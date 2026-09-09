-- Prepare only. Captured production baseline: 2026-09-09.
-- No existing function body, cron schedule, or active flag changes.
DO $preflight$
DECLARE r record; v_job record;
BEGIN
  IF to_regprocedure('public.alpha_run_portfolio_maintenance_serialized(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'SERIALIZED_WRAPPER_ALREADY_EXISTS_RECONCILE_FIRST';
  END IF;
  FOR r IN SELECT * FROM (VALUES
('alpha-autonomy-heartbeat-30m','alpha_autonomy_heartbeat','10,40 3-11 * * 1-5','c0ab550b00425842f7cb4eb855d34fbb'),
('alpha-autonomous-worker-15m','alpha_autonomous_worker_tick_v7','*/15 * * * *','20a413a75ee5e66933e7f90acebb1368'),
('alpha-ground-truth-liveness-5m','alpha_liveness_guard_tick','*/5 3-10 * * 1-5','2f7890e7d7c36352492ad2612a43d803'),
('alpha-master-daily-sop','alpha_master_daily_sop_tick','*/5 * * * *','0e3baf7a6896255e2d98c38efcc79e81')
  ) AS expected(job_name,function_name,schedule,body_hash)
  LOOP
    IF md5(pg_get_functiondef(to_regprocedure('public.'||r.function_name||'()'))) IS DISTINCT FROM r.body_hash THEN
      RAISE EXCEPTION 'PRODUCTION_FUNCTION_DRIFT: %',r.function_name;
    END IF;
    SELECT * INTO STRICT v_job FROM cron.job WHERE jobname=r.job_name;
    IF v_job.command IS DISTINCT FROM 'select public.'||r.function_name||'();'
       OR v_job.schedule IS DISTINCT FROM r.schedule
       OR v_job.username IS DISTINCT FROM 'postgres'
       OR v_job.database IS DISTINCT FROM 'postgres'
       OR NOT v_job.active THEN
      RAISE EXCEPTION 'CRON_BASELINE_DRIFT: %',r.job_name;
    END IF;
  END LOOP;
END
$preflight$;

-- WRAPPER_BEGIN
CREATE FUNCTION public.alpha_run_portfolio_maintenance_serialized(p_job text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF p_job IS NULL OR p_job NOT IN ('heartbeat','worker','liveness','daily_sop') THEN
    RAISE EXCEPTION 'UNKNOWN_PORTFOLIO_MAINTENANCE_JOB' USING ERRCODE='22023';
  END IF;

  -- Acquire BEFORE entering any existing maintenance function / taking row locks.
  -- Transaction-scoped: released on both commit and rollback.
  PERFORM pg_advisory_xact_lock(1095520328,1);
  CASE p_job
    WHEN 'heartbeat' THEN RETURN public.alpha_autonomy_heartbeat();
    WHEN 'worker' THEN RETURN public.alpha_autonomous_worker_tick_v7();
    WHEN 'liveness' THEN RETURN public.alpha_liveness_guard_tick();
    WHEN 'daily_sop' THEN RETURN public.alpha_master_daily_sop_tick();
  END CASE;
END
$function$;
REVOKE ALL ON FUNCTION public.alpha_run_portfolio_maintenance_serialized(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alpha_run_portfolio_maintenance_serialized(text) TO postgres,service_role;
-- WRAPPER_END

DO $schedule$
DECLARE r record; v_id bigint;
BEGIN
  FOR r IN SELECT * FROM (VALUES
('alpha-autonomy-heartbeat-30m','heartbeat'),
('alpha-autonomous-worker-15m','worker'),
('alpha-ground-truth-liveness-5m','liveness'),
('alpha-master-daily-sop','daily_sop')
  ) AS jobs(job_name,entry_key)
  LOOP
    SELECT jobid INTO STRICT v_id FROM cron.job WHERE jobname=r.job_name;
    PERFORM cron.alter_job(v_id,command:=format(
      'select public.alpha_run_portfolio_maintenance_serialized(%L);',r.entry_key));
  END LOOP;
END
$schedule$;

