begin;

create extension if not exists pgcrypto;

create table if not exists public.alpha_runtime_policy (
  policy_key text primary key,
  policy_value jsonb not null,
  effective_at timestamptz not null default now(),
  version text not null,
  updated_at timestamptz not null default now()
);

insert into public.alpha_runtime_policy(policy_key, policy_value, version)
values
('EXECUTION_BROKER_MAX_AGE_SECONDS', jsonb_build_object('value',300), 'PREOPEN_LOCK_V1'),
('EXECUTION_PRICE_MAX_AGE_SECONDS', jsonb_build_object('value',300), 'PREOPEN_LOCK_V1'),
('MONITOR_QUOTE_MAX_AGE_SECONDS', jsonb_build_object('value',600), 'PREOPEN_LOCK_V1'),
('CONTROL_ROOM_BROKER_WARNING_SECONDS', jsonb_build_object('value',900), 'PREOPEN_LOCK_V1'),
('LOCKED_PLAN_MONITOR_MAX_AGE_SECONDS', jsonb_build_object('value',600), 'PREOPEN_LOCK_V1')
on conflict(policy_key) do update set policy_value=excluded.policy_value, version=excluded.version, updated_at=now();

create or replace function public.alpha_runtime_policy_number(p_key text)
returns numeric
language sql
stable
set search_path to 'public'
as $$
  select nullif(policy_value->>'value','')::numeric
  from public.alpha_runtime_policy
  where policy_key=p_key
  limit 1
$$;

create table if not exists public.alpha_preopen_rankings (
  id uuid primary key default gen_random_uuid(),
  trade_date date not null,
  ticker text not null,
  rank integer not null check(rank > 0),
  tier text not null check(tier in ('P1','P2','IGNORE')),
  research_priority_score numeric,
  setup_conviction numeric,
  business_quality_score numeric,
  trade_quality_score numeric,
  institutional_confirmations integer not null default 0 check(institutional_confirmations >= 0),
  institutional_confirmation_detail jsonb not null default '[]'::jsonb,
  cmp numeric,
  target_price numeric,
  expected_upside_pct numeric,
  bear_return_pct numeric,
  base_return_pct numeric,
  bull_return_pct numeric,
  bear_probability numeric,
  base_probability numeric,
  bull_probability numeric,
  probability_weighted_return_pct numeric,
  expected_portfolio_contribution numeric,
  rs_vs_nifty_state text,
  rs_vs_nifty_value numeric,
  volume_signature text,
  distance_from_primary_trigger_pct numeric,
  research_coverage_id uuid,
  underwriting_id uuid,
  decision_id uuid,
  authorization_state text not null check(authorization_state in ('RESEARCH_ONLY','CAPITAL_BLOCKED','PREAUTHORIZED','CAPITAL_READY','IGNORE_SESSION')),
  block_reasons text[] not null default '{}',
  loss_of_priority_conditions jsonb not null default '[]'::jsonb,
  material_rerank_conditions jsonb not null default '[]'::jsonb,
  no_intraday_promotion boolean not null default true,
  locked_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(trade_date,ticker)
);

create table if not exists public.alpha_campaign_routes (
  id uuid primary key default gen_random_uuid(),
  trade_date date not null,
  ticker text not null,
  campaign_id text not null,
  route_key text not null,
  route_name text not null,
  route_priority integer not null check(route_priority > 0),
  exclusive_group text not null,
  authorization_state text not null check(authorization_state in ('RESEARCH_ONLY','PREAUTHORIZED','CAPITAL_READY','BLOCKED','CANCELLED','EXECUTED','MUTEX_CANCELLED','SESSION_INVALIDATED','EXPIRED')),
  runtime_state text not null default 'LOCKED' check(runtime_state in ('LOCKED','WATCHING','TEST_SEEN','RECLAIM_PENDING','TRIGGER_READY','AWAITING_APPROVAL','APPROVED','EXECUTED','INVALIDATED','MUTEX_CANCELLED','SESSION_CANCELLED','EXPIRED')),
  trigger_type text not null check(trigger_type in ('PRICE_ABOVE','PRICE_BELOW','PRICE_RANGE','TEST_AND_RECLAIM','BREAKOUT_ACCEPTANCE','CUSTOM_STATE_MACHINE')),
  trigger_params jsonb not null,
  entry_low numeric,
  entry_high numeric,
  model_entry numeric,
  structural_stop numeric not null,
  target_price numeric not null,
  shares bigint,
  rupee_amount numeric,
  planned_loss_rupees numeric,
  structural_downside_pct numeric,
  portfolio_risk_fraction numeric,
  upside_pct numeric,
  rr_ratio numeric,
  setup_conviction numeric,
  expected_hold_sessions integer,
  expected_hold_text text,
  acceptance_rule jsonb not null default '{}'::jsonb,
  market_context_rule jsonb not null default '{}'::jsonb,
  volume_rule jsonb not null default '{}'::jsonb,
  session_kill_rule jsonb not null default '{}'::jsonb,
  route_cancel_rule jsonb not null default '{}'::jsonb,
  requires_human_approval boolean not null default true,
  source_underwriting_id uuid,
  source_decision_id uuid,
  source_ranking_id uuid references public.alpha_preopen_rankings(id) on delete set null,
  valid_from timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(trade_date,ticker,route_key),
  check(entry_low is null or entry_high is null or entry_low <= entry_high),
  check(model_entry is null or structural_stop < model_entry),
  check(model_entry is null or target_price > model_entry),
  check(rr_ratio is null or rr_ratio >= 0)
);

