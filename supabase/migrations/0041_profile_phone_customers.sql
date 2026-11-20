-- Telefono en el perfil y lista de clientes para el panel.
alter table public.profiles add column phone text
  check (phone is null or phone ~ '^\+?[0-9 ()-]{7,20}$');

-- Clientes para el panel (solo service role). Datos de la cuenta y
-- metricas de uso; nunca movimientos individuales.
create or replace function public.admin_customers(
  p_search text default null, p_limit integer default 50, p_offset integer default 0
) returns jsonb
language sql stable security definer set search_path = public, auth, pg_temp as $$
  with base as (
    select u.id, u.email, u.created_at, u.last_sign_in_at,
           p.full_name, p.phone, p.gender, p.age, p.occupation
    from auth.users u
    left join public.profiles p on p.id = u.id
    where p_search is null or p_search = ''
       or u.email ilike '%' || p_search || '%'
       or p.full_name ilike '%' || p_search || '%'
       or p.phone ilike '%' || p_search || '%'
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'rows', coalesce((
      select jsonb_agg(row_to_json(x) order by x.created_at desc)
      from (
        select b.*,
          (select max(t.created_at) from public.transactions t where t.user_id = b.id) as last_activity,
          (select count(*) from public.transactions t where t.user_id = b.id) as transactions,
          (select count(*) from public.dgi_receipts r where r.user_id = b.id) as receipts,
          coalesce((select pb.confirmed_points from public.points_balances pb where pb.user_id = b.id), 0) as cashback_cents,
          coalesce((select pb.habit_points from public.points_balances pb where pb.user_id = b.id), 0) as points,
          (select count(*) from public.reward_redemptions rr where rr.user_id = b.id) as redemptions,
          exists (select 1 from public.device_push_tokens d where d.user_id = b.id) as has_push,
          (select jsonb_object_agg(c.purpose, c.granted) from public.current_consents c where c.user_id = b.id) as consents,
          (select s.status from public.subscriptions s where s.user_id = b.id order by s.updated_at desc nulls last limit 1) as subscription
        from base b
        order by b.created_at desc
        limit greatest(least(p_limit, 200), 1) offset greatest(p_offset, 0)
      ) x), '[]'::jsonb)
  );
$$;
revoke execute on function public.admin_customers(text, integer, integer) from public, anon, authenticated;
