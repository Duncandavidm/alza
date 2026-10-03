-- RLS en profiles/family_groups/family_members solo deja ver la fila
-- propia o el grupo al que uno pertenece/es dueno — no alcanza para armar
-- la pantalla "Mi familia" (nombre del dueno + nombres de los miembros) con
-- selects directos desde el cliente. Esta RPC si puede, via security
-- definer, pero solo devuelve datos del UNICO grupo al que el usuario que
-- llama pertenece (como dueno o como miembro) — nunca el de otro grupo.
create or replace function public.get_my_family_group()
returns table (
  group_id uuid,
  invite_code text,
  owner_id uuid,
  owner_full_name text,
  is_owner boolean,
  member_id uuid,
  member_full_name text,
  member_joined_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_group_id uuid;
begin
  select id into v_group_id from public.family_groups where owner_id = auth.uid();

  if v_group_id is null then
    select fg.id into v_group_id
    from public.family_members fm
    join public.family_groups fg on fg.id = fm.group_id
    where fm.member_id = auth.uid();
  end if;

  if v_group_id is null then
    return;
  end if;

  return query
  select g.id, g.invite_code, g.owner_id, po.full_name, (g.owner_id = auth.uid()),
         fm.member_id, p.full_name, fm.joined_at
  from public.family_groups g
  left join public.profiles po on po.id = g.owner_id
  left join public.family_members fm on fm.group_id = g.id
  left join public.profiles p on p.id = fm.member_id
  where g.id = v_group_id;
end;
$$;

grant execute on function public.get_my_family_group() to authenticated;
revoke execute on function public.get_my_family_group() from public;
revoke execute on function public.get_my_family_group() from anon;
