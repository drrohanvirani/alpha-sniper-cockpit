CREATE OR REPLACE FUNCTION public.alpha_autonomy_heartbeat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now(); v_ist time := (v_now at time zone 'Asia/Kolkata')::time; v_phase text;
  v_snapshot timestamptz; v_positions integer; v_top_ticker text; v_top_weight numeric;
  v_top_theme text; v_top_theme_weight numeric; v_integrity boolean; v_open integer;
  v_plan_result jsonb := '{}'::jsonb;
begin
  v_phase := case when v_ist < time '09:15' then 'PREOPEN' when v_ist < time '10:15' then 'OPENING_EVIDENCE' when v_ist < time '14:45' then 'INTRADAY_SURVEILLANCE' when v_ist <= time '15:40' then 'PRECLOSE_RISK' else 'POSTCLOSE_REVIEW' end;
  select max(snapshot_at),count(*) into v_snapshot,v_positions from public.live_portfolio;
  select ticker,portfolio_weight into v_top_ticker,v_top_weight from public.live_portfolio order by portfolio_weight desc nulls last limit 1;
  with themes as (
    select tag theme,sum(coalesce(lp.portfolio_weight,0)) weight
    from public.live_portfolio lp cross join lateral unnest(coalesce(lp.theme_tags,array[]::text[])) tag
    where tag like 'THEME_%' group by tag
  ) select theme,weight into v_top_theme,v_top_theme_weight from themes order by weight desc limit 1;
  v_integrity := v_snapshot is not null and (v_now-v_snapshot)<=interval '20 minutes';
  if v_positions>0 then
    insert into public.alpha_market_observations(observed_at,ticker,current_price,avg_price,portfolio_weight,return_vs_cost_pct)
    select date_trunc('minute',v_now),ticker,current_price,avg_price,portfolio_weight,case when avg_price>0 then 100*(current_price/avg_price-1) end from public.live_portfolio
    on conflict(ticker,observed_at) do nothing;
  end if;
  if not v_integrity and v_ist between time '08:55' and time '15:40' then
    insert into public.alpha_autonomy_queue(queue_key,queue_type,priority,objective,recommended_next_step,evidence,status,updated_at)
    values('DATA_FRESHNESS','DATA_INTEGRITY',100,'Protect capital from stale portfolio truth','Refresh Zerodha portfolio truth before any fresh BUY/ADD/ROTATE.',jsonb_build_object('snapshot_at',v_snapshot,'heartbeat_at',v_now),'OPEN',v_now)
    on conflict(queue_key) do update set priority=excluded.priority,objective=excluded.objective,recommended_next_step=excluded.recommended_next_step,evidence=excluded.evidence,status='OPEN',updated_at=v_now,resolved_at=null;
  else update public.alpha_autonomy_queue set status='RESOLVED',resolved_at=v_now,updated_at=v_now where queue_key='DATA_FRESHNESS' and status='OPEN'; end if;
  if coalesce(v_top_weight,0)>=0.14 then
    insert into public.alpha_autonomy_queue(queue_key,queue_type,ticker,priority,objective,recommended_next_step,evidence,status,updated_at)
    values('SINGLE_STOCK_CONCENTRATION:'||v_top_ticker,'PORTFOLIO_HEAT',v_top_ticker,85,'Control single-stock concentration without mechanically cutting a winner','Risk review only. Do not create or substitute a capital destination during market hours.',jsonb_build_object('weight',v_top_weight,'phase',v_phase),'OPEN',v_now)
    on conflict(queue_key) do update set ticker=excluded.ticker,priority=excluded.priority,objective=excluded.objective,recommended_next_step=excluded.recommended_next_step,evidence=excluded.evidence,status='OPEN',updated_at=v_now,resolved_at=null;
  end if;
  if coalesce(v_top_theme_weight,0)>=0.35 then
    insert into public.alpha_autonomy_queue(queue_key,queue_type,priority,objective,recommended_next_step,evidence,status,updated_at)
    values('THEME_HEAT:'||v_top_theme,'THEME_CORRELATION',80,'Prevent hidden correlated concentration','Risk review only. Apply the next off-hours allocator hurdle; do not re-rank destinations intraday.',jsonb_build_object('theme',v_top_theme,'weight',v_top_theme_weight),'OPEN',v_now)
    on conflict(queue_key) do update set priority=excluded.priority,objective=excluded.objective,recommended_next_step=excluded.recommended_next_step,evidence=excluded.evidence,status='OPEN',updated_at=v_now,resolved_at=null;
  end if;
  if v_phase in ('OPENING_EVIDENCE','INTRADAY_SURVEILLANCE','PRECLOSE_RISK') then v_plan_result := public.alpha_locked_capital_plan_tick(); end if;
  select count(*) into v_open from public.alpha_autonomy_queue where status='OPEN';
  insert into public.alpha_heartbeat_runs(phase,portfolio_snapshot_at,portfolio_positions,open_queue_items,top_position_ticker,top_position_weight,top_theme,top_theme_weight,integrity_ok,notes)
  values(v_phase,v_snapshot,v_positions,v_open,v_top_ticker,v_top_weight,v_top_theme,v_top_theme_weight,v_integrity,
    jsonb_build_object('objective','Execute the pre-committed capital plan; do not re-rank capital intraday','allowed_allocation_questions',jsonb_build_array('HAS_LOCKED_TRIGGER_FIRED','HAS_PREDEFINED_INVALIDATION_FIRED'),'capital_plan_result',v_plan_result,'execution_boundary','PROPOSALS_ONLY_NO_AUTONOMOUS_TRADING'));
  insert into public.brain_events(event_type,entity_type,entity_key,payload)
  values('AUTONOMY_HEARTBEAT','SYSTEM','ALPHA-OS-CANONICAL',jsonb_build_object('phase',v_phase,'integrity_ok',v_integrity,'positions',v_positions,'open_queue',v_open,'top_position',v_top_ticker,'top_weight',v_top_weight,'top_theme',v_top_theme,'top_theme_weight',v_top_theme_weight,'allocation_mode','LOCKED_PLAN_ONLY','capital_plan_result',v_plan_result));
  return jsonb_build_object('ok',true,'phase',v_phase,'integrity_ok',v_integrity,'positions',v_positions,'open_queue',v_open,'top_position',v_top_ticker,'top_weight',v_top_weight,'top_theme',v_top_theme,'top_theme_weight',v_top_theme_weight,'allocation_mode','LOCKED_PLAN_ONLY','capital_plan',v_plan_result);
end;
$function$

