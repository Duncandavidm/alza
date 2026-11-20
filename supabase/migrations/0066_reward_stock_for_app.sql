-- Datos para la app 1.0.3 (aditivo: 1.0.2 y anteriores lo ignoran).
--
-- 1) reward_items.used_count: codigos que ya gastaron cupo, para que la
--    app muestre "Quedan 5". Lo mantiene el mismo trigger de 0065 (solo en
--    canjes con limite; sin limite queda en 0 y la app no lo usa).
--
-- 2) my_redemption_items(): los productos que la persona ya canjeo, aunque
--    hoy esten agotados o pausados. La RLS de reward_items solo deja ver
--    los activos (asi el catalogo de las apps viejas no muestra agotados),
--    por eso "Mis canjes" llegaba con el producto en null ("tu producto").
--    La 1.0.3 completa con esto los que falten. No se toca la RLS.

alter table public.reward_items
  add column if not exists used_count integer not null default 0;

create or replace function public.reward_items_apply_stock()
returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_used integer;
begin
  if new.max_redemptions is null then
    new.used_count := 0;
    if new.status = 'agotado' then new.status := 'active'; end if;
    return new;
  end if;

  v_used := public.reward_item_used(new.id);
  new.used_count := v_used;
  if new.status in ('active', 'agotado') then
    new.status := case when v_used >= new.max_redemptions then 'agotado' else 'active' end;
  end if;
  return new;
end $$;

-- Recalcula los que ya tienen limite.
update public.reward_items set updated_at = now() where max_redemptions is not null;

create or replace function public.my_redemption_items()
returns setof public.reward_items
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select ri.*
  from public.reward_items ri
  where exists (
    select 1 from public.reward_redemptions rr
    where rr.reward_item_id = ri.id and rr.user_id = auth.uid()
  );
$$;
revoke all on function public.my_redemption_items() from public, anon;
grant execute on function public.my_redemption_items() to authenticated;
