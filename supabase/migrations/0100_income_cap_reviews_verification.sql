-- 0100: control de ingresos inventados para cashback (1.1.0).
--
-- 1. Tope de ingreso sin verificar: para respaldar cashback solo cuentan
--    hasta 3,000 al mes (Panamá, en USD; Colombia 12,000,000 COP). Con
--    ingresos verificados (documento aprobado en el panel, 6 meses) cuenta
--    el monto verificado. La persona puede anotar lo que quiera para su
--    presupuesto: esto solo afecta el cashback.
-- 2. Revisiones de cashback: patrones raros abren una revisión y el
--    cashback nuevo queda retenido hasta que el panel la apruebe o la anule.
--    No se agrega un estado nuevo a dgi_receipts.cashback_status (las
--    versiones viejas de la app no lo conocen): lo retenido sigue como
--    'sin_ingreso' y la revisión vive en cashback_reviews.
-- 3. Dispositivos: varias cuentas en el mismo iPhone abren revisión.
-- 4. Verificación de ingresos: la app sube el documento (bucket privado),
--    la IA lo lee y el panel aprueba el monto. El documento se borra al
--    revisarlo.

-- ---------------------------------------------------------------- config
insert into public.app_config (key, value)
values ('unverified_income_cap', '{"PA": 3000, "CO": 12000000}'::jsonb)
on conflict (key) do nothing;

update public.app_config
   set value = coalesce(value, '{}'::jsonb) || '{"read-income-document": {"limit": 6, "period": "month"}}'::jsonb
 where key = 'ai_quotas';

-- ---------------------------------------------------------------- perfil
alter table public.profiles
  add column if not exists verified_income numeric(14, 2),
  add column if not exists verified_income_until date;

-- Ingreso mensual máximo que respalda cashback para esta persona.
create or replace function public.user_income_cap(p_user uuid)
returns numeric
language sql stable security definer set search_path = public, pg_temp as $$
  with p as (select country, verified_income, verified_income_until from public.profiles where id = p_user),
  cap as (
    select coalesce(
      ((select value from public.app_config where key = 'unverified_income_cap') ->> coalesce((select country from p), 'PA'))::numeric,
      3000) as amount
  )
  select case
    when (select verified_income_until from p) >= current_date and (select verified_income from p) is not null
      then greatest((select amount from cap), (select verified_income from p))
    else (select amount from cap)
  end
