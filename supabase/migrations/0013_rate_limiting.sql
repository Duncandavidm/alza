-- Rate limiting para las Edge Functions de IA/terceros: sin esto,
-- cualquier usuario autenticado podria llamar generate-insights/
-- ask-finances/etc. en loop y disparar el costo de Anthropic, o
-- sobrecargar la base. Postgres hace de contador atomico (una fila por
-- usuario+funcion), las funciones llaman a check_and_increment_rate_limit
-- antes de hacer trabajo real.

create table public.edge_function_rate_limits (
  user_id uuid not null,
  function_name text not null,
  window_start timestamptz not null default now(),
  request_count int not null default 0,
  primary key (user_id, function_name)
);

-- Sin policies: anon/authenticated no tienen ningun acceso (ni select).
-- Solo la service role key (que usan las Edge Functions) puede tocar
-- esta tabla, via la funcion de abajo.
alter table public.edge_function_rate_limits enable row level security;

create function public.check_and_increment_rate_limit(
  p_user_id uuid,
  p_function_name text,
  p_max_requests int,
  p_window_seconds int
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_now timestamptz := now();
begin
  select * into v_row
    from public.edge_function_rate_limits
    where user_id = p_user_id and function_name = p_function_name
    for update;

  if not found then
    insert into public.edge_function_rate_limits (user_id, function_name, window_start, request_count)
    values (p_user_id, p_function_name, v_now, 1);
    return true;
  end if;

  if v_now - v_row.window_start > make_interval(secs => p_window_seconds) then
    update public.edge_function_rate_limits
      set window_start = v_now, request_count = 1
      where user_id = p_user_id and function_name = p_function_name;
    return true;
  end if;

  if v_row.request_count >= p_max_requests then
    return false;
  end if;

  update public.edge_function_rate_limits
    set request_count = request_count + 1
    where user_id = p_user_id and function_name = p_function_name;
  return true;
end;
$$;

-- Solo la service role puede ejecutarla (las Edge Functions), no
-- anon/authenticated directo.
revoke execute on function public.check_and_increment_rate_limit(uuid, text, int, int) from public;
revoke execute on function public.check_and_increment_rate_limit(uuid, text, int, int) from anon;
revoke execute on function public.check_and_increment_rate_limit(uuid, text, int, int) from authenticated;
