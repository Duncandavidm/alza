-- Países que la app puede ofrecer. Colombia queda apagada hasta que se
-- active desde el panel (Sistema > Países). Mientras esté apagada la app
-- no muestra "¿Dónde vives?" ni "País y moneda": todo el mundo queda en
-- Panamá, igual que antes de la 1.0.7.
insert into public.app_config (key, value) values ('colombia_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Lectura pública y mínima: solo las banderas que la app necesita (la
-- tabla app_config sigue cerrada por RLS).
create or replace function public.get_app_flags()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'colombia_enabled',
    coalesce((select value from public.app_config where key = 'colombia_enabled'), 'false'::jsonb)
  );
$$;

revoke all on function public.get_app_flags() from public;
grant execute on function public.get_app_flags() to anon, authenticated;
