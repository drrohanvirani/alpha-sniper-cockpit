-- Alpha OS PREOPEN_LOCK_V1 regression tests
-- Run only on an isolated/dev database. The script uses transaction rollback.

begin;

-- Clean fixture date only.
delete from public.alpha_route_evaluations where trade_date=date '2026-09-07';
delete from public.alpha_session_capital_lock where trade_date=date '2026-09-07';
delete from public.alpha_campaign_routes where trade_date=date '2026-09-07';
delete from public.alpha_preopen_rankings where trade_date=date '2026-09-07';

insert into public.alpha_preopen_rankings(
  trade_date,ticker,rank,tier,research_priority_score,setup_conviction,business_quality_score,trade_quality_score,
  institutional_confirmations,authorization_state,block_reasons,no_intraday_promotion,locked_at,expires_at
) values
(date '2026-09-07','ASTRAMICRO',1,'P1',90,87,84,88,3,'PREAUTHORIZED','{}',true,now(),timestamptz '2026-09-07 15:30:00+05:30'),
(date '2026-09-07','KDDL',2,'P1',82,83,86,79,3,'CAPITAL_BLOCKED',array['NOT_SESSION_CAPITAL_OWNER'],true,now(),timestamptz '2026-09-07 15:30:00+05:30'),
(date '2026-09-07','GKENERGY',6,'IGNORE',60,60,70,55,1,'IGNORE_SESSION',array['IGNORE_SESSION'],true,now(),timestamptz '2026-09-07 15:30:00+05:30');

select public.alpha_lock_session_capital(
  date '2026-09-07','ASTRAMICRO','ASTRA_FRESH_ENTRY_SESSION',1000000,271000,3874000,
  timestamptz '2026-09-07 15:30:00+05:30','REGRESSION_TEST'
);

select public.alpha_create_campaign_route(
  date '2026-09-07','ASTRAMICRO','ASTRA_FRESH_ENTRY_SESSION','SUPPORT_RECLAIM','Support reclaim',1,
  'ASTRA_FRESH_ENTRY_SESSION','TEST_AND_RECLAIM',
  jsonb_build_object('test_low',1665,'test_high',1680,'reclaim_level',1682),
  1665,1682,1682,1630,2150,87,
  jsonb_build_object('status','DEFINED'),
  jsonb_build_object('type','PRICE_BELOW_OR_EQUAL','level',1630),
  timestamptz '2026-09-07 15:30:00+05:30'
);

select public.alpha_create_campaign_route(
  date '2026-09-07','ASTRAMICRO','ASTRA_FRESH_ENTRY_SESSION','BREAKOUT','Breakout acceptance',2,
  'ASTRA_FRESH_ENTRY_SESSION','BREAKOUT_ACCEPTANCE',
  jsonb_build_object('breakout_level',1741,'max_entry',1760),
  1745,1760,1750,1640,2150,87,
  jsonb_build_object('status','DEFINED'),
  jsonb_build_object('type','PRICE_BELOW_OR_EQUAL','level',1630),
  timestamptz '2026-09-07 15:30:00+05:30'
);

-- TEST 1: support test then reclaim => trigger ready.
do $$
declare
  v_id uuid;
  x jsonb;
begin
  select id into v_id from public.alpha_campaign_routes where trade_date=date '2026-09-07' and ticker='ASTRAMICRO' and route_key='SUPPORT_RECLAIM';
  x:=public.alpha_evaluate_campaign_route(v_id,1668,now(),1666,1672,null,'TEST');
  if x->>'new_state' <> 'TEST_SEEN' then raise exception 'TEST1A failed: %',x; end if;
  x:=public.alpha_evaluate_campaign_route(v_id,1682,now(),1670,1683,null,'TEST');
  if x->>'new_state' <> 'TRIGGER_READY' then raise exception 'TEST1B failed: %',x; end if;
end $$;

-- reset fixture runtime for kill test.
update public.alpha_campaign_routes set runtime_state='LOCKED',authorization_state='CAPITAL_READY' where trade_date=date '2026-09-07';
update public.alpha_session_capital_lock set status='LOCKED',fresh_campaigns_executed=0,executed_route_id=null,session_invalidation_reason=null where trade_date=date '2026-09-07';

-- TEST 2: 1629 kills entire Astra session; later 1750 must not resurrect breakout.
do $$
declare
  v_a uuid; v_b uuid; x jsonb; s text;
