-- ISOLATED TEST FIXTURE ONLY. The runner creates a new in-memory PGlite database.
-- Not a production recovery schema; NEVER run this file against Supabase.
-- Session-table shape comes from the owner-supplied live definition.
-- Other tables/functions are explicit test doubles that record side effects.
CREATE ROLE service_role NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE TABLE public.alpha_campaign_routes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), args jsonb);
CREATE TABLE public.alpha_session_capital_lock (
  trade_date date NOT NULL PRIMARY KEY,
  lock_id uuid NOT NULL DEFAULT gen_random_uuid(),
  status text NOT NULL,
  capital_owner_ticker text,
  capital_owner_campaign_id text,
  max_fresh_campaigns integer NOT NULL DEFAULT 1,
  fresh_campaigns_executed integer NOT NULL DEFAULT 0,
  total_cash_available numeric,
  cash_reserved numeric,
  cash_remaining numeric,
  total_nav numeric,
  reroute_allowed boolean NOT NULL DEFAULT false,
  intraday_new_destination_allowed boolean NOT NULL DEFAULT false,
  executed_route_id uuid REFERENCES public.alpha_campaign_routes(id),
  executed_decision_id uuid,
  session_invalidation_reason text,
  locked_at timestamptz,
  expires_at timestamptz,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(fresh_campaigns_executed<=max_fresh_campaigns),
  CHECK(fresh_campaigns_executed>=0), CHECK(max_fresh_campaigns>=0),
  CHECK(status=ANY(ARRAY['DRAFT','LOCKED','TRIGGERED','EXECUTED','CANCELLED','EXPIRED','KEEP_CASH','DATA_BLOCKED']))
);
ALTER TABLE public.alpha_session_capital_lock ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.alpha_session_capital_lock TO service_role;
CREATE TABLE public.brain_state(state_key text PRIMARY KEY,current_truth jsonb);
CREATE TABLE public.zerodha_sync_log_internal(status text,cash_available numeric,sync_at timestamptz);
CREATE TABLE public.live_portfolio(quantity numeric,market_value numeric);
CREATE TABLE public.portfolio_campaign_targets(ticker text,execution_plan jsonb);
CREATE TABLE public.alpha_autonomy_queue(
  queue_key text PRIMARY KEY,queue_type text,ticker text,priority integer,objective text,
  recommended_next_step text,evidence jsonb,status text,origin text,generated_by_agent text,
  human_approval_required boolean,user_prompted boolean,delivery_required boolean,
  delivery_status text,delivery_sla_minutes integer,detected_at timestamptz,created_at timestamptz,
  updated_at timestamptz,resolved_at timestamptz
);
CREATE TABLE public.test_events(event_type text,entity_type text,entity_key text,payload jsonb);
CREATE FUNCTION public.alpha_emit_brain_event(text,text,text,jsonb) RETURNS void
LANGUAGE sql AS $$ INSERT INTO public.test_events VALUES($1,$2,$3,$4) $$;
CREATE FUNCTION public.alpha_create_campaign_route(
  date,text,text,text,text,integer,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,numeric,jsonb,jsonb,timestamptz
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r public.alpha_campaign_routes%rowtype;
BEGIN
  INSERT INTO public.alpha_campaign_routes(args)
  VALUES(jsonb_build_array($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18))
  RETURNING * INTO r;
  RETURN to_jsonb(r);
END $$;
-- Metadata sentinels, NOT claimed to be live implementations/signatures.
-- Snapshot tests prove this migration leaves all non-target functions/ACLs alone.
CREATE FUNCTION public.alpha_evaluate_campaign_route() RETURNS text LANGUAGE sql AS $$ SELECT 'evaluator sentinel'::text $$;
CREATE FUNCTION public.alpha_reconcile_route_execution_from_broker() RETURNS text LANGUAGE sql AS $$ SELECT 'broker sentinel'::text $$;
CREATE FUNCTION public.alpha_expire_session_routes() RETURNS text LANGUAGE sql AS $$ SELECT 'expiry sentinel'::text $$;
CREATE FUNCTION public.alpha_route_monitor_tick() RETURNS text LANGUAGE sql AS $$ SELECT 'monitor sentinel'::text $$;
REVOKE ALL ON FUNCTION public.alpha_evaluate_campaign_route(),
  public.alpha_reconcile_route_execution_from_broker(),public.alpha_expire_session_routes(),
  public.alpha_route_monitor_tick() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.alpha_evaluate_campaign_route(),
  public.alpha_reconcile_route_execution_from_broker(),public.alpha_expire_session_routes(),
  public.alpha_route_monitor_tick() TO service_role;

-- Deterministic pre-open clock ONLY in this disposable test database.
-- Target migration/function source is executed byte-for-byte, not patched for time.
CREATE OR REPLACE FUNCTION pg_catalog.now() RETURNS timestamptz LANGUAGE sql STABLE
AS $$ SELECT current_setting('test.clock')::timestamptz $$;
SET test.clock='2026-09-08 02:30:00+00';