create table if not exists public.alpha_session_capital_lock (
  trade_date date primary key,
  lock_id uuid not null default gen_random_uuid(),
  status text not null check(status in ('DRAFT','LOCKED','TRIGGERED','EXECUTED','CANCELLED','EXPIRED','KEEP_CASH','DATA_BLOCKED')),
  capital_owner_ticker text,
  capital_owner_campaign_id text,
  max_fresh_campaigns integer not null default 1 check(max_fresh_campaigns >= 0),
  fresh_campaigns_executed integer not null default 0 check(fresh_campaigns_executed >= 0),
  total_cash_available numeric,
  cash_reserved numeric,
  cash_remaining numeric,
  total_nav numeric,
  reroute_allowed boolean not null default false,
  intraday_new_destination_allowed boolean not null default false,
  executed_route_id uuid references public.alpha_campaign_routes(id),
  executed_decision_id uuid,
  session_invalidation_reason text,
  locked_at timestamptz,
  expires_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(fresh_campaigns_executed <= max_fresh_campaigns)
);

create table if not exists public.alpha_route_evaluations (
  id bigint generated always as identity primary key,
  route_id uuid not null references public.alpha_campaign_routes(id) on delete cascade,
  trade_date date not null,
  ticker text not null,
  evaluated_at timestamptz not null default now(),
  price numeric,
  price_at timestamptz,
  bar_interval text,
  bar_open numeric,
  bar_high numeric,
  bar_low numeric,
  bar_close numeric,
  bar_volume numeric,
  market_context jsonb not null default '{}'::jsonb,
  volume_context jsonb not null default '{}'::jsonb,
  prior_state text,
  new_state text,
  trigger_result boolean,
  invalidation_result boolean,
  reason_codes text[] not null default '{}',
  evidence jsonb not null default '{}'::jsonb,
  source text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists alpha_one_executed_route_per_mutex_group
on public.alpha_campaign_routes(trade_date, exclusive_group)
where runtime_state='EXECUTED';

create index if not exists alpha_campaign_routes_trade_ticker_idx
on public.alpha_campaign_routes(trade_date,ticker,route_priority);

create index if not exists alpha_route_evaluations_route_time_idx
on public.alpha_route_evaluations(route_id,evaluated_at);

create or replace function public.alpha_emit_brain_event(
  p_event_type text,
  p_entity_type text,
  p_entity_key text,
  p_payload jsonb
) returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if to_regclass('public.brain_events') is not null then
    insert into public.brain_events(event_type,entity_type,entity_key,payload)
    values(p_event_type,p_entity_type,p_entity_key,p_payload);
  end if;
end;
$$;

create or replace function public.alpha_lock_session_capital(
  p_trade_date date,
  p_capital_owner_ticker text,
  p_campaign_id text,
  p_total_cash numeric,
  p_cash_reserved numeric,
  p_total_nav numeric,
  p_expires_at timestamptz,
  p_created_by text default 'SYSTEM'
) returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_row public.alpha_session_capital_lock%rowtype;
begin
  if p_trade_date is null then raise exception 'trade_date required'; end if;
  if p_capital_owner_ticker is null or btrim(p_capital_owner_ticker)='' then raise exception 'capital owner required'; end if;
  if p_total_nav is null or p_total_nav<=0 then raise exception 'total_nav invalid'; end if;
  if p_total_cash is null or p_total_cash<0 then raise exception 'cash invalid'; end if;
  if p_cash_reserved is null or p_cash_reserved<0 or p_cash_reserved>p_total_cash then raise exception 'cash_reserved invalid'; end if;

  insert into public.alpha_session_capital_lock(
    trade_date,status,capital_owner_ticker,capital_owner_campaign_id,max_fresh_campaigns,
    fresh_campaigns_executed,total_cash_available,cash_reserved,cash_remaining,total_nav,
    reroute_allowed,intraday_new_destination_allowed,locked_at,expires_at,created_by
  ) values(
    p_trade_date,'LOCKED',upper(p_capital_owner_ticker),p_campaign_id,1,0,p_total_cash,p_cash_reserved,
    p_total_cash-p_cash_reserved,p_total_nav,false,false,now(),p_expires_at,p_created_by
  )
  on conflict(trade_date) do update set
    status='LOCKED',
    capital_owner_ticker=excluded.capital_owner_ticker,
    capital_owner_campaign_id=excluded.capital_owner_campaign_id,
    max_fresh_campaigns=1,
    fresh_campaigns_executed=0,
    total_cash_available=excluded.total_cash_available,
    cash_reserved=excluded.cash_reserved,
    cash_remaining=excluded.cash_remaining,
    total_nav=excluded.total_nav,
    reroute_allowed=false,
    intraday_new_destination_allowed=false,
    executed_route_id=null,
    executed_decision_id=null,
    session_invalidation_reason=null,
    locked_at=now(),
    expires_at=excluded.expires_at,
    created_by=excluded.created_by,
    updated_at=now()
  returning * into v_row;

  perform public.alpha_emit_brain_event('SESSION_CAPITAL_LOCKED','SYSTEM',p_trade_date::text,
    jsonb_build_object('trade_date',p_trade_date,'capital_owner',upper(p_capital_owner_ticker),'campaign_id',p_campaign_id,
      'cash_reserved',p_cash_reserved,'total_cash',p_total_cash,'total_nav',p_total_nav,'reroute_allowed',false,'capital_authority',false));
  return to_jsonb(v_row);
end;
$$;

create or replace function public.alpha_create_campaign_route(
  p_trade_date date,
  p_ticker text,
  p_campaign_id text,
  p_route_key text,
  p_route_name text,
  p_route_priority integer,
  p_exclusive_group text,
  p_trigger_type text,
  p_trigger_params jsonb,
  p_entry_low numeric,
  p_entry_high numeric,
  p_model_entry numeric,
  p_structural_stop numeric,
  p_target_price numeric,
  p_setup_conviction numeric,
  p_volume_rule jsonb,
  p_session_kill_rule jsonb,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_rr numeric;
  v_up numeric;
  v_down numeric;
  v_state text;
  v_row public.alpha_campaign_routes%rowtype;
begin
  if p_model_entry is null or p_structural_stop is null or p_target_price is null then raise exception 'entry/stop/target required'; end if;
  if not (p_structural_stop < p_model_entry and p_model_entry < p_target_price) then raise exception 'invalid geometry'; end if;
  v_rr := (p_target_price-p_model_entry)/(p_model_entry-p_structural_stop);
  v_up := 100*(p_target_price/p_model_entry-1);
  v_down := 100*(p_model_entry-p_structural_stop)/p_model_entry;
  v_state := case
    when upper(coalesce(p_volume_rule->>'status','DEFINED'))='UNDEFINED_BLOCKING' then 'PREAUTHORIZED'
    else 'CAPITAL_READY'
  end;

  insert into public.alpha_campaign_routes(
    trade_date,ticker,campaign_id,route_key,route_name,route_priority,exclusive_group,
    authorization_state,runtime_state,trigger_type,trigger_params,entry_low,entry_high,model_entry,
    structural_stop,target_price,structural_downside_pct,upside_pct,rr_ratio,setup_conviction,
    volume_rule,session_kill_rule,requires_human_approval,valid_from,expires_at
  ) values(
    p_trade_date,upper(p_ticker),p_campaign_id,p_route_key,p_route_name,p_route_priority,p_exclusive_group,
    v_state,'LOCKED',upper(p_trigger_type),coalesce(p_trigger_params,'{}'::jsonb),p_entry_low,p_entry_high,p_model_entry,
    p_structural_stop,p_target_price,v_down,v_up,v_rr,p_setup_conviction,
    coalesce(p_volume_rule,'{}'::jsonb),coalesce(p_session_kill_rule,'{}'::jsonb),true,now(),p_expires_at
  )
  on conflict(trade_date,ticker,route_key) do update set
    route_name=excluded.route_name,route_priority=excluded.route_priority,exclusive_group=excluded.exclusive_group,
    authorization_state=excluded.authorization_state,runtime_state='LOCKED',trigger_type=excluded.trigger_type,
    trigger_params=excluded.trigger_params,entry_low=excluded.entry_low,entry_high=excluded.entry_high,
    model_entry=excluded.model_entry,structural_stop=excluded.structural_stop,target_price=excluded.target_price,
    structural_downside_pct=excluded.structural_downside_pct,upside_pct=excluded.upside_pct,rr_ratio=excluded.rr_ratio,
    setup_conviction=excluded.setup_conviction,volume_rule=excluded.volume_rule,session_kill_rule=excluded.session_kill_rule,
    valid_from=now(),expires_at=excluded.expires_at,updated_at=now()
  returning * into v_row;

  perform public.alpha_emit_brain_event('CAMPAIGN_ROUTE_CREATED','TICKER',upper(p_ticker),
    jsonb_build_object('route_id',v_row.id,'trade_date',p_trade_date,'route_key',p_route_key,'exclusive_group',p_exclusive_group,
      'authorization_state',v_row.authorization_state,'rr',v_rr,'capital_authority',false));
  return to_jsonb(v_row);
end;
$$;

create or replace function public.alpha_evaluate_campaign_route(
  p_route_id uuid,
  p_price numeric,
  p_price_at timestamptz default now(),
  p_bar_low numeric default null,
  p_bar_high numeric default null,
  p_bar_volume numeric default null,
  p_source text default 'ROUTE_EVALUATOR'
) returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  r public.alpha_campaign_routes%rowtype;
  l public.alpha_session_capital_lock%rowtype;
  v_prior text;
  v_new text;
  v_trigger boolean := false;
  v_invalid boolean := false;
  v_reasons text[] := '{}';
  v_kill_type text;
  v_kill_level numeric;
  v_test_low numeric;
  v_test_high numeric;
  v_reclaim numeric;
  v_breakout numeric;
  v_entry_high numeric;
  v_volume_status text;
begin
  select * into r from public.alpha_campaign_routes where id=p_route_id for update;
  if not found then raise exception 'route not found'; end if;
  select * into l from public.alpha_session_capital_lock where trade_date=r.trade_date for update;
  if not found then raise exception 'session lock missing'; end if;

  v_prior := r.runtime_state;
  v_new := v_prior;

  if l.status not in ('LOCKED','TRIGGERED') then
    v_new := case when l.status='EXECUTED' then 'SESSION_CANCELLED' else 'INVALIDATED' end;
    v_reasons := array_append(v_reasons,'SESSION_NOT_OPEN_FOR_FRESH_CAPITAL');
  elsif upper(coalesce(l.capital_owner_ticker,'')) <> upper(r.ticker) then
    v_new := 'SESSION_CANCELLED';
    v_reasons := array_append(v_reasons,'NOT_SESSION_CAPITAL_OWNER');
  elsif r.expires_at is not null and r.expires_at <= now() then
    v_new := 'EXPIRED';
    v_reasons := array_append(v_reasons,'ROUTE_EXPIRED');
  else
    v_kill_type := upper(coalesce(r.session_kill_rule->>'type',''));
    v_kill_level := nullif(r.session_kill_rule->>'level','')::numeric;
    if v_kill_type='PRICE_BELOW_OR_EQUAL' and v_kill_level is not null and least(coalesce(p_bar_low,p_price),p_price) <= v_kill_level then
      v_invalid := true;
      v_new := 'INVALIDATED';
      v_reasons := array_append(v_reasons,'SESSION_KILL_PRICE_FIRED');
      update public.alpha_session_capital_lock set status='KEEP_CASH',session_invalidation_reason='SESSION_KILL_PRICE_FIRED',updated_at=now() where trade_date=r.trade_date;
      update public.alpha_campaign_routes set runtime_state='INVALIDATED',authorization_state='SESSION_INVALIDATED',updated_at=now()
      where trade_date=r.trade_date and exclusive_group=r.exclusive_group and runtime_state not in ('EXECUTED','MUTEX_CANCELLED','SESSION_CANCELLED','EXPIRED');
      perform public.alpha_emit_brain_event('CAMPAIGN_ROUTE_INVALIDATED','TICKER',r.ticker,
        jsonb_build_object('route_id',r.id,'reason','SESSION_KILL_PRICE_FIRED','price',p_price,'kill_level',v_kill_level,'capital_authority',false));
    else
      v_volume_status := upper(coalesce(r.volume_rule->>'status','DEFINED'));
      if v_volume_status='UNDEFINED_BLOCKING' then
        v_reasons := array_append(v_reasons,'VOLUME_ACCEPTANCE_RULE_NOT_NUMERIC');
      end if;

      if r.trigger_type='TEST_AND_RECLAIM' then
        v_test_low := nullif(r.trigger_params->>'test_low','')::numeric;
        v_test_high := nullif(r.trigger_params->>'test_high','')::numeric;
        v_reclaim := nullif(r.trigger_params->>'reclaim_level','')::numeric;
        if v_prior in ('LOCKED','WATCHING') and v_test_low is not null and v_test_high is not null and p_price between v_test_low and v_test_high then
          v_new := 'TEST_SEEN';
          v_reasons := array_append(v_reasons,'SUPPORT_TEST_SEEN');
        elsif v_prior in ('TEST_SEEN','RECLAIM_PENDING') and v_reclaim is not null and p_price >= v_reclaim then
          if v_volume_status='UNDEFINED_BLOCKING' then
            v_new := 'AWAITING_APPROVAL';
            v_reasons := array_append(v_reasons,'PRICE_RECLAIM_MET_BUT_SUBJECTIVE_GATE_BLOCKS_AUTO_AUTH');
          else
            v_new := 'TRIGGER_READY'; v_trigger := true;
            v_reasons := array_append(v_reasons,'TEST_AND_RECLAIM_TRIGGERED');
          end if;
        elsif v_prior='TEST_SEEN' then
          v_new := 'RECLAIM_PENDING';
        end if;
      elsif r.trigger_type='BREAKOUT_ACCEPTANCE' then
        v_breakout := nullif(r.trigger_params->>'breakout_level','')::numeric;
        v_entry_high := coalesce(r.entry_high,nullif(r.trigger_params->>'max_entry','')::numeric);
        if v_breakout is not null and p_price >= v_breakout and (v_entry_high is null or p_price <= v_entry_high) then
          if v_volume_status='UNDEFINED_BLOCKING' then
            v_new := 'AWAITING_APPROVAL';
            v_reasons := array_append(v_reasons,'BREAKOUT_PRICE_MET_BUT_SUBJECTIVE_GATE_BLOCKS_AUTO_AUTH');
          else
            v_new := 'TRIGGER_READY'; v_trigger := true;
            v_reasons := array_append(v_reasons,'BREAKOUT_TRIGGERED');
          end if;
        else
          v_new := case when v_prior='LOCKED' then 'WATCHING' else v_prior end;
        end if;
      elsif r.trigger_type='PRICE_ABOVE' then
        v_breakout := nullif(r.trigger_params->>'level','')::numeric;
        if v_breakout is not null and p_price>=v_breakout then v_new:='TRIGGER_READY'; v_trigger:=true; end if;
      elsif r.trigger_type='PRICE_BELOW' then
        v_breakout := nullif(r.trigger_params->>'level','')::numeric;
        if v_breakout is not null and p_price<=v_breakout then v_new:='TRIGGER_READY'; v_trigger:=true; end if;
      elsif r.trigger_type='PRICE_RANGE' then
        v_test_low := nullif(r.trigger_params->>'low','')::numeric;
        v_test_high := nullif(r.trigger_params->>'high','')::numeric;
        if v_test_low is not null and v_test_high is not null and p_price between v_test_low and v_test_high then v_new:='TRIGGER_READY'; v_trigger:=true; end if;
      end if;
    end if;
  end if;

  if not v_invalid then
    update public.alpha_campaign_routes set runtime_state=v_new,updated_at=now() where id=r.id;
  end if;

  insert into public.alpha_route_evaluations(route_id,trade_date,ticker,price,price_at,bar_low,bar_high,bar_volume,prior_state,new_state,trigger_result,invalidation_result,reason_codes,evidence,source)
  values(r.id,r.trade_date,r.ticker,p_price,p_price_at,p_bar_low,p_bar_high,p_bar_volume,v_prior,v_new,v_trigger,v_invalid,v_reasons,
    jsonb_build_object('trigger_type',r.trigger_type,'trigger_params',r.trigger_params,'session_kill_rule',r.session_kill_rule),p_source);

  if v_new='TRIGGER_READY' then
    update public.alpha_session_capital_lock set status='TRIGGERED',updated_at=now() where trade_date=r.trade_date and status='LOCKED';
    perform public.alpha_emit_brain_event('CAMPAIGN_ROUTE_TRIGGERED','TICKER',r.ticker,
      jsonb_build_object('route_id',r.id,'route_key',r.route_key,'price',p_price,'capital_authority',false,'requires_human_approval',true));
  elsif v_prior is distinct from v_new and v_new='TEST_SEEN' then
    perform public.alpha_emit_brain_event('CAMPAIGN_ROUTE_TEST_SEEN','TICKER',r.ticker,
      jsonb_build_object('route_id',r.id,'route_key',r.route_key,'price',p_price,'capital_authority',false));
  end if;

  return jsonb_build_object('route_id',r.id,'ticker',r.ticker,'prior_state',v_prior,'new_state',v_new,'trigger_result',v_trigger,'invalidation_result',v_invalid,'reason_codes',v_reasons);
end;
$$;

create or replace function public.alpha_claim_route_execution(
  p_route_id uuid,
  p_decision_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  r public.alpha_campaign_routes%rowtype;
  l public.alpha_session_capital_lock%rowtype;
begin
  select * into r from public.alpha_campaign_routes where id=p_route_id for update;
  if not found then raise exception 'route not found'; end if;
  select * into l from public.alpha_session_capital_lock where trade_date=r.trade_date for update;
  if not found then raise exception 'session lock missing'; end if;

  if l.status not in ('TRIGGERED','LOCKED') then raise exception 'SESSION_NOT_EXECUTABLE'; end if;
  if l.fresh_campaigns_executed >= l.max_fresh_campaigns then raise exception 'MAX_FRESH_CAMPAIGNS_REACHED'; end if;
  if upper(coalesce(l.capital_owner_ticker,'')) <> upper(r.ticker) then raise exception 'NOT_CAPITAL_OWNER'; end if;
  if r.runtime_state not in ('TRIGGER_READY','AWAITING_APPROVAL','APPROVED') then raise exception 'ROUTE_NOT_TRIGGER_READY'; end if;

  update public.alpha_campaign_routes
    set runtime_state='EXECUTED',authorization_state='EXECUTED',updated_at=now()
  where id=r.id;

  update public.alpha_campaign_routes
    set runtime_state='MUTEX_CANCELLED',authorization_state='MUTEX_CANCELLED',updated_at=now()
  where trade_date=r.trade_date and exclusive_group=r.exclusive_group and id<>r.id
    and runtime_state not in ('EXECUTED','INVALIDATED','EXPIRED','SESSION_CANCELLED');

  update public.alpha_session_capital_lock
    set status='EXECUTED',fresh_campaigns_executed=fresh_campaigns_executed+1,
        executed_route_id=r.id,executed_decision_id=p_decision_id,updated_at=now()
  where trade_date=r.trade_date;

  perform public.alpha_emit_brain_event('CAMPAIGN_ROUTE_MUTEX_CANCELLED','SYSTEM',r.exclusive_group,
    jsonb_build_object('executed_route_id',r.id,'trade_date',r.trade_date,'ticker',r.ticker,'capital_authority',false));
  perform public.alpha_emit_brain_event('SESSION_CAPITAL_EXECUTED','TICKER',r.ticker,
    jsonb_build_object('route_id',r.id,'decision_id',p_decision_id,'trade_date',r.trade_date,'human_approval_required',true));

  return jsonb_build_object('ok',true,'route_id',r.id,'trade_date',r.trade_date,'ticker',r.ticker,'session_status','EXECUTED');
end;
$$;

create or replace function public.alpha_expire_session_routes(p_trade_date date)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_count integer;
begin
  update public.alpha_campaign_routes
  set runtime_state='EXPIRED',authorization_state='EXPIRED',updated_at=now()
  where trade_date=p_trade_date and runtime_state not in ('EXECUTED','MUTEX_CANCELLED','INVALIDATED','SESSION_CANCELLED','EXPIRED');
  get diagnostics v_count = row_count;

  update public.alpha_session_capital_lock
  set status=case when status='EXECUTED' then status else 'EXPIRED' end,updated_at=now()
  where trade_date=p_trade_date;

  return jsonb_build_object('ok',true,'trade_date',p_trade_date,'expired_routes',v_count);
end;
$$;

commit;
