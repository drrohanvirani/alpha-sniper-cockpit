CREATE OR REPLACE FUNCTION public.alpha_liveness_guard_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_latest timestamptz;
  v_age integer;
  v_market_open boolean;
  v_india timestamp:=timezone('Asia/Kolkata',now());
  v_wp jsonb;
  v_dg jsonb;
  v_stale boolean:=false;
begin
  select max(captured_at) into v_latest from public.zerodha_raw_snapshot_internal;
  v_age:=case when v_latest is null then 999999 else greatest(0,extract(epoch from(now()-v_latest))::int) end;
  v_market_open:=extract(isodow from v_india) between 1 and 5 and v_india::time between time '09:15' and time '15:30';
  v_stale:=v_market_open and v_age>420;

  if v_stale then
    insert into public.alpha_autonomy_queue(queue_key,queue_type,priority,objective,recommended_next_step,evidence,status,origin,generated_by_agent,human_approval_required,user_prompted,delivery_required,delivery_status,delivery_sla_minutes,detected_at,updated_at)
    values('BROKER_LIVENESS:STALE','SYSTEM_DEFECT',100,'Keep broker truth fresh without user prompting','Repair broker sync immediately; block portfolio instructions until a fresh snapshot exists.',jsonb_build_object('last_snapshot_at',v_latest,'age_seconds',v_age,'checked_at',now()),'OPEN','SYSTEM','LIVENESS_GUARD',false,false,true,'PENDING_DELIVERY',15,now(),now())
    on conflict(queue_key) do update set priority=100,status='OPEN',resolved_at=null,evidence=excluded.evidence,updated_at=now(),delivery_required=true,delivery_status='PENDING_DELIVERY',detected_at=coalesce(public.alpha_autonomy_queue.detected_at,now());
  else
    update public.alpha_autonomy_queue set status='RESOLVED',resolved_at=now(),updated_at=now(),answer_conclusion='BROKER_LIVENESS_RESTORED',answered_at=now(),decision_impact='Portfolio instructions may use current broker state.'
    where queue_key='BROKER_LIVENESS:STALE' and status='OPEN';
  end if;

  v_wp:=public.alpha_winner_protection_tick();
  v_dg:=public.alpha_delivery_gate_tick();

  insert into public.brain_events(event_type,entity_type,entity_key,payload)
  values('GROUND_TRUTH_LIVENESS_TICK','SYSTEM','ALPHA-OS-CANONICAL',jsonb_build_object('checked_at',now(),'broker_snapshot_at',v_latest,'broker_age_seconds',v_age,'broker_stale',v_stale,'winner_protection',v_wp,'delivery_gate',v_dg));

  return jsonb_build_object('ok',not v_stale,'broker_snapshot_at',v_latest,'broker_age_seconds',v_age,'broker_stale',v_stale,'winner_protection',v_wp,'delivery_gate',v_dg);
end;
$function$

