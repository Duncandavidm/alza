-- Prueba gratis: la app se usa completa, pero los descuentos, bonos y
-- canjes en comercios aliados se activan solo cuando empieza el plan
-- pagado. El cashback y los puntos se siguen ganando durante la prueba.
--
-- subscriptions.is_trial lo marcan verify-apple-receipt y
-- apple-notifications cuando la transacción vigente de Apple es la oferta
-- introductoria gratuita (offerType 1, FREE_TRIAL). Al primer cobro real
-- la transacción nueva ya no es de prueba y queda en false.

alter table public.subscriptions add column if not exists is_trial boolean not null default false;

create or replace function public.subscription_in_trial(p_user uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.subscriptions
     where user_id = p_user and is_trial and status in ('active', 'in_grace_period')
  );
$$;
revoke all on function public.subscription_in_trial(uuid) from public, anon, authenticated;

-- redeem_reward y use_benefit: después de verificar el correo, se frena el
-- canje si la persona está en la prueba gratis. Se inserta en la definición
-- vigente para no reescribir esas funciones.
do $$
declare
  fn text;
  def text;
  guard constant text := E'\n  if public.subscription_in_trial(v_user) then\n    raise exception ''Los descuentos y canjes se activan cuando empiece tu plan pagado, al terminar tu prueba gratis.'' using errcode = ''P0001'';\n  end if;\n';
  anchor text;
begin
  foreach fn in array array['redeem_reward', 'use_benefit'] loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn;
    if def is null then raise exception 'No existe %', fn; end if;
    if position('subscription_in_trial' in def) > 0 then continue; end if;
    anchor := 'perform pg_advisory_xact_lock(hashtext(''redeem:'' || v_user::text));';
    if position(anchor in def) = 0 then raise exception 'No se encontró el punto de inserción en %', fn; end if;
    def := replace(def, anchor, anchor || guard);
    execute def;
  end loop;
end $$;
