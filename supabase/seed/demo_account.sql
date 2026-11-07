-- Cuenta de demostracion para capturas de App Store.
--
-- Llena UNA cuenta ya creada (se registra primero en la app) con: cuentas
-- y saldos, ~75 dias de movimientos, presupuestos, metas con aportes,
-- pagos fijos, facturas por pagar, una deuda, facturas verificadas con
-- detalle (cashback > $3.50), puntos por habitos (los calcula
-- award_habit_points, igual que el job diario) y un canje ya entregado.
--
-- Uso: cambiar el correo de abajo y correrlo en el SQL Editor. Si la
-- cuenta ya tiene movimientos, no hace nada (para no duplicar).
do $$
declare
  v_email text := 'davidmunozduncan@gmail.com';
  u uuid;
  acc_bank uuid; acc_save uuid; acc_cash uuid; acc_card uuid;
  g_trip uuid; g_emerg uuid; g_laptop uuid;
  d date;
  i int;
  r record;
  rid uuid;
  tz text := 'America/Panama';
  today date := (now() at time zone 'America/Panama')::date;
  v_ts timestamptz;
  v_item uuid;
  v_merchant uuid;
begin
  select id into u from auth.users where lower(email) = lower(v_email);
  if u is null then
    raise exception 'No existe la cuenta %: registrala primero en la app', v_email;
  end if;
  if exists (select 1 from public.transactions where user_id = u) then
    raise notice 'La cuenta ya tiene movimientos: no se cargan datos de demostracion';
    return;
  end if;

  -- Perfil y consentimientos ---------------------------------------------
  insert into public.profiles (id, full_name, age, gender, marital_status, occupation, onboarding_completed_at, dgi_scan_consent_at)
  values (u, 'David', 34, 'masculino', 'casado', 'Emprendedor', now() - interval '80 days', now() - interval '75 days')
  on conflict (id) do update set
    full_name = coalesce(public.profiles.full_name, excluded.full_name),
    age = coalesce(public.profiles.age, excluded.age),
    gender = coalesce(public.profiles.gender, excluded.gender),
    onboarding_completed_at = coalesce(public.profiles.onboarding_completed_at, excluded.onboarding_completed_at),
    dgi_scan_consent_at = coalesce(public.profiles.dgi_scan_consent_at, excluded.dgi_scan_consent_at);

  insert into public.user_consents (user_id, purpose, granted, source)
  values (u, 'programa_recompensas', true, 'app'), (u, 'estudio_mercado', true, 'app');

  -- Cuentas (saldo actual) -------------------------------------------------
  insert into public.accounts (user_id, name, type, balance, currency) values (u, 'Banco General', 'checking', 2845.60, 'USD') returning id into acc_bank;
  insert into public.accounts (user_id, name, type, balance, currency) values (u, 'Cuenta de ahorros', 'savings', 1970.00, 'USD') returning id into acc_save;
  insert into public.accounts (user_id, name, type, balance, currency) values (u, 'Efectivo', 'cash', 86.40, 'USD') returning id into acc_cash;
  insert into public.accounts (user_id, name, type, balance, currency) values (u, 'Visa Clásica', 'credit_card', -412.35, 'USD') returning id into acc_card;

  -- Ingresos: quincena (1 y 15) + un trabajo extra -------------------------
  for d in select generate_series(today - 75, today, interval '1 day')::date loop
    if extract(day from d) in (1, 15) then
      v_ts := (d::text || ' 08:15')::timestamp at time zone tz;
      insert into public.transactions (user_id, account_id, amount, movement_type, category, description, occurred_at, created_at)
      values (u, acc_bank, 1150.00, 'ingreso', 'Ingreso', 'Salario quincena', v_ts, v_ts);
    end if;
  end loop;
  v_ts := ((today - 20)::text || ' 17:40')::timestamp at time zone tz;
  insert into public.transactions (user_id, account_id, amount, movement_type, category, description, occurred_at, created_at)
  values (u, acc_bank, 350.00, 'ingreso', 'Ingreso', 'Diseño de logo (cliente)', v_ts, v_ts);

  -- Gastos fijos del mes ---------------------------------------------------
  for d in select generate_series(date_trunc('month', today - 75)::date, today, interval '1 month')::date loop
    for r in select * from (values
        (1, 650.00, 'Vivienda', 'Alquiler apartamento', 'bank'),
        (5, 68.40, 'Servicios', 'Luz (ENSA)', 'bank'),
        (8, 45.00, 'Servicios', 'Internet y cable', 'bank'),
        (10, 18.50, 'Servicios', 'Celular', 'card'),
        (12, 12.99, 'Suscripciones', 'Netflix', 'card'),
        (12, 5.99, 'Suscripciones', 'Spotify', 'card'),
        (20, 35.00, 'Salud', 'Gimnasio', 'card')
      ) as x(dom, amount, category, descr, acc)
    loop
      continue when (d + (r.dom - 1)) > today or (d + (r.dom - 1)) < today - 75;
      v_ts := ((d + (r.dom - 1))::text || ' 09:30')::timestamp at time zone tz;
      insert into public.transactions (user_id, account_id, amount, movement_type, category, description, occurred_at, created_at)
      values (u, case r.acc when 'card' then acc_card else acc_bank end, -r.amount, 'gasto', r.category, r.descr, v_ts, v_ts);
    end loop;
  end loop;

  -- Gastos del dia a dia: casi todos los dias (para rachas y puntos) -------
  i := 0;
  for d in select generate_series(today - 74, today, interval '1 day')::date loop
    i := i + 1;
    -- 2 o 3 dias sin anotar, para que la racha se vea real
    continue when i in (19, 41);
    for r in select * from (values
        (1, 'Comida', 'Almuerzo fonda', 6.50, '12:40', 'cash'),
        (2, 'Transporte', 'Uber', 7.80, '08:10', 'card'),
        (3, 'Comida', 'Café y empanada', 3.75, '07:50', 'cash'),
        (4, 'Supermercado', 'Super 99', 38.60, '19:15', 'card'),
        (5, 'Transporte', 'Gasolina', 30.00, '18:05', 'card'),
        (6, 'Salir', 'Cena con amigos', 32.40, '21:10', 'card'),
        (7, 'Comida', 'Almuerzo', 9.25, '13:05', 'card'),
        (8, 'Compras', 'Farmacia', 14.30, '17:20', 'card'),
        (9, 'Entretenimiento', 'Cine', 16.00, '20:30', 'card'),
        (10, 'Supermercado', 'Riba Smith', 52.75, '11:00', 'card'),
        (11, 'Mascotas', 'Comida para Luna', 24.90, '16:45', 'card'),
        (12, 'Ropa', 'Camisa', 29.99, '15:30', 'card'),
        (13, 'Comida', 'Desayuno', 5.50, '08:20', 'cash'),
        (14, 'Regalos', 'Regalo cumpleaños', 25.00, '18:40', 'card')
      ) as x(slot, category, descr, amount, hhmm, acc)
    loop
      -- Cada dia toca 1 o 2 gastos, rotando por la lista
      continue when r.slot not in (((i - 1) % 14) + 1, ((i * 5) % 14) + 1);
      v_ts := (d::text || ' ' || r.hhmm)::timestamp at time zone tz;
      continue when v_ts > now();
      insert into public.transactions (user_id, account_id, amount, movement_type, category, description, occurred_at, created_at)
      values (u, case r.acc when 'cash' then acc_cash else acc_card end,
              -round((r.amount * (0.85 + ((i * 7) % 30) / 100.0))::numeric, 2),
              'gasto', r.category, r.descr, v_ts, v_ts);
    end loop;
  end loop;

  -- Presupuestos (creados antes del periodo, para que cuenten) -------------
  insert into public.budgets (user_id, category, period, limit_amount, color, created_at, updated_at) values
    (u, 'Comida', 'monthly', 260, null, now() - interval '80 days', now() - interval '80 days'),
    (u, 'Supermercado', 'monthly', 450, null, now() - interval '80 days', now() - interval '80 days'),
    (u, 'Transporte', 'monthly', 260, null, now() - interval '80 days', now() - interval '80 days'),
    (u, 'Salir', 'monthly', 150, null, now() - interval '80 days', now() - interval '80 days'),
    (u, 'Entretenimiento', 'monthly', 60, null, now() - interval '80 days', now() - interval '80 days');

  -- Metas de ahorro con aportes semanales ---------------------------------
  insert into public.savings_goals (user_id, name, emoji, target_amount, target_date, current_amount, account_id, created_at, updated_at)
  values (u, 'Viaje a Boquete', '🏔️', 800, today + 120, 0, acc_save, now() - interval '78 days', now()) returning id into g_trip;
  insert into public.savings_goals (user_id, name, emoji, target_amount, target_date, current_amount, account_id, created_at, updated_at)
  values (u, 'Fondo de emergencia', '🛟', 3000, today + 300, 0, acc_save, now() - interval '78 days', now()) returning id into g_emerg;
  insert into public.savings_goals (user_id, name, emoji, target_amount, target_date, current_amount, account_id, created_at, updated_at)
  values (u, 'Laptop nueva', '💻', 1200, today + 180, 0, acc_save, now() - interval '78 days', now()) returning id into g_laptop;

  alter table public.savings_contributions disable trigger savings_contributions_force_now;
  for i in 0..10 loop
    v_ts := now() - make_interval(days => 72 - i * 7);
    insert into public.savings_contributions (user_id, goal_id, amount, created_at) values
      (u, g_trip, 40, v_ts),
      (u, g_emerg, 100, v_ts + interval '1 hour');
    if i % 2 = 0 then
      insert into public.savings_contributions (user_id, goal_id, amount, created_at) values (u, g_laptop, 50, v_ts + interval '2 hours');
    end if;
  end loop;
  alter table public.savings_contributions enable trigger savings_contributions_force_now;
  update public.savings_goals g
     set current_amount = (select coalesce(sum(amount), 0) from public.savings_contributions c where c.goal_id = g.id)
   where g.user_id = u;

  -- Pagos fijos, facturas por pagar y deuda --------------------------------
  insert into public.recurring_transactions (user_id, account_id, name, amount, movement_type, category, day_of_month, active) values
    (u, acc_bank, 'Alquiler', 650, 'gasto', 'Vivienda', 1, true),
    (u, acc_card, 'Netflix', 12.99, 'gasto', 'Suscripciones', 12, true),
    (u, acc_card, 'Gimnasio', 35, 'gasto', 'Salud', 20, true),
    (u, acc_bank, 'Salario (1ra quincena)', 1150, 'ingreso', 'Ingreso', 1, true),
    (u, acc_bank, 'Salario (2da quincena)', 1150, 'ingreso', 'Ingreso', 15, true);

  insert into public.bills (user_id, account_id, name, amount, due_date, category, movement_type, priority, status) values
    (u, acc_bank, 'Luz (ENSA)', 71.20, today + 3, 'Servicios', 'gasto', 'alta', 'pendiente'),
    (u, acc_bank, 'Internet y cable', 45.00, today + 8, 'Servicios', 'gasto', 'normal', 'pendiente'),
    (u, acc_bank, 'Seguro del auto', 96.00, today + 14, 'Transporte', 'gasto', 'alta', 'pendiente');

  insert into public.debts (user_id, creditor, balance, credit_limit, interest_rate_monthly, minimum_payment, due_date, is_overdue, status)
  values (u, 'Visa Clásica', 412.35, 2000, 2.25, 25, today + 12, false, 'active');

  -- Facturas verificadas (cashback 1%) con detalle --------------------------
  for r in select * from (values
      (1, 'DEMO-8000001', 'Super 99', 142.30, 'Tarjeta de crédito', 6, '19:10', 'ARROZ 5 LB|1|4.95;LECHE ENTERA 1L|4|1.45;POLLO ENTERO|2|8.90;HUEVOS 30 UND|1|6.25;DETERGENTE 3L|1|11.40'),
      (2, 'DEMO-8000002', 'Riba Smith', 96.75, 'Tarjeta de débito', 13, '11:05', 'CAFE MOLIDO 425G|1|7.95;QUESO BLANCO|1|5.60;MANZANAS KG|2|3.80;YOGURT GRIEGO|3|2.35'),
      (3, 'DEMO-8000003', 'Farmacia Metro', 47.35, 'Tarjeta de crédito', 20, '17:25', 'VITAMINA C 100 TAB|1|12.90;PROTECTOR SOLAR|1|18.75;ACETAMINOFEN|1|4.20'),
      (4, 'DEMO-8000004', 'Super 99', 88.10, 'Efectivo', 27, '18:45', 'PAN DE MOLDE|2|3.25;REFRESCO COLA 2L|2|2.40;PASTA 500G|3|1.35;SALSA DE TOMATE|2|1.95'),
      (5, 'DEMO-8000005', 'Café La Esquina', 28.45, 'Tarjeta de crédito', 34, '08:05', 'CAPUCHINO 12OZ|3|3.50;CROISSANT|2|2.75;CAFE FRIO 16OZ|1|4.25'),
      (6, 'DEMO-8000006', 'Riba Smith', 64.20, 'Tarjeta de crédito', 41, '10:30', 'SALMON FILETE|1|14.80;AGUACATE|3|1.60;AGUA MINERAL 6PK|1|4.95'),
      (7, 'DEMO-8000007', 'Do it Center', 58.90, 'Tarjeta de débito', 48, '15:15', 'FOCO LED 3PK|1|9.95;EXTENSION 6 PIES|1|7.45;PINTURA GALON|1|22.90'),
      (8, 'DEMO-8000008', 'Super 99', 35.60, 'Yappy', 55, '20:05', 'LECHE ENTERA 1L|6|1.45;BANANOS|1|1.80;CEREAL 500G|1|5.25')
    ) as x(n, cufe, merchant, amount, pay, days_ago, hhmm, lines)
  loop
    v_ts := ((today - r.days_ago)::text || ' ' || r.hhmm)::timestamp at time zone tz;
    insert into public.dgi_receipts (user_id, cufe, i_amb, tipo_doc, tipo_contribuyente, ruc, dv, sucursal, fecha_factura,
        numero_documento, punto_facturacion, tipo_emision, numero_seguridad, digito_verificador, status, confirmed_amount,
        payment_method, merchant_name, authorized_at, scanned_at, dgi_checked_at, dgi_check_count)
    values (u, r.cufe, '1', '01', '2', 'DEMO-RUC-' || r.n, '00', '0001', today - r.days_ago,
        lpad(r.n::text, 10, '0'), '001', '01', '000000000', '0', 'confirmada', r.amount,
        r.pay, r.merchant, v_ts, v_ts + interval '20 minutes', v_ts + interval '1 day', 1)
    returning id into rid;

    insert into public.dgi_receipt_items (receipt_id, user_id, line_no, description, quantity, unit_price, total)
    select rid, u, ord, split_part(line, '|', 1), split_part(line, '|', 2)::numeric, split_part(line, '|', 3)::numeric,
           split_part(line, '|', 2)::numeric * split_part(line, '|', 3)::numeric
    from unnest(string_to_array(r.lines, ';')) with ordinality as l(line, ord);

    insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
    values (u, 'factura', 'factura:' || r.cufe, floor(r.amount)::int, 'confirmado', v_ts + interval '20 minutes',
            jsonb_build_object('cufe', r.cufe, 'confirmedAmount', r.amount, 'demo', true));
  end loop;

  -- Una factura pendiente de verificar (se ve "Pendiente")
  v_ts := now() - interval '3 hours';
  insert into public.dgi_receipts (user_id, cufe, i_amb, tipo_doc, tipo_contribuyente, ruc, dv, sucursal, fecha_factura,
      numero_documento, punto_facturacion, tipo_emision, numero_seguridad, digito_verificador, status, scanned_at)
  values (u, 'DEMO-8000009', '1', '01', '2', 'DEMO-RUC-9', '00', '0001', today,
      '0000000009', '001', '01', '000000000', '0', 'pendiente', v_ts);

  -- Puntos por habitos: los calcula el servidor con las reglas reales ------
  perform public.award_habit_points();

  -- Un canje ya entregado (se ve en "Mis canjes") con puntos ----------------
  select ri.id, ri.merchant_id into v_item, v_merchant
    from public.reward_items ri join public.partner_merchants pm on pm.id = ri.merchant_id
   where pm.reward_currency = 'puntos' and ri.status = 'active'
   order by ri.points_cost limit 1;
  if v_item is not null and (select habit_points from public.points_balances where user_id = u) >= 80 then
    v_ts := now() - interval '9 days';
    insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, status, expires_at,
        delivered_at, created_at, delivered_via, currency)
    select u, v_item, v_merchant, ri.points_cost, upper(substr(md5(random()::text), 1, 6)), 'entregado', v_ts + interval '7 days',
           v_ts + interval '2 hours', v_ts, 'comercio', 'puntos'
      from public.reward_items ri where ri.id = v_item
    returning id into rid;
    insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
    select u, 'canje_puntos', 'canje:' || rid, -ri.points_cost, 'confirmado', v_ts, jsonb_build_object('redemption', rid, 'demo', true)
      from public.reward_items ri where ri.id = v_item;
  end if;

  raise notice 'Listo: %', (select row_to_json(b) from public.points_balances b where b.user_id = u);
end $$;
