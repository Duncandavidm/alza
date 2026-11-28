-- 1.1.0: las funciones de señales de revisión (0100) solo corren como
-- triggers. Nadie debe poder llamarlas por /rest/v1/rpc.
revoke execute on function public.transactions_income_review_signals() from public, anon, authenticated;
revoke execute on function public.dgi_receipts_review_signals() from public, anon, authenticated;
revoke execute on function public.profiles_phone_review_signal() from public, anon, authenticated;
