-- PREPARE ONLY. Run via psql in an explicitly approved isolated database.
-- Requires the existing zero-argument function and Supabase role definitions.
-- Does not create/replace or invoke the target function or any business RPC.
\set ON_ERROR_STOP on
\if :{?ACL_TEST_ISOLATED}
SELECT :'ACL_TEST_ISOLATED' = 'yes' AS acl_test_isolated \gset
\else
\echo 'FAIL: set ACL_TEST_ISOLATED=yes only for an isolated test database.'
\quit 3
\endif
\if :acl_test_isolated
\else
\echo 'FAIL: isolated test database acknowledgement required.'
\quit 3
\endif

BEGIN;

DO $preflight$
DECLARE
  target_oid oid := to_regprocedure('public.alpha_lock_capital_owner_preopen()');
  role_name text;
BEGIN
  IF target_oid IS NULL THEN
    RAISE EXCEPTION 'FAIL: existing zero-argument target function required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid = target_oid AND prokind = 'f' AND prosecdef
  ) THEN
    RAISE EXCEPTION 'FAIL: expected existing SECURITY DEFINER function';
  END IF;
  -- Do not silently leave a same-name overload exposed.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'alpha_lock_capital_owner_preopen') <> 1 THEN
    RAISE EXCEPTION 'FAIL: unexpected overloads; review exact signatures before proceeding';
  END IF;
  FOREACH role_name IN ARRAY ARRAY['postgres', 'service_role', 'anon', 'authenticated'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      RAISE EXCEPTION 'FAIL: required role % missing', role_name;
    END IF;
  END LOOP;
END;
$preflight$;

-- Snapshot BEFORE applying the actual migration: no hard-coded body or hash.
CREATE TEMP TABLE preopen_acl_target_before ON COMMIT DROP AS
SELECT oid, pg_get_functiondef(oid) AS definition, to_jsonb(p) AS catalog_row
FROM pg_proc p
WHERE oid = 'public.alpha_lock_capital_owner_preopen()'::regprocedure;

CREATE TEMP TABLE preopen_acl_other_functions_before ON COMMIT DROP AS
SELECT oid, to_jsonb(p) AS catalog_row
FROM pg_proc p
WHERE oid <> 'public.alpha_lock_capital_owner_preopen()'::regprocedure;

-- Include the checked-in migration, not a duplicated imitation of its SQL.
\ir ../migrations/20260907143201_preopen_function_access_control.sql

CREATE TEMP TABLE preopen_acl_after_first ON COMMIT DROP AS
SELECT oid, proacl FROM pg_proc
WHERE oid = 'public.alpha_lock_capital_owner_preopen()'::regprocedure;

-- Reapplying the access-only migration must leave the same permissions.
\ir ../migrations/20260907143201_preopen_function_access_control.sql

DO $assertions$
DECLARE
  target_oid oid := 'public.alpha_lock_capital_owner_preopen()'::regprocedure;
  role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    -- Checks effective privileges, including inherited and PUBLIC grants.
    IF has_function_privilege(role_name, target_oid, 'EXECUTE') IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'FAIL: % retains effective EXECUTE', role_name;
    END IF;
    RAISE NOTICE 'PASS: % cannot execute target function', role_name;
  END LOOP;

  -- PUBLIC is a pseudo-role (ACL grantee OID 0), not a pg_roles entry.
  -- A NULL proacl means default ACL, which must also be expanded and checked.
  IF EXISTS (
    SELECT 1 FROM pg_proc p,
    LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid = target_oid AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'FAIL: PUBLIC retains EXECUTE';
  END IF;
  RAISE NOTICE 'PASS: PUBLIC has no EXECUTE grant';

  FOREACH role_name IN ARRAY ARRAY['postgres', 'service_role'] LOOP
    IF has_function_privilege(role_name, target_oid, 'EXECUTE') IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'FAIL: % lost effective EXECUTE', role_name;
    END IF;
    IF has_schema_privilege(role_name, 'public', 'USAGE') IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'FAIL: % lacks existing public schema USAGE', role_name;
    END IF;
    RAISE NOTICE 'PASS: % retains function EXECUTE and schema USAGE', role_name;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM preopen_acl_target_before b JOIN pg_proc p USING (oid)
    WHERE b.definition IS NOT DISTINCT FROM pg_get_functiondef(p.oid)
      AND (b.catalog_row - 'proacl') IS NOT DISTINCT FROM (to_jsonb(p) - 'proacl')
  ) THEN
    RAISE EXCEPTION 'FAIL: target definition/body or non-ACL metadata changed';
  END IF;
  RAISE NOTICE 'PASS: target definition/body and non-ACL metadata unchanged';

  IF EXISTS (
    SELECT 1
    FROM preopen_acl_other_functions_before b
    FULL JOIN (SELECT oid, to_jsonb(p) AS catalog_row FROM pg_proc p
               WHERE oid <> target_oid) a USING (oid)
    WHERE b.catalog_row IS DISTINCT FROM a.catalog_row
  ) THEN
    RAISE EXCEPTION 'FAIL: another function was added, removed or changed';
  END IF;
  RAISE NOTICE 'PASS: all other functions unchanged';

  IF NOT EXISTS (
    SELECT 1 FROM preopen_acl_after_first b JOIN pg_proc p USING (oid)
    WHERE b.proacl IS NOT DISTINCT FROM p.proacl
  ) THEN
    RAISE EXCEPTION 'FAIL: migration is not idempotent';
  END IF;
  RAISE NOTICE 'PASS: repeat migration preserves the same ACL';
END;
$assertions$;

ROLLBACK;
\echo 'PASS: preopen function access regression; test transaction rolled back.'