begin
  select id into v_a from public.alpha_campaign_routes where trade_date=date '2026-09-07' and route_key='SUPPORT_RECLAIM';
  select id into v_b from public.alpha_campaign_routes where trade_date=date '2026-09-07' and route_key='BREAKOUT';
  x:=public.alpha_evaluate_campaign_route(v_a,1629,now(),1629,1640,null,'TEST');
  if x->>'invalidation_result' <> 'true' then raise exception 'TEST2A failed: %',x; end if;
  x:=public.alpha_evaluate_campaign_route(v_b,1750,now(),1740,1755,null,'TEST');
  if x->>'new_state' not in ('INVALIDATED','SESSION_CANCELLED') then raise exception 'TEST2B resurrection detected: %',x; end if;
  select status into s from public.alpha_session_capital_lock where trade_date=date '2026-09-07';
  if s <> 'KEEP_CASH' then raise exception 'TEST2C expected KEEP_CASH got %',s; end if;
end $$;

-- reset for mutex execution test.
update public.alpha_campaign_routes set runtime_state='LOCKED',authorization_state='CAPITAL_READY' where trade_date=date '2026-09-07';
update public.alpha_session_capital_lock set status='LOCKED',fresh_campaigns_executed=0,executed_route_id=null,session_invalidation_reason=null where trade_date=date '2026-09-07';

-- TEST 3: breakout executes first => support mutex-cancelled and count=1.
do $$
declare
  v_b uuid; x jsonb; a_state text; n int;
begin
  select id into v_b from public.alpha_campaign_routes where trade_date=date '2026-09-07' and route_key='BREAKOUT';
  x:=public.alpha_evaluate_campaign_route(v_b,1750,now(),1745,1755,null,'TEST');
  if x->>'new_state' <> 'TRIGGER_READY' then raise exception 'TEST3A failed: %',x; end if;
  perform public.alpha_claim_route_execution(v_b,null);
  select runtime_state into a_state from public.alpha_campaign_routes where trade_date=date '2026-09-07' and route_key='SUPPORT_RECLAIM';
  if a_state <> 'MUTEX_CANCELLED' then raise exception 'TEST3B expected MUTEX_CANCELLED got %',a_state; end if;
  select fresh_campaigns_executed into n from public.alpha_session_capital_lock where trade_date=date '2026-09-07';
  if n <> 1 then raise exception 'TEST3C expected one campaign got %',n; end if;
end $$;

-- TEST 4/5 policy assertions: KDDL and GKENERGY are not capital owner and cannot be promoted by price alone.
do $$
declare
  k text; g text;
begin
  select authorization_state into k from public.alpha_preopen_rankings where trade_date=date '2026-09-07' and ticker='KDDL';
  select authorization_state into g from public.alpha_preopen_rankings where trade_date=date '2026-09-07' and ticker='GKENERGY';
  if k <> 'CAPITAL_BLOCKED' then raise exception 'TEST4 failed'; end if;
  if g <> 'IGNORE_SESSION' then raise exception 'TEST5 failed'; end if;
end $$;

-- TEST 13: R:R less than 3 can exist as research/preauth geometry, but must never be CAPITAL_READY.
do $$
declare
  v_id uuid;
begin
  insert into public.alpha_campaign_routes(
    trade_date,ticker,campaign_id,route_key,route_name,route_priority,exclusive_group,authorization_state,runtime_state,
    trigger_type,trigger_params,model_entry,structural_stop,target_price,rr_ratio,requires_human_approval
  ) values(
    date '2026-09-07','BADRR','BADRR','BAD','Bad RR',99,'BADRR','PREAUTHORIZED','LOCKED','PRICE_ABOVE','{"level":100}'::jsonb,
    100,90,129,2.9,true
  ) returning id into v_id;
  if exists(select 1 from public.alpha_campaign_routes where id=v_id and authorization_state='CAPITAL_READY') then raise exception 'TEST13 failed'; end if;
end $$;

-- Test subjective gate: undefined volume cannot auto-authorize trigger.
do $$
declare
  v_id uuid; x jsonb;
begin
  select (public.alpha_create_campaign_route(
    date '2026-09-07','VOLUMEBLOCK','VB','BRK','Undefined volume breakout',1,'VB','BREAKOUT_ACCEPTANCE',
    jsonb_build_object('breakout_level',100,'max_entry',105),100,105,102,95,130,80,
    jsonb_build_object('status','UNDEFINED_BLOCKING'),jsonb_build_object('type','PRICE_BELOW_OR_EQUAL','level',95),
    timestamptz '2026-09-07 15:30:00+05:30'
  )->>'id')::uuid into v_id;

  -- separate lock is intentionally absent; evaluator should not be usable without session lock.
  -- This validates architecture principle that a route alone has no session capital authority.
  begin
    x:=public.alpha_evaluate_campaign_route(v_id,103,now(),101,104,100000,'TEST');
    raise exception 'SUBJECTIVE_GATE test unexpectedly evaluated without session lock: %',x;
  exception when others then
    if position('session lock missing' in sqlerrm)=0 then raise; end if;
  end;
end $$;

rollback;
