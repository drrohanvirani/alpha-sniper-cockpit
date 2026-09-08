-- TEST INPUT ONLY. Owner-supplied live definitions, 2026-09-07/08.
-- Formatting condensed; no production query performed by this test.
-- NEVER replay this baseline: it deliberately contains the original reset bug.
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

CREATE OR REPLACE FUNCTION public.alpha_sync_session_lock_from_brain()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
declare
  v_now timestamptz:=now();
  v_ist timestamp:=now() at time zone 'Asia/Kolkata';
  v_day date:=(now() at time zone 'Asia/Kolkata')::date;
  v_plan jsonb;
  v_owner text;
  v_item jsonb;
  v_routes jsonb;
  v_route jsonb;
  v_cash numeric:=0;
  v_nav numeric:=0;
  v_reserved numeric:=0;
  v_campaign_id text;
  v_expires timestamptz;
  v_locked_at timestamptz;
  v_route_count integer:=0;
  v_result jsonb;
  v_trigger jsonb;
  v_target numeric;
  v_stop numeric;
  v_entry_low numeric;
  v_entry_high numeric;
  v_model_entry numeric;
  v_trigger_type text;
  v_trigger_params jsonb;
  v_volume_rule jsonb;
  v_kill_rule jsonb;
begin
  if extract(isodow from v_ist) not between 1 and 5 then
    return jsonb_build_object('ok',false,'status','WEEKEND','for_date',v_day);
  end if;
  if v_ist::time >= time '09:15' then
    return jsonb_build_object('ok',false,'status','TOO_LATE_FOR_PREOPEN_SESSION_SYNC','for_date',v_day);
  end if;
  select current_truth->'capital_plan' into v_plan
  from public.brain_state where state_key='ALPHA-OS-CANONICAL';
  if v_plan is null or upper(coalesce(v_plan->>'status',''))<>'LOCKED' then
    return jsonb_build_object('ok',false,'status','NO_LOCKED_CAPITAL_PLAN','for_date',v_day);
  end if;
  begin
    v_locked_at:=nullif(v_plan->>'locked_at','')::timestamptz;
  exception when others then v_locked_at:=null;
  end;
  begin
    v_expires:=nullif(v_plan->>'expires_at','')::timestamptz;
  exception when others then v_expires:=null;
  end;
  if v_locked_at is null
     or (v_locked_at at time zone 'Asia/Kolkata')::date<>v_day
     or v_expires is null or v_expires<=v_now then
    insert into public.alpha_session_capital_lock(
      trade_date,status,capital_owner_ticker,max_fresh_campaigns,
      fresh_campaigns_executed,reroute_allowed,intraday_new_destination_allowed,
      session_invalidation_reason,created_by,updated_at
    ) values(v_day,'DATA_BLOCKED',null,1,0,false,false,
      'LOCKED_PLAN_NOT_CURRENT_SESSION','PREOPEN_BRIDGE',now())
    on conflict(trade_date) do update set
      status='DATA_BLOCKED',capital_owner_ticker=null,
      session_invalidation_reason='LOCKED_PLAN_NOT_CURRENT_SESSION',updated_at=now();
    return jsonb_build_object('ok',false,'status','LOCKED_PLAN_NOT_CURRENT_SESSION',
      'for_date',v_day,'locked_at',v_locked_at,'expires_at',v_expires);
  end if;
  select coalesce(cash_available,0) into v_cash
  from public.zerodha_sync_log_internal where status='SUCCESS'
  order by sync_at desc limit 1;
  v_nav:=coalesce(nullif(v_plan->>'total_nav','')::numeric,0);
  if v_nav<=0 then
    select coalesce(sum(case when quantity>0 then market_value else 0 end),0)+v_cash
    into v_nav from public.live_portfolio;
  end if;
  v_owner:=upper(coalesce(v_plan->>'capital_owner','CASH'));
  if v_owner='CASH'
     or jsonb_array_length(coalesce(v_plan->'items','[]'::jsonb))=0 then
    insert into public.alpha_session_capital_lock(
      trade_date,status,capital_owner_ticker,capital_owner_campaign_id,
      max_fresh_campaigns,fresh_campaigns_executed,total_cash_available,
      cash_reserved,cash_remaining,total_nav,reroute_allowed,
      intraday_new_destination_allowed,locked_at,expires_at,created_by,updated_at
    ) values(v_day,'KEEP_CASH','CASH',
      coalesce(v_plan->>'lock_id','CAPITAL-OWNER-'||to_char(v_day,'YYYYMMDD')),
      1,0,v_cash,0,v_cash,v_nav,false,false,v_locked_at,v_expires,'PREOPEN_BRIDGE',now())
    on conflict(trade_date) do update set
      status='KEEP_CASH',capital_owner_ticker='CASH',
      capital_owner_campaign_id=excluded.capital_owner_campaign_id,
      max_fresh_campaigns=1,fresh_campaigns_executed=0,
      total_cash_available=excluded.total_cash_available,cash_reserved=0,
      cash_remaining=excluded.total_cash_available,total_nav=excluded.total_nav,
      reroute_allowed=false,intraday_new_destination_allowed=false,
      executed_route_id=null,executed_decision_id=null,session_invalidation_reason=null,
      locked_at=excluded.locked_at,expires_at=excluded.expires_at,
      created_by='PREOPEN_BRIDGE',updated_at=now();
    perform public.alpha_emit_brain_event('SESSION_CAPITAL_KEEP_CASH','SYSTEM',v_day::text,
      jsonb_build_object('trade_date',v_day,'source_lock_id',v_plan->>'lock_id',
        'cash',v_cash,'total_nav',v_nav,'capital_authority',false));
    return jsonb_build_object('ok',true,'status','KEEP_CASH',
      'for_date',v_day,'cash',v_cash,'total_nav',v_nav);
  end if;
  select value into v_item
  from jsonb_array_elements(coalesce(v_plan->'items','[]'::jsonb)) value
  where upper(coalesce(value->>'ticker',''))=v_owner limit 1;
  if v_item is null then
    return jsonb_build_object('ok',false,'status','OWNER_ITEM_MISSING',
      'for_date',v_day,'owner',v_owner);
  end if;
  v_reserved:=least(v_cash,coalesce(nullif(v_item->>'rupee_amount','')::numeric,
    nullif(v_plan->>'cash_reserved','')::numeric,0));
  if v_reserved<=0 or v_nav<=0 then
    insert into public.alpha_session_capital_lock(
      trade_date,status,capital_owner_ticker,max_fresh_campaigns,
      fresh_campaigns_executed,total_cash_available,cash_reserved,cash_remaining,
      total_nav,reroute_allowed,intraday_new_destination_allowed,
      session_invalidation_reason,created_by,updated_at
    ) values(v_day,'DATA_BLOCKED',v_owner,1,0,v_cash,0,v_cash,v_nav,
      false,false,'INVALID_CASH_OR_NAV','PREOPEN_BRIDGE',now())
    on conflict(trade_date) do update set
      status='DATA_BLOCKED',capital_owner_ticker=excluded.capital_owner_ticker,
      total_cash_available=excluded.total_cash_available,total_nav=excluded.total_nav,
      session_invalidation_reason='INVALID_CASH_OR_NAV',updated_at=now();
    return jsonb_build_object('ok',false,'status','DATA_BLOCKED','reason','INVALID_CASH_OR_NAV',
      'owner',v_owner,'cash',v_cash,'nav',v_nav);
  end if;
  v_campaign_id:=coalesce(v_plan->>'lock_id','CAPITAL-OWNER-'||to_char(v_day,'YYYYMMDD'))||':'||v_owner;
  perform public.alpha_lock_session_capital(
    v_day,v_owner,v_campaign_id,v_cash,v_reserved,v_nav,v_expires,'PREOPEN_BRIDGE');
  v_routes:=v_item->'routes';
  if jsonb_typeof(v_routes)<>'array' then
    select execution_plan->'routes' into v_routes
    from public.portfolio_campaign_targets where upper(ticker)=v_owner limit 1;
  end if;
  if jsonb_typeof(v_routes)='array' and jsonb_array_length(v_routes)>0 then
    for v_route in select value from jsonb_array_elements(v_routes) loop
      perform public.alpha_create_campaign_route(
        v_day,v_owner,v_campaign_id,
        coalesce(v_route->>'route_key','ROUTE_'||v_route_count::text),
        coalesce(v_route->>'route_name',v_route->>'route_key','Route'),
        coalesce(nullif(v_route->>'route_priority','')::int,v_route_count+1),
        coalesce(v_route->>'exclusive_group',v_campaign_id),
        coalesce(v_route->>'trigger_type','CUSTOM_STATE_MACHINE'),
        coalesce(v_route->'trigger_params','{}'::jsonb),
        nullif(v_route->>'entry_low','')::numeric,nullif(v_route->>'entry_high','')::numeric,
        nullif(v_route->>'model_entry','')::numeric,nullif(v_route->>'structural_stop','')::numeric,
        nullif(v_route->>'target_price','')::numeric,nullif(v_route->>'setup_conviction','')::numeric,
        coalesce(v_route->'volume_rule',jsonb_build_object('status','UNDEFINED_BLOCKING')),
        coalesce(v_route->'session_kill_rule','{}'::jsonb),
        coalesce(nullif(v_route->>'expires_at','')::timestamptz,v_expires));
      v_route_count:=v_route_count+1;
    end loop;
  else
    select execution_plan into v_route
    from public.portfolio_campaign_targets where upper(ticker)=v_owner limit 1;
    v_trigger:=coalesce(v_item->'trigger',v_route->'trigger');
    v_target:=coalesce(nullif(v_route->>'target_price','')::numeric,nullif(v_item->>'target_price','')::numeric);
    v_stop:=coalesce(nullif(v_route->>'structural_invalidation','')::numeric,
      nullif(v_route->>'stop','')::numeric,nullif(v_item->>'structural_stop','')::numeric);
    v_entry_low:=coalesce(nullif(v_route#>>'{entry_range,low}','')::numeric,
      nullif(v_item#>>'{entry_range,low}','')::numeric);
    v_entry_high:=coalesce(nullif(v_route#>>'{entry_range,high}','')::numeric,
      nullif(v_item#>>'{entry_range,high}','')::numeric);
    v_model_entry:=coalesce(nullif(v_route->>'model_entry','')::numeric,v_entry_low,v_entry_high);
    v_trigger_type:=upper(coalesce(v_trigger->>'type',''));
    v_trigger_params:=coalesce(v_trigger,'{}'::jsonb);
    v_volume_rule:=coalesce(v_route->'volume_rule',jsonb_build_object('status','UNDEFINED_BLOCKING'));
    v_kill_rule:=coalesce(v_route->'session_kill_rule','{}'::jsonb);
    if v_target is not null and v_stop is not null and v_model_entry is not null
       and v_trigger_type in ('PRICE_ABOVE','PRICE_BELOW','PRICE_RANGE') then
      perform public.alpha_create_campaign_route(v_day,v_owner,v_campaign_id,'PRIMARY',
        'Primary locked route',1,v_campaign_id,v_trigger_type,v_trigger_params,
        v_entry_low,v_entry_high,v_model_entry,v_stop,v_target,
        nullif(v_route->>'setup_conviction','')::numeric,v_volume_rule,v_kill_rule,v_expires);
      v_route_count:=1;
    end if;
  end if;
  if v_route_count=0 then
    insert into public.alpha_autonomy_queue(
      queue_key,queue_type,ticker,priority,objective,recommended_next_step,evidence,status,origin,
      generated_by_agent,human_approval_required,user_prompted,delivery_required,delivery_status,
      delivery_sla_minutes,detected_at,created_at,updated_at
    ) values('SESSION_ROUTE_GEOMETRY_MISSING:'||v_day::text||':'||v_owner,'SYSTEM_DEFECT',v_owner,100,
      'Freeze executable route geometry before market open',
      'Capital owner is locked but no complete route geometry could be created. Keep cash. Populate exact entry, stop, target, trigger and invalidation before the next session.',
      jsonb_build_object('trade_date',v_day,'owner',v_owner,'capital_plan',v_plan,'capital_authority',false),
      'OPEN','SYSTEM','PREOPEN_BRIDGE',false,false,true,'PENDING',15,now(),now(),now())
    on conflict(queue_key) do update set status='OPEN',resolved_at=null,priority=100,
      evidence=excluded.evidence,updated_at=now(),delivery_status='PENDING',detected_at=now();
  end if;
  return jsonb_build_object('ok',true,'status','LOCKED','for_date',v_day,'owner',v_owner,
    'campaign_id',v_campaign_id,'route_count',v_route_count,'cash_reserved',v_reserved,'cash',v_cash,'nav',v_nav);
end;
$function$;
