-- ---------------------------------------------------------------------------
-- Plan "Familia": a diferencia de Apple Family Sharing (que solo deja
-- compartir gratis), este es un producto de suscripcion propio y mas caro
-- (app.alza.sub.pro.family / .family.annual) que le da al comprador un
-- grupo con cupo para hasta 5 invitados — cada quien con su propia cuenta
-- y datos, pero con acceso Pro heredado del dueno del grupo mientras su
-- suscripcion este activa.
--
-- family_groups: una fila por dueno (owner_id unico), creada sola por el
-- trigger ensure_family_group cuando su suscripcion pasa a un producto de
-- familia activo — nunca la crea el cliente directo.
-- family_members: hasta 5 filas por grupo, un usuario solo puede estar en
-- un grupo a la vez (member_id unico). Se unen solo via join_family_group
-- (RPC), nunca insertando directo (asi se valida el codigo y el cupo).
-- ---------------------------------------------------------------------------

create table public.family_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users (id) on delete cascade,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  member_id uuid not null unique references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now()
);

alter table public.family_groups enable row level security;
alter table public.family_members enable row level security;

-- El dueno ve su propio grupo; un miembro ve el grupo al que pertenece.
create policy "family_groups_select" on public.family_groups
  for select using (
    auth.uid() = owner_id
    or exists (
      select 1 from public.family_members fm
      where fm.group_id = id and fm.member_id = auth.uid()
    )
  );

-- Un miembro ve su propia fila; el dueno ve las filas de su grupo.
create policy "family_members_select" on public.family_members
  for select using (
    auth.uid() = member_id
    or exists (
      select 1 from public.family_groups fg
      where fg.id = group_id and fg.owner_id = auth.uid()
    )
  );

-- Salir del grupo (el propio miembro) o sacar a alguien (el dueno).
create policy "family_members_delete" on public.family_members
  for delete using (
    auth.uid() = member_id
    or exists (
      select 1 from public.family_groups fg
      where fg.id = group_id and fg.owner_id = auth.uid()
    )
  );

-- No hay policy de insert en ninguna de las dos tablas: family_groups solo
-- la crea el trigger de abajo (security definer), family_members solo la
-- llena join_family_group (security definer) — asi se valida siempre el
-- codigo de invitacion y el cupo de 5, nunca se puede insertar a mano.

create or replace function public.generate_family_invite_code()
returns text
language sql
as $$
  select upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
$$;

-- Crea el grupo familiar del dueno la primera vez que su suscripcion queda
-- activa en un producto de familia. on conflict (owner_id) do nothing: si
-- ya tenia uno (ej. se le vencio y se volvio a suscribir), lo conserva con
-- su mismo codigo de invitacion y miembros.
create or replace function public.ensure_family_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('active', 'in_grace_period')
     and new.product_id in ('app.alza.sub.pro.family', 'app.alza.sub.pro.family.annual') then
    insert into public.family_groups (owner_id, invite_code)
    values (new.user_id, public.generate_family_invite_code())
    on conflict (owner_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger subscriptions_ensure_family_group
  after insert or update on public.subscriptions
  for each row execute procedure public.ensure_family_group();

-- Un miembro (no el dueno) se une a un grupo con un codigo de invitacion.
-- Valida el codigo, que no sea su propio grupo, y el cupo de 5. Si ya
-- pertenecia a otro grupo, lo mueve a este (upsert por member_id unico).
create or replace function public.join_family_group(p_invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_owner_id uuid;
  v_member_count int;
begin
  select id, owner_id into v_group_id, v_owner_id
  from public.family_groups
  where invite_code = p_invite_code;

  if v_group_id is null then
    raise exception 'Codigo de invitacion invalido';
  end if;

  if v_owner_id = auth.uid() then
    raise exception 'No puedes unirte a tu propio grupo familiar';
  end if;

  select count(*) into v_member_count
  from public.family_members
  where group_id = v_group_id;

  if v_member_count >= 5 then
    raise exception 'Ese grupo familiar ya tiene el maximo de 5 miembros';
  end if;

  insert into public.family_members (group_id, member_id)
  values (v_group_id, auth.uid())
  on conflict (member_id) do update set group_id = excluded.group_id, joined_at = now();
end;
$$;

grant execute on function public.join_family_group(text) to authenticated;

-- Estado de suscripcion efectivo del usuario actual: su propia fila en
-- subscriptions si la tiene, o si no, la del dueno del grupo familiar al
-- que pertenece (solo si esa suscripcion del dueno sigue siendo un
-- producto de familia activo). security definer porque un miembro no
-- tiene (ni debe tener) permiso de leer directo la fila de subscriptions
-- de otro usuario (el dueno) — esta funcion es el unico lugar donde esa
-- lectura cruzada esta permitida, y solo para ese proposito puntual.
create or replace function public.get_entitlement_status()
returns table (
  status text,
  product_id text,
  expires_at timestamptz,
  via_family boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select s.status, s.product_id, s.expires_at, false
  from public.subscriptions s
  where s.user_id = auth.uid();

  if found then
    return;
  end if;

  return query
  select s.status, s.product_id, s.expires_at, true
  from public.family_members fm
  join public.family_groups fg on fg.id = fm.group_id
  join public.subscriptions s on s.user_id = fg.owner_id
  where fm.member_id = auth.uid()
    and s.product_id in ('app.alza.sub.pro.family', 'app.alza.sub.pro.family.annual');
end;
$$;

grant execute on function public.get_entitlement_status() to authenticated;
