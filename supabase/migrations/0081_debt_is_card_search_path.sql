-- 0081: aviso de seguridad de Supabase (function_search_path_mutable)
-- sobre debt_is_card (0079). Fija el search_path como en el resto.
alter function public.debt_is_card(text, numeric) set search_path = public, pg_temp;
