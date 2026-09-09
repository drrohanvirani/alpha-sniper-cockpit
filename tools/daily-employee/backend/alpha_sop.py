"""One read-only Alpha SOP packet rendered as tables. No external dependencies."""
import argparse
import html
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

SECTIONS = [
 ('overview','1. Current status'),
 ('portfolio','2. Every holding plus CASH'),
 ('tournament','3. Existing portfolio-versus-cash tournament'),
 ('research_candidates','4. Top 20 census research candidates - not BUY recommendations'),
 ('routes','5. Stored routes for today - not confirmed GTT orders'),
 ('session_lock','6. Capital lock for today'),
 ('telegram','7. Latest three Telegram distillation runs'),
 ('telegram_verification','8. Telegram leads versus primary verification'),
 ('paper_trades','9. Latest 20 paper trades - never real positions'),
 ('eod_runs','10. Latest three EOD scoring runs'),
 ('outcome_coverage','11. Outcome coverage by lane, prospective status and horizon'),
 ('recent_outcomes','12. Latest 20 trade outcomes - separated by lane'),
 ('learning_proposals','13. Latest ten proposed lessons - not automatically applied'),
 ('learning','14. Latest three learning scorecard events'),
 ('curiosity','15. Up to 20 curiosity questions and recorded answers'),
 ('source_gaps','16. Source integration gaps'),
 ('jobs','17. Latest scheduled job attempts'),
 ('sop_phases','18. Latest ten SOP phases'),
]

def cell(value):
    if value is None: return 'NOT AVAILABLE'
    if isinstance(value, bool): return 'YES' if value else 'NO'
    if isinstance(value,(list,dict)):
        value=json.dumps(value,ensure_ascii=False,sort_keys=True)
    return html.escape(str(value),quote=False).replace('|','&#124;').replace('\r','').replace('\n','<br>')

def render(report, now=None):
    if report.get('schema_version')!='ALPHA_SOP_V1':
        raise ValueError('Unsupported SOP version')
    if report.get('project_ref')!='rclbninptekxitkdtmrs':
        raise ValueError('Wrong project')
    if report.get('report_mode')!='READ_ONLY_EVIDENCE_NOT_ORDER_AUTHORIZATION':
        raise ValueError('Unexpected authority mode')
    asof=datetime.fromisoformat(report['as_of'].replace('Z','+00:00'))
    if asof.tzinfo is None or asof>(now or datetime.now(timezone.utc)):
        raise ValueError('Invalid/future snapshot timestamp')
    lines=['# Alpha SOP - one tabulated report','',
      'Snapshot: '+asof.astimezone(timezone(timedelta(hours=5,minutes=30))).isoformat()+' (IST).',
      'Source: '+report['project_ref']+'. Historical records retain their own dates.',
      'Read-only evidence. This run did not scan again, create trades, change orders or certify an automated full day.',
      'Stored states and routes are not new recommendations. Missing data stays missing.','']
    for key,title in SECTIONS:
        if key not in report or not isinstance(report[key],list):
            raise ValueError('Missing/invalid section: '+key)
        rows=report[key]
        if any(not isinstance(row,dict) for row in rows): raise ValueError('Invalid rows: '+key)
        lines+=['## '+title,'']
        if not rows:
            lines+=['| Result |','|---|','| NO RECORDS RETURNED - no result invented |','']
            continue
        cols=list(dict.fromkeys(k for row in rows for k in row))
        lines+=['| '+' | '.join(cell(k.replace('_',' ')) for k in cols)+' |',
                '| '+' | '.join('---' for _ in cols)+' |']
        lines+=['| '+' | '.join(cell(row.get(k)) for k in cols)+' |' for row in rows]
        lines+=['']
    return '\n'.join(lines)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--input',required=True);p.add_argument('--output',required=True)
    args=p.parse_args()
    report=json.loads(Path(args.input).read_text(encoding='utf-8-sig'))
    text=render(report)
    out=Path(args.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(text,encoding='utf-8')
    if out.read_text(encoding='utf-8')!=text: raise RuntimeError('Read-back failed')
    print(json.dumps({'saved':str(out.resolve()),'tables':len(SECTIONS),'production_modified':False}))

if __name__=='__main__': main()
