CREATE OR REPLACE FUNCTION public.alpha_master_daily_sop_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now timestamptz:=now();
  v_ist timestamp:=now() at time zone 'Asia/Kolkata';
  v_day date:=(now() at time zone 'Asia/Kolkata')::date;
  v_t time:=(now() at time zone 'Asia/Kolkata')::time;
  v_dow int:=extract(isodow from (now() at time zone 'Asia/Kolkata'));
  v_branch text:='IDLE';
  v_r1 jsonb:='{}'::jsonb; v_r2 jsonb:='{}'::jsonb; v_r3 jsonb:='{}'::jsonb; v_r4 jsonb:='{}'::jsonb; v_r5 jsonb:='{}'::jsonb;
  v_result jsonb:='{}'::jsonb;
  v_plan jsonb;
  v_active int:=0; v_challengers int:=0;
begin
  -- One canonical SOP; infrastructure sensors remain plumbing, not separate decision processes.
  if v_dow between 1 and 5 then
    if v_t >= time '07:30' and v_t < time '08:45' then
      v_branch:='PREOPEN_RESEARCH';
      if not public.alpha_master_sop_phase_done(v_day,'PREOPEN_RESEARCH') then
        begin v_r1:=public.alpha_conviction_board_sync(); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r2:=public.alpha_conviction_event_review_tick(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r3:=public.alpha_generate_research_frontiers(); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r5:=public.alpha_run_challenger_underwriting_v1(); exception when others then v_r5:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r4:=public.alpha_preopen_add_readiness_tick(); exception when others then v_r4:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        v_result:=jsonb_build_object('conviction_board',v_r1,'verified_event_reviews',v_r2,'research_frontiers',v_r3,'challenger_underwriting',v_r5,'holding_readiness',v_r4);
        perform public.alpha_master_sop_record_phase(v_day,'PREOPEN_RESEARCH',case when coalesce((v_r4->>'ok')::boolean,false) then 'PASS' else 'WARN' end,v_result);
      end if;

    elsif v_t >= time '08:45' and v_t < time '09:15' then
      v_branch:='CAPITAL_LOCK';
      if not public.alpha_master_sop_phase_done(v_day,'CAPITAL_LOCK') then
        begin v_r1:=public.alpha_lock_capital_owner_preopen(); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r2:=public.alpha_conviction_capital_guard_tick(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r3:=public.alpha_sync_session_lock_from_brain(); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        v_result:=jsonb_build_object('capital_owner_lock',v_r1,'conviction_guard',v_r2,'session_lock',v_r3,'rule','ONLY_ACTIVE_CONVICTION_NAMES_MAY_RECEIVE_FRESH_CAPITAL; OTHERWISE CASH');
        perform public.alpha_master_sop_record_phase(v_day,'CAPITAL_LOCK',case when coalesce((v_r3->>'ok')::boolean,false) then 'PASS' else 'WARN' end,v_result);
      end if;

    elsif v_t >= time '09:15' and v_t <= time '15:30' then
      v_branch:='MARKET_EXECUTION';
      begin v_r1:=public.alpha_liveness_guard_tick(); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r2:=public.alpha_winner_protection_tick(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r3:=public.alpha_route_monitor_tick(); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r4:=public.alpha_reconcile_route_execution_from_broker(); exception when others then v_r4:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      v_result:=jsonb_build_object('ground_truth_liveness',v_r1,'winner_protection',v_r2,'locked_route_monitor',v_r3,'broker_reconciliation',v_r4,'intraday_rule','EXECUTE_FROZEN_PLAN_OR_WAIT; NO_RERANK_NO_SUBSTITUTE');

    elsif v_t > time '15:30' and v_t < time '19:50' then
      v_branch:='EOD_RECONCILE';
      if not public.alpha_master_sop_phase_done(v_day,'EOD_RECONCILE') then
        begin v_r1:=public.alpha_expire_session_routes(v_day); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r2:=public.alpha_reconcile_route_execution_from_broker(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r3:=public.alpha_conviction_board_sync(); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r4:=public.alpha_conviction_event_review_tick(); exception when others then v_r4:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r5:=public.alpha_generate_research_frontiers(); exception when others then v_r5:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        v_result:=jsonb_build_object('route_expiry',v_r1,'broker_reconcile',v_r2,'conviction_board',v_r3,'verified_event_reviews',v_r4,'tomorrow_research_frontier',v_r5);
        perform public.alpha_master_sop_record_phase(v_day,'EOD_RECONCILE','PASS',v_result);
      end if;

    else
      v_branch:='DEEP_CLOSURE';
      if v_t >= time '19:50' and not public.alpha_master_sop_phase_done(v_day,'DEEP_CLOSURE') then
        begin v_r1:=public.alpha_run_conviction_audit(20); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r2:=public.alpha_score_shadow_trades(v_day); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        begin v_r3:=public.alpha_run_system_audit('DAILY'); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
        v_result:=jsonb_build_object('conviction_audit',v_r1,'shadow_outcomes',v_r2,'system_audit',v_r3,'closure_rule','LEARN_FROM_OUTCOMES; DO_NOT_CHANGE_CONVICTION_FROM_SCAN_EXCITEMENT');
        perform public.alpha_master_sop_record_phase(v_day,'DEEP_CLOSURE',case when upper(coalesce(v_r3->>'status',''))='PASS' then 'PASS' else 'WARN' end,v_result);
      end if;
    end if;
  elsif v_dow=6 then
    v_branch:='WEEKLY_REVIEW';
    if v_t >= time '08:50' and not public.alpha_master_sop_phase_done(v_day,'WEEKLY_REVIEW') then
      begin v_r1:=public.alpha_conviction_board_sync(); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r2:=public.alpha_generate_research_frontiers(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r3:=public.alpha_run_system_audit('WEEKLY'); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      v_result:=jsonb_build_object('conviction_board',v_r1,'research_frontier',v_r2,'weekly_audit',v_r3,'rule','ZERO_BASE_HOLDINGS_CASH_AND_CHALLENGERS; ACTIVE_CONVICTION_CHANGES_ONLY_ON_VERIFIED_EVIDENCE');
      perform public.alpha_master_sop_record_phase(v_day,'WEEKLY_REVIEW','PASS',v_result);
    end if;
  else
    v_branch:='SUNDAY_PREP';
    if v_t >= time '19:50' and not public.alpha_master_sop_phase_done(v_day,'SUNDAY_PREP') then
      begin v_r1:=public.alpha_conviction_board_sync(); exception when others then v_r1:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r2:=public.alpha_conviction_event_review_tick(); exception when others then v_r2:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      begin v_r3:=public.alpha_generate_research_frontiers(); exception when others then v_r3:=jsonb_build_object('ok',false,'error',sqlerrm); end;
      v_result:=jsonb_build_object('conviction_board',v_r1,'verified_event_reviews',v_r2,'next_week_research',v_r3,'rule','PREPARE_EVIDENCE; DO_NOT_FORCE_TRADE_WITHOUT_FRESH_MARKET_CONTEXT');
      perform public.alpha_master_sop_record_phase(v_day,'SUNDAY_PREP','PASS',v_result);
    end if;
  end if;

  select count(*) filter(where board_role='ACTIVE'),count(*) filter(where board_role='CHALLENGER') into v_active,v_challengers from public.alpha_conviction_board;
  select current_truth->'capital_plan' into v_plan from public.brain_state where state_key='ALPHA-OS-CANONICAL';

  update public.brain_state
  set current_truth=jsonb_set(coalesce(current_truth,'{}'::jsonb),'{master_daily_sop}',jsonb_build_object(
    'sop_key','ALPHA_SINGLE_OPERATING_LOOP_V1',
    'version','MASTER_DAILY_SOP_V1',
    'last_tick',v_now,
    'ist_time',v_ist,
    'branch',v_branch,
    'active_conviction_slots',v_active,
    'challengers',v_challengers,
    'capital_owner',coalesce(v_plan->>'capital_owner','CASH'),
    'capital_decision',coalesce(v_plan->>'decision','KEEP_CASH'),
    'one_line','SCAN BROADLY -> BUILD CONVICTION SLOWLY -> LOCK ONE CAPITAL OWNER -> EXECUTE FROZEN PLAN OR KEEP CASH -> LEARN AFTER CLOSE',
    'user_visible_task','ALPHA MASTER DAILY SOP'
  ),true),updated_at=v_now
  where state_key='ALPHA-OS-CANONICAL';

  insert into public.brain_events(event_type,entity_type,entity_key,payload)
  values('ALPHA_MASTER_DAILY_SOP_TICK','SYSTEM',v_day::text,jsonb_build_object('branch',v_branch,'at',v_now,'active_conviction_slots',v_active,'challengers',v_challengers,'capital_owner',coalesce(v_plan->>'capital_owner','CASH'),'capital_authority',false));

  return jsonb_build_object('ok',true,'trade_date',v_day,'branch',v_branch,'active_conviction_slots',v_active,'challengers',v_challengers,'capital_owner',coalesce(v_plan->>'capital_owner','CASH'),'detail',v_result);
end;
$function$

