-- Cuenta de revision de Apple (apple-review@monavi.app): movimientos
-- recientes para que la pantalla Hoy y el cierre del dia tengan contenido
-- mientras Apple revisa la app. Solo toca esa cuenta.
--
-- 1) Rellena del 8 al 12 de noviembre.
-- 2) Tres jobs diarios (manana, mediodia, noche, hora de Panama) agregan
--    un movimiento cada uno con la hora real.
-- Quitar cuando la app este aprobada:
--   select cron.unschedule('demo-review-morning'); (y midday / evening)

create or replace function public.demo_review_insert(p_at timestamptz, p_account text, p_amount numeric,
  p_category text, p_description text, p_type text default 'gasto')
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := (select id from auth.users where email = 'apple-review@monavi.app');
  v_account uuid;
begin
  if v_user is null then return; end if;
  select id into v_account from public.accounts where user_id = v_user and name = p_account limit 1;
  if v_account is null then return; end if;
  insert into public.transactions (user_id, account_id, amount, category, description, occurred_at, created_at, movement_type)
  values (v_user, v_account, p_amount, p_category, p_description, p_at, p_at, p_type);
  update public.accounts set balance = balance + p_amount where id = v_account;
end $$;
revoke execute on function public.demo_review_insert(timestamptz, text, numeric, text, text, text) from public, anon, authenticated;

-- p_slot: 1 manana, 2 mediodia, 3 noche. Elige uno al azar del grupo.
create or replace function public.demo_review_tick(p_slot int)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_options jsonb := case p_slot
    when 1 then '[["Efectivo",-2.75,"Comida","Café"],["Visa Clásica",-6.40,"Transporte","Uber"],["Efectivo",-3.50,"Comida","Café y empanada"],["Visa Clásica",-30.00,"Transporte","Gasolina"]]'
    when 2 then '[["Efectivo",-6.50,"Comida","Almuerzo fonda"],["Visa Clásica",-8.90,"Comida","Almuerzo"],["Visa Clásica",-11.40,"Salud","Farmacia"],["Visa Clásica",-14.25,"Compras","Artículos de casa"]]'
    else '[["Visa Clásica",-38.70,"Supermercado","Super 99"],["Visa Clásica",-52.30,"Supermercado","Riba Smith"],["Visa Clásica",-24.00,"Salir","Cena"],["Visa Clásica",-14.00,"Entretenimiento","Cine"],["Visa Clásica",-26.50,"Mascotas","Comida para Luna"]]'
  end::jsonb;
  v_pick jsonb := v_options -> floor(random() * jsonb_array_length(v_options))::int;
begin
  perform public.demo_review_insert(now(), v_pick ->> 0, (v_pick ->> 1)::numeric, v_pick ->> 2, v_pick ->> 3);
end $$;
revoke execute on function public.demo_review_tick(int) from public, anon, authenticated;

-- Relleno 8-12 de noviembre (hora de Panama = UTC-5).
select public.demo_review_insert(t.at at time zone 'America/Panama', t.acc, t.amt, t.cat, t.descr, t.typ)
from (values
  (timestamp '2026-11-08 10:30', 'Visa Clásica', -52.30, 'Supermercado', 'Riba Smith', 'gasto'),
  (timestamp '2026-11-08 19:20', 'Visa Clásica', -14.00, 'Entretenimiento', 'Cine', 'gasto'),
  (timestamp '2026-11-09 12:45', 'Efectivo', -6.50, 'Comida', 'Almuerzo fonda', 'gasto'),
  (timestamp '2026-11-09 17:10', 'Visa Clásica', -30.00, 'Transporte', 'Gasolina', 'gasto'),
  (timestamp '2026-11-10 08:10', 'Efectivo', -2.75, 'Comida', 'Café', 'gasto'),
  (timestamp '2026-11-10 13:05', 'Visa Clásica', -11.40, 'Salud', 'Farmacia', 'gasto'),
  (timestamp '2026-11-11 09:00', 'Banco General', -45.00, 'Servicios', 'Internet', 'gasto'),
  (timestamp '2026-11-11 18:40', 'Visa Clásica', -28.60, 'Supermercado', 'Super 99', 'gasto'),
  (timestamp '2026-11-12 08:20', 'Visa Clásica', -5.90, 'Transporte', 'Uber', 'gasto'),
  (timestamp '2026-11-12 12:30', 'Efectivo', -7.25, 'Comida', 'Almuerzo', 'gasto'),
  (timestamp '2026-11-12 15:00', 'Banco General', 250.00, 'Ingreso', 'Pago freelance', 'ingreso'),
  (timestamp '2026-11-12 19:15', 'Visa Clásica', -24.00, 'Salir', 'Cena', 'gasto')
) as t(at, acc, amt, cat, descr, typ);

-- 8:40 am, 12:50 pm y 7:25 pm de Panama.
select cron.schedule('demo-review-morning', '40 13 * * *', 'select public.demo_review_tick(1)');
select cron.schedule('demo-review-midday', '50 17 * * *', 'select public.demo_review_tick(2)');
select cron.schedule('demo-review-evening', '25 0 * * *', 'select public.demo_review_tick(3)');
