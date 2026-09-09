"""Deterministic Alpha report. Reads exported evidence; never places orders or calls AI.

Usage: python daily_employee.py --input packet.json --output report.json
  --source PROSETUPS_1=path --source PROSETUPS_2=path --source RECENT_LISTINGS=path
"""
import argparse
import hashlib
import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path


def load_universes(paths):
    sources, memberships = {}, {}
    for name, path in sorted(paths.items()):
        raw = Path(path).read_bytes()
        tokens = [s.strip().upper() for s in re.split(r'[,\r\n]+', raw.decode('utf-8-sig')) if s.strip()]
        bad = [s for s in tokens if not re.fullmatch(r'(NSE|BSE):[A-Z0-9&_.-]+', s)]
        if bad:
            raise ValueError(f'{name}: malformed symbols; import blocked')
        unique = sorted(set(tokens))
        if not unique:
            raise ValueError(f'{name}: empty source; import blocked')
        sources[name] = {'sha256': hashlib.sha256(raw).hexdigest(),
                         'entries': len(tokens), 'unique': len(unique),
                         'duplicate_entries': len(tokens)-len(unique),
                         'source_kind': 'USER_EXPORTED_SNAPSHOT',
                         'live_feed_verified': False}
        for symbol in unique:
            memberships.setdefault(symbol, []).append(name)
    return sources, memberships


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('missing timestamp')
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('timestamp must include timezone')
    return result


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def build_report(packet, sources, memberships, now=None):
    if packet.get('schema_version') != 'ALPHA_EMPLOYEE_INPUT_V1':
        raise ValueError('unsupported input schema')
    if packet.get('project_ref') != 'rclbninptekxitkdtmrs':
        raise ValueError('wrong Supabase project')
    captured = timestamp(packet.get('captured_at'))
    now = now or datetime.now(timezone.utc)
    if captured > now:
        raise ValueError('future observation rejected')
    required = ['broker_sync', 'holdings', 'census', 'features', 'worker_attempt',
                'learning_event', 'curiosity', 'tournament', 'session_lock']
    if any(key not in packet for key in required):
        raise ValueError('incomplete input envelope')
    if not isinstance(packet['holdings'], list) or not isinstance(packet['features'], list):
        raise ValueError('holdings/features must be arrays')
    blocked = ['LIVE_TRADE_FRESHNESS_NOT_CERTIFIED', 'CASH_FLOW_RECONCILIATION_MISSING',
               'COMPARABLE_BENCHMARK_SERIES_MISSING', 'HISTORICAL_BEGINNING_WEIGHTS_MISSING',
               'AUTOMATED_CHARTINK_CAPTURE_NOT_VERIFIED']
    broker = packet['broker_sync'] or {}
    if broker.get('status') != 'SUCCESS':
        blocked.append('LATEST_BROKER_SYNC_NOT_SUCCESSFUL')
    cash = broker.get('cash_available')
    if not number(cash):
        cash = None
        blocked.append('BROKER_CASH_MISSING')
    holdings = []
    for row in packet['holdings']:
        item = {key: row.get(key) for key in ['ticker', 'quantity', 'market_value', 'snapshot_at']}
        item['action'] = 'NOT_GENERATED'
        item['contribution'] = None
        if not number(item['market_value']) or not number(item['quantity']):
            blocked.append('HOLDING_VALUATION_MISSING')
        try:
            if timestamp(item['snapshot_at']) > captured:
                raise ValueError('future holdings snapshot')
        except ValueError:
            blocked.append('HOLDING_TIMESTAMP_INVALID')
        holdings.append(item)
    holdings.sort(key=lambda x: x.get('ticker') or '')
    holdings.append({'ticker': 'CASH', 'market_value': cash, 'action': 'NOT_GENERATED', 'contribution': None})
    census = packet['census'] or {}
    observations, matched = [], set()
    for row in packet['features']:
        # NSE census cannot validate a BSE symbol by coincidental ticker spelling.
        symbol = 'NSE:' + str(row.get('symbol', '')).upper()
        if symbol not in memberships:
            continue
        if row.get('trade_date') != census.get('trade_date'):
            raise ValueError('mixed census dates')
        if timestamp(row.get('calculated_at')) > captured:
            raise ValueError('future market feature rejected')
        matched.add(symbol)
        observations.append({key: row.get(key) for key in [
            'symbol', 'series', 'trade_date', 'close', 'eligible', 'census_rank',
            'return_5d_pct', 'return_20d_pct', 'calculated_at']}
            | {'sources': memberships[symbol], 'capital_authority': False})
    observations.sort(key=lambda x: (x['census_rank'] is None, x['census_rank'] or 0, x['symbol'], x['series'] or ''))
    worker = packet['worker_attempt'] or {}
    if worker.get('status') != 'succeeded':
        blocked.append('LATEST_WORKER_ATTEMPT_NOT_SUCCESSFUL')
    tournament = packet['tournament'] or {}
    if tournament.get('trade_date') != packet.get('trade_date'):
        blocked.append('CURRENT_DAY_TOURNAMENT_MISSING')
    for source in sources:
        sources[source] = dict(sources[source], census_matches=sum(
            source in memberships[symbol] for symbol in matched))
    report = {'schema_version': 'ALPHA_EMPLOYEE_REPORT_V1', 'captured_at': packet['captured_at'],
        'trade_date': packet['trade_date'], 'project_ref': packet['project_ref'],
        'status': 'DATA_BLOCKED', 'capital_authority': False, 'paid_ai_calls': 0,
        'input_sha256': hashlib.sha256(json.dumps(packet, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'sources': sources, 'unique_universe_symbols': len(memberships),
        'census': census, 'matched_universe_symbols': len(matched),
        'unmatched_symbols': sorted(set(memberships)-matched),
        'ranked_research_candidates': [x for x in observations if x['eligible'] and x['census_rank'] is not None][:20],
        'portfolio_and_cash': holdings, 'broker_sync': broker,
        'tournament': tournament, 'session_lock': packet['session_lock'],
        'worker_attempt': worker, 'learning_event': packet['learning_event'],
        'curiosity': packet['curiosity'], 'blocked_reasons': sorted(set(blocked)),
        'performance': {'status': 'DATA_BLOCKED', 'twr': None, 'benchmark_return': None,
                        'excess_return': None, 'selection_vs_allocation': None},
        'delivery': {'scheduled': False, 'production_record_id': None,
                     'chatgpt_readback_verified': False}}
    report['report_sha256'] = hashlib.sha256(json.dumps(report, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--source', action='append', required=True)
    args = parser.parse_args()
    pairs = [value.split('=', 1) for value in args.source]
    if any(len(pair) != 2 for pair in pairs) or len(dict(pairs)) != len(pairs):
        raise ValueError('source names must be unique NAME=path arguments')
    sources, memberships = load_universes(dict(pairs))
    packet = json.loads(Path(args.input).read_text(encoding='utf-8-sig'))
    report = build_report(packet, sources, memberships)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    if json.loads(output.read_text(encoding='utf-8')) != report:
        raise RuntimeError('saved report read-back failed')
    print(json.dumps({'saved_local': str(output.resolve()), 'sha256': report['report_sha256'],
        'status': report['status'], 'matched': report['matched_universe_symbols'],
        'universe': report['unique_universe_symbols'], 'production_saved': False}))


if __name__ == '__main__':
    main()
