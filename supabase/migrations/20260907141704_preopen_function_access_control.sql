REVOKE EXECUTE ON FUNCTION public.alpha_lock_capital_owner_preopen() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alpha_lock_capital_owner_preopen() TO postgres, service_role;
