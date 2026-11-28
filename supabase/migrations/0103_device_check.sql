-- 1.1.0: DeviceCheck de Apple.
--
-- El identificador del llavero (0100) se pierde si alguien borra el iPhone
-- de fábrica. DeviceCheck guarda en Apple dos bits por iPhone que
-- sobreviven a eso. MonAvi los usa así:
--   bit0 = este iPhone ya tuvo una cuenta de MonAvi.
--   bit1 = una cuenta de este iPhone tuvo cashback anulado en una revisión.
-- La Edge Function device-check los lee con un token que genera la app,
-- llama a device_check_record y escribe en Apple lo que esta función
-- devuelve. Apple no recibe nada de la persona: solo esos dos bits.
--
-- Revisiones nuevas:
--   dispositivo_marcado    el iPhone tiene bit1 (cuenta anulada antes).
--   dispositivo_reiniciado el iPhone ya tuvo una cuenta (bit0) pero llega
--                          con un identificador nuevo (lo borraron), la
--                          cuenta es nueva (menos de 30 días), nunca se usó
--                          en otro iPhone y Apple marcó el bit hace menos
--                          de 6 meses (un iPhone de segunda mano viejo no
--                          salta). El equipo aprueba los casos legítimos.

alter table public.cashback_reviews drop constraint if exists cashback_reviews_reason_check;
alter table public.cashback_reviews add constraint cashback_reviews_reason_check check (reason in (
  'ingreso_inusual', 'ingreso_a_la_medida', 'ingreso_editado', 'muchas_facturas',
  'dispositivo_compartido', 'telefono_repetido', 'apple_id_compartido',
  'dispositivo_reiniciado', 'dispositivo_marcado', 'manual'));

alter table public.user_devices
  add column if not exists dc_bit0 boolean,
  add column if not exists dc_bit1 boolean,
  add column if not exists dc_last_update text,
  add column if not exists dc_checked_at timestamptz;

create or replace function public.device_check_record(
  p_user uuid,
  p_device_id text,
  p_bit0 boolean,
  p_bit1 boolean,
  p_last_update text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_seen_before boolean;
  v_account_known boolean;
  v_account_new boolean;
  v_recent boolean;
  v_flag boolean;
begin
  if p_user is null or p_device_id is null or length(p_device_id) not between 16 and 80 then
    raise exception 'Datos no válidos';
  end if;

  -- ¿Ya revisamos este identificador antes (en cualquier cuenta)?
  select exists (
    select 1 from public.user_devices where device_id = p_device_id and dc_checked_at is not null
  ) into v_seen_before;

  -- ¿La cuenta ya se usaba en otro identificador? (borró su propio iPhone)
  select exists (
    select 1 from public.user_devices
     where user_id = p_user and device_id <> p_device_id and first_seen < now() - interval '1 day'
  ) into v_account_known;

  select coalesce((select created_at > now() - interval '30 days' from auth.users where id = p_user), false)
    into v_account_new;

  v_recent := p_last_update is not null
    and p_last_update >= to_char(now() - interval '6 months', 'YYYY-MM');

  insert into public.user_devices (user_id, device_id) values (p_user, p_device_id)
  on conflict (user_id, device_id) do update set last_seen = now();

  if coalesce(p_bit1, false) then
    perform public.open_cashback_review(p_user, 'dispositivo_marcado',
      jsonb_build_object('last_update', p_last_update));
  elsif coalesce(p_bit0, false) and not v_seen_before and not v_account_known and v_account_new and v_recent then
    perform public.open_cashback_review(p_user, 'dispositivo_reiniciado',
      jsonb_build_object('last_update', p_last_update));
  end if;

  -- bit1: alguna cuenta vista en este identificador tuvo cashback anulado.
  select coalesce(p_bit1, false) or exists (
    select 1 from public.cashback_reviews r
     where r.status = 'anulada'
       and r.user_id in (select user_id from public.user_devices where device_id = p_device_id)
  ) into v_flag;

  update public.user_devices
     set dc_bit0 = true,
         dc_bit1 = v_flag,
         dc_last_update = p_last_update,
         dc_checked_at = now()
   where user_id = p_user and device_id = p_device_id;

  return jsonb_build_object('bit0', true, 'bit1', v_flag);
end;
$$;

revoke execute on function public.device_check_record(uuid, text, boolean, boolean, text) from public, anon, authenticated;
grant execute on function public.device_check_record(uuid, text, boolean, boolean, text) to service_role;