$$;
revoke execute on function public.user_income_cap(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- revisiones
create table if not exists public.cashback_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (reason in (
    'ingreso_inusual', 'ingreso_a_la_medida', 'ingreso_editado', 'muchas_facturas',
    'dispositivo_compartido', 'telefono_repetido', 'manual')),
  details jsonb not null default '{}'::jsonb,
  status text not null default 'abierta' check (status in ('abierta', 'aprobada', 'anulada')),
  note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create unique index if not exists cashback_reviews_one_open
  on public.cashback_reviews (user_id, reason) where status = 'abierta';
create index if not exists cashback_reviews_status_idx on public.cashback_reviews (status, created_at desc);
alter table public.cashback_reviews enable row level security;
-- Solo el panel (service role) la lee y la cambia.

create or replace function public.open_cashback_review(p_user uuid, p_reason text, p_details jsonb)
returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.cashback_reviews (user_id, reason, details)
  values (p_user, p_reason, coalesce(p_details, '{}'::jsonb))
  on conflict (user_id, reason) where status = 'abierta' do nothing;
$$;
revoke execute on function public.open_cashback_review(uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.user_has_open_review(p_user uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.cashback_reviews where user_id = p_user and status = 'abierta');
$$;
revoke execute on function public.user_has_open_review(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- respaldo
-- Igual que antes (ingresos de 35 días, anotados hace 48 h o más), pero el
-- ingreso que cuenta no pasa del tope de la persona.
create or replace function public.receipt_income_backed(p_receipt_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  with r as (
    select id, user_id, confirmed_amount as amount, coalesce(authorized_at, scanned_at) as at
    from dgi_receipts where id = p_receipt_id
  ),
  income as (
    select coalesce(sum(t.amount), 0) as total
    from transactions t, r
    where t.user_id = r.user_id and t.movement_type = 'ingreso' and t.amount > 0
      and t.occurred_at >= r.at - interval '35 days' and t.occurred_at <= r.at + interval '3 days'
      and t.created_at <= now() - interval '48 hours'
  ),
  backed as (
    select coalesce(sum(o.confirmed_amount), 0) as total
    from dgi_receipts o, r
    where o.user_id = r.user_id and o.id <> r.id and o.cashback_status = 'acreditado'
      and coalesce(o.authorized_at, o.scanned_at) between r.at - interval '30 days' and r.at
  )
  select coalesce((select amount from r), 0) + (select total from backed)
         <= least((select total from income), public.user_income_cap((select user_id from r)))
$$;

-- Con una revisión abierta, el cashback nuevo queda retenido.
create or replace function public.points_ledger_hold_unbacked_cashback()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_receipt public.dgi_receipts;
  v_review boolean;
begin
  if new.status <> 'confirmado' or new.points <= 0
     or new.source not in ('factura', 'tarjeta')
     or new.external_ref not like 'factura:%' then
    return new;
  end if;

  select * into v_receipt from public.dgi_receipts
   where user_id = new.user_id and cufe = split_part(new.external_ref, ':', 2);
  if v_receipt.id is null then
    return new;
  end if;

  if v_receipt.cashback_status = 'acreditado' then
    return new;
  end if;
  v_review := public.user_has_open_review(new.user_id);
  if v_receipt.cashback_status is null then
    if not v_review and public.receipt_income_backed(v_receipt.id) then
      update public.dgi_receipts set cashback_status = 'acreditado' where id = v_receipt.id;
      return new;
    end if;
    update public.dgi_receipts set cashback_status = 'sin_ingreso' where id = v_receipt.id;
  end if;

  new.status := 'pendiente';
  new.metadata := coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object('retenido', case when v_review then 'revision' else 'sin_ingreso' end);
  return new;
end $$;

-- El job diario no libera ni vence nada de quien está en revisión.
create or replace function public.release_income_held_cashback()
returns table (user_id uuid, released_cents integer, receipts integer)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_receipt record;
  v_row record;
begin
  create temp table if not exists _released (user_id uuid, cents integer) on commit drop;
  truncate _released;

  for v_receipt in
    select r.* from public.dgi_receipts r
    where r.cashback_status = 'sin_ingreso'
    order by coalesce(r.authorized_at, r.scanned_at)
  loop
    continue when public.user_has_open_review(v_receipt.user_id);

    if coalesce(v_receipt.authorized_at, v_receipt.scanned_at) < now() - interval '45 days' then
      update public.dgi_receipts set cashback_status = 'vencido' where id = v_receipt.id;
      for v_row in
        select l.* from public.points_ledger l
        where l.user_id = v_receipt.user_id and l.status = 'pendiente'
          and l.external_ref in ('factura:' || v_receipt.cufe, 'factura:' || v_receipt.cufe || ':tarjeta')
      loop
        insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
        values (v_row.user_id, v_row.source, v_row.external_ref || ':vencido', -v_row.points, 'pendiente',
                jsonb_build_object('motivo', 'sin ingresos que respalden la compra en 45 dias'))
        on conflict (source, external_ref) do nothing;
      end loop;
      continue;
    end if;

    continue when not public.receipt_income_backed(v_receipt.id);

    update public.dgi_receipts set cashback_status = 'acreditado' where id = v_receipt.id;
    for v_row in
      select l.* from public.points_ledger l
      where l.user_id = v_receipt.user_id and l.status = 'pendiente'
        and l.external_ref in ('factura:' || v_receipt.cufe, 'factura:' || v_receipt.cufe || ':tarjeta')
    loop
      insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
      values (v_row.user_id, v_row.source, v_row.external_ref || ':liberado', -v_row.points, 'pendiente',
              jsonb_build_object('motivo', 'respaldado por ingresos'))
      on conflict (source, external_ref) do nothing;
      if found then
        insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
        values (v_row.user_id, v_row.source, v_row.external_ref || ':respaldado', v_row.points, 'confirmado',
                v_row.occurred_at, jsonb_build_object('motivo', 'respaldado por ingresos'))
        on conflict (source, external_ref) do nothing;
        insert into _released values (v_row.user_id, v_row.points);
      end if;
    end loop;
  end loop;

  return query
    select x.user_id, sum(x.cents)::integer, count(*)::integer from _released x group by x.user_id;
end $$;
revoke execute on function public.release_income_held_cashback() from public, anon, authenticated;

-- Panel: aprobar (el job libera lo que respalden los ingresos) o anular
-- (el cashback retenido de esa persona se anula).
create or replace function public.resolve_cashback_review(p_review_id uuid, p_approve boolean, p_note text default null)
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_review public.cashback_reviews;
  v_receipt record;
  v_row record;
  v_count integer := 0;
begin
  select * into v_review from public.cashback_reviews where id = p_review_id and status = 'abierta' for update;
  if v_review.id is null then
    return 0;
  end if;
  update public.cashback_reviews
     set status = case when p_approve then 'aprobada' else 'anulada' end,
         note = p_note, resolved_at = now()
   where id = p_review_id;
  if p_approve then
    return 0;
  end if;
  for v_receipt in
    select r.* from public.dgi_receipts r where r.user_id = v_review.user_id and r.cashback_status = 'sin_ingreso'
  loop
    update public.dgi_receipts set cashback_status = 'vencido' where id = v_receipt.id;
    for v_row in
      select l.* from public.points_ledger l
      where l.user_id = v_receipt.user_id and l.status = 'pendiente'
        and l.external_ref in ('factura:' || v_receipt.cufe, 'factura:' || v_receipt.cufe || ':tarjeta')
    loop
      insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
      values (v_row.user_id, v_row.source, v_row.external_ref || ':anulado', -v_row.points, 'pendiente',
              jsonb_build_object('motivo', 'anulado en revision de cashback'))
      on conflict (source, external_ref) do nothing;
    end loop;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke execute on function public.resolve_cashback_review(uuid, boolean, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- señales
-- Ingresos: inusual (más del doble de su promedio), a la medida de lo que
-- faltaba para liberar cashback retenido, o editado/borrado después de
-- liberar cashback.
create or replace function public.transactions_income_review_signals()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_avg numeric;
  v_months integer;
  v_held numeric;
begin
  if tg_op in ('INSERT', 'UPDATE') and new.movement_type = 'ingreso' and new.amount > 0 then
    -- Promedio mensual de los 3 meses anteriores (solo meses con ingresos).
    select coalesce(sum(t.amount), 0), count(distinct date_trunc('month', t.occurred_at))
      into v_avg, v_months
      from public.transactions t
     where t.user_id = v_user and t.movement_type = 'ingreso' and t.amount > 0 and t.id <> new.id
       and t.occurred_at >= date_trunc('month', now()) - interval '3 months'
       and t.occurred_at < date_trunc('month', now());
    if v_months > 0 then
      v_avg := v_avg / v_months;
      if new.amount >= 1000 and new.amount > 2 * v_avg then
        perform public.open_cashback_review(v_user, 'ingreso_inusual',
          jsonb_build_object('transaction_id', new.id, 'amount', new.amount, 'monthly_average', round(v_avg, 2)));
      end if;
    end if;

    -- Cashback retenido por falta de ingresos y un ingreso que justo lo cubre.
    select coalesce(sum(r.confirmed_amount), 0) into v_held
      from public.dgi_receipts r
     where r.user_id = v_user and r.cashback_status = 'sin_ingreso';
    if v_held >= 200 and new.amount between v_held * 0.9 and v_held * 1.15 then
      perform public.open_cashback_review(v_user, 'ingreso_a_la_medida',
        jsonb_build_object('transaction_id', new.id, 'amount', new.amount, 'held_purchases', v_held));
    end if;
  end if;

  if (tg_op = 'DELETE' and old.movement_type = 'ingreso')
     or (tg_op = 'UPDATE' and old.movement_type = 'ingreso' and (new.movement_type <> 'ingreso' or new.amount < old.amount)) then
    if exists (
      select 1 from public.points_ledger l
       where l.user_id = v_user and l.status = 'confirmado' and l.external_ref like 'factura:%:respaldado'
         and l.created_at >= now() - interval '30 days'
    ) then
      perform public.open_cashback_review(v_user, 'ingreso_editado',
        jsonb_build_object('transaction_id', old.id, 'old_amount', old.amount,
                           'new_amount', case when tg_op = 'DELETE' then null else new.amount end));
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists transactions_income_review_signals on public.transactions;
create trigger transactions_income_review_signals
  after insert or update or delete on public.transactions
  for each row execute function public.transactions_income_review_signals();

-- Facturas: muchas de comercios distintos en pocas horas.
create or replace function public.dgi_receipts_review_signals()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_count integer;
  v_merchants integer;
begin
  select count(*), count(distinct r.ruc) into v_count, v_merchants
    from public.dgi_receipts r
   where r.user_id = new.user_id and r.scanned_at >= now() - interval '3 hours';
  if v_count >= 8 and v_merchants >= 6 then
    perform public.open_cashback_review(new.user_id, 'muchas_facturas',
      jsonb_build_object('receipts_3h', v_count, 'merchants_3h', v_merchants));
  end if;
  return new;
end $$;

drop trigger if exists dgi_receipts_review_signals on public.dgi_receipts;
create trigger dgi_receipts_review_signals
  after insert on public.dgi_receipts
  for each row execute function public.dgi_receipts_review_signals();

-- Teléfono repetido en otra cuenta.
create or replace function public.profiles_phone_review_signal()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.phone is not null and length(regexp_replace(new.phone, '\D', '', 'g')) >= 7
     and (tg_op = 'INSERT' or new.phone is distinct from old.phone)
     and exists (
       select 1 from public.profiles p
        where p.id <> new.id
          and regexp_replace(p.phone, '\D', '', 'g') = regexp_replace(new.phone, '\D', '', 'g')
     ) then
    perform public.open_cashback_review(new.id, 'telefono_repetido', jsonb_build_object('phone_tail', right(new.phone, 4)));
  end if;
  return new;
end $$;

drop trigger if exists profiles_phone_review_signal on public.profiles;
create trigger profiles_phone_review_signal
  after insert or update of phone on public.profiles
  for each row execute function public.profiles_phone_review_signal();

-- ---------------------------------------------------------------- dispositivos
create table if not exists public.user_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id text not null check (length(device_id) between 16 and 80),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, device_id)
);
create index if not exists user_devices_device_idx on public.user_devices (device_id);
alter table public.user_devices enable row level security;

-- La app lo llama al entrar con el id de su llavero (sobrevive a
-- reinstalar). Más de 2 cuentas en el mismo iPhone abren revisión.
create or replace function public.register_device(p_device_id text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_accounts integer;
begin
  if v_user is null or p_device_id is null or length(p_device_id) not between 16 and 80 then
    return;
  end if;
  insert into public.user_devices (user_id, device_id) values (v_user, p_device_id)
  on conflict (user_id, device_id) do update set last_seen = now();
  select count(distinct user_id) into v_accounts from public.user_devices where device_id = p_device_id;
  if v_accounts > 2 then
    perform public.open_cashback_review(v_user, 'dispositivo_compartido', jsonb_build_object('accounts_on_device', v_accounts));
  end if;
end $$;
revoke execute on function public.register_device(text) from public, anon;
grant execute on function public.register_device(text) to authenticated;

-- ---------------------------------------------------------------- verificación
create table if not exists public.income_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pendiente' check (status in ('pendiente', 'aprobada', 'rechazada')),
  document_kind text not null check (document_kind in ('talonario', 'carta_trabajo', 'css', 'estado_cuenta', 'declaracion_renta', 'otro')),
  document_path text,
  ai_name text,
  ai_monthly_income numeric(14, 2),
  ai_summary text,
  approved_amount numeric(14, 2),
  note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists income_verifications_status_idx on public.income_verifications (status, created_at desc);
alter table public.income_verifications enable row level security;
create policy "income_verifications: ver las propias" on public.income_verifications
  for select to authenticated using (user_id = auth.uid());

-- Bucket privado: cada persona solo sube y ve lo suyo (carpeta = su id).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('income-docs', 'income-docs', false, 10485760,
        array['image/jpeg', 'image/png', 'image/heic', 'application/pdf'])
on conflict (id) do nothing;

create policy "income-docs: subir lo propio" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'income-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "income-docs: ver lo propio" on storage.objects
  for select to authenticated
  using (bucket_id = 'income-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- La app registra la solicitud después de subir el documento.
create or replace function public.submit_income_verification(p_path text, p_kind text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Sin sesión';
  end if;
  if split_part(p_path, '/', 1) <> v_user::text then
    raise exception 'Documento no válido';
  end if;
  if exists (select 1 from public.income_verifications where user_id = v_user and status = 'pendiente') then
    raise exception 'Ya tienes una verificación en revisión.';
  end if;
  insert into public.income_verifications (user_id, document_kind, document_path)
  values (v_user, p_kind, p_path) returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.submit_income_verification(text, text) from public, anon;
grant execute on function public.submit_income_verification(text, text) to authenticated;

-- Lo que la app muestra: tope, ingreso verificado, ingresos del mes,
-- solicitud en curso y si hay una revisión abierta.
create or replace function public.my_income_status()
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with p as (select country, verified_income, verified_income_until from public.profiles where id = auth.uid()),
  last_request as (
    select status, created_at, note from public.income_verifications
     where user_id = auth.uid() order by created_at desc limit 1
  )
  select jsonb_build_object(
    'cap', coalesce(((select value from public.app_config where key = 'unverified_income_cap') ->> coalesce((select country from p), 'PA'))::numeric, 3000),
    'verified_income', (select verified_income from p),
    'verified_until', (select verified_income_until from p),
    'income_30d', (select coalesce(sum(t.amount), 0) from public.transactions t
                    where t.user_id = auth.uid() and t.movement_type = 'ingreso' and t.amount > 0
                      and t.occurred_at >= now() - interval '30 days'),
    'request_status', (select status from last_request),
    'request_note', (select note from last_request),
    'in_review', public.user_has_open_review(auth.uid())
  )
$$;
revoke execute on function public.my_income_status() from public, anon;
grant execute on function public.my_income_status() to authenticated;
