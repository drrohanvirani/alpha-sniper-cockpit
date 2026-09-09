-- Read-only employee report input. No application RPCs are invoked.
BEGIN READ ONLY;
SELECT jsonb_build_object(
 'schema_version','ALPHA_EMPLOYEE_INPUT_V1',
 'captured_at',now(),
 'trade_date',(now() at time zone 'Asia/Kolkata')::date,
 'project_ref','rclbninptekxitkdtmrs',
 'broker_sync',(SELECT to_jsonb(x) FROM
   (SELECT id,sync_at,status,holdings_count,positions_count,cash_available
    FROM public.zerodha_sync_log_internal ORDER BY sync_at DESC,id DESC LIMIT 1)x),
 'holdings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticker',ticker,'quantity',quantity,'market_value',market_value,'snapshot_at',snapshot_at)
   ORDER BY ticker),'[]'::jsonb) FROM public.live_portfolio WHERE quantity>0),
 'census',(SELECT to_jsonb(x) FROM
   (SELECT id,trade_date,status,stored_rows,eligible_rows,completed_at
    FROM public.alpha_census_runs WHERE status='COMPLETED'
    AND trade_date <= (now() at time zone 'Asia/Kolkata')::date
    ORDER BY trade_date DESC,id DESC LIMIT 1)x),
 'features',(SELECT coalesce(jsonb_agg(jsonb_build_object(
   'symbol',symbol,'series',series,'trade_date',trade_date,'eligible',eligible,
   'census_rank',census_rank,'close',close,'return_5d_pct',return_5d_pct,
   'return_20d_pct',return_20d_pct,'calculated_at',calculated_at)
   ORDER BY census_rank NULLS LAST,symbol,series),'[]'::jsonb)
   FROM public.alpha_market_features WHERE trade_date=(
    SELECT trade_date FROM public.alpha_census_runs WHERE status='COMPLETED'
    AND trade_date <= (now() at time zone 'Asia/Kolkata')::date
    ORDER BY trade_date DESC,id DESC LIMIT 1)),
 'tournament',(SELECT to_jsonb(x) FROM
   (SELECT id,trade_date,source_trade_date,generated_at,run_status,decision_state,
     holding_count,qualified_challenger_count,failure_reasons
    FROM public.alpha_capital_tournament_runs ORDER BY generated_at DESC,id DESC LIMIT 1)x),
 'worker_attempt',(SELECT to_jsonb(x) FROM
   (SELECT runid,jobid,start_time,end_time,status
    FROM cron.job_run_details WHERE jobid=29 ORDER BY start_time DESC,runid DESC LIMIT 1)x),
 'learning_event',(SELECT to_jsonb(x) FROM
   (SELECT id,created_at FROM public.brain_events WHERE event_type='DAILY_LEARNING_SCORECARD'
    ORDER BY created_at DESC,id DESC LIMIT 1)x),
 'curiosity',(SELECT jsonb_build_object('total',count(*),
   'answered',count(*) FILTER(WHERE answered_at IS NOT NULL),
   'overdue_unanswered',count(*) FILTER(WHERE answered_at IS NULL AND deadline_at<=now()
     AND status IN ('OPEN','ACKNOWLEDGED')))
   FROM public.alpha_autonomy_queue WHERE contract_version='AWARENESS_CURIOSITY_V1'),
 'session_lock',(SELECT jsonb_build_object('trade_date',trade_date,'status',status,
   'lock_id',lock_id,'capital_owner_ticker',capital_owner_ticker,
   'executed_route_id',executed_route_id)
   FROM public.alpha_session_capital_lock
   WHERE trade_date=(now() at time zone 'Asia/Kolkata')::date)
) AS packet;
COMMIT;

