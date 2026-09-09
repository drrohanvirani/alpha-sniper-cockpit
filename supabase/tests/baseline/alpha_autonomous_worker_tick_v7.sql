CREATE OR REPLACE FUNCTION public.alpha_autonomous_worker_tick_v7()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_base jsonb; v_phase text; v_agenda jsonb := '{}'::jsonb; v_compress jsonb := '{}'::jsonb;
  v_mission jsonb := '{}'::jsonb; v_win jsonb; v_evo jsonb; v_delivery jsonb; v_run_id bigint;
begin
  v_base := public.alpha_autonomous_worker_tick_v4();
  v_phase := coalesce(v_base->>'phase','UNKNOWN');
  if v_phase <> 'MARKET_HOURS' then
    v_agenda := public.alpha_seed_independent_opportunity_agenda(3);
    v_compress := public.alpha_queue_compress(15);
    v_mission := public.alpha_mission_control_tick();
  else
    v_agenda := jsonb_build_object('status','SUPPRESSED_MARKET_HOURS','reason','LOCKED_CAPITAL_PLAN_ONLY');
    v_mission := jsonb_build_object('status','SUPPRESSED_MARKET_HOURS','reason','NO_INTRADAY_CAPITAL_RERANKING');
  end if;
  v_win := public.alpha_winner_protection_tick();
  v_delivery := public.alpha_delivery_gate_tick();
  v_evo := public.alpha_evolution_governor_tick();
  v_run_id := nullif(v_base->>'run_id','')::bigint;
  if v_run_id is not null then
    update public.alpha_worker_runs set actions = actions
      || jsonb_build_array(jsonb_build_object('action','independent_opportunity_agenda','result',v_agenda))
      || jsonb_build_array(jsonb_build_object('action','mission_control','result',v_mission))
      || jsonb_build_array(jsonb_build_object('action','winner_protection','result',v_win))
      || jsonb_build_array(jsonb_build_object('action','delivery_gate','result',v_delivery))
      || jsonb_build_array(jsonb_build_object('action','evolution_governor','result',v_evo))
    where id=v_run_id;
  end if;
  return v_base || jsonb_build_object(
    'independent_opportunity_agenda',v_agenda,
    'mission_control',v_mission,
    'winner_protection',v_win,
    'delivery_gate',v_delivery,
    'evolution_governor',v_evo
  );
end
$function$

