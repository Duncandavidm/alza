-- Las funciones del plan Familia en la base seguian con los Product ID del
-- nombre anterior de la app (app.alza.sub.pro.family*), pero la app vende
-- app.monavi.sub.pro.family*. Sin esto, quien compra Familia nunca recibe
-- su codigo y los invitados nunca heredan el acceso.
do $$
declare def text;
begin
  def := pg_get_functiondef('public.ensure_family_group()'::regprocedure);
  execute replace(def, 'app.alza.sub.pro.family', 'app.monavi.sub.pro.family');
  def := pg_get_functiondef('public.get_entitlement_status()'::regprocedure);
  execute replace(def, 'app.alza.sub.pro.family', 'app.monavi.sub.pro.family');
end $$;

-- Grupos que ya debieron existir para dueños con Familia activo.
insert into public.family_groups (owner_id, invite_code)
select s.user_id, public.generate_family_invite_code()
from public.subscriptions s
where s.status in ('active', 'in_grace_period')
  and s.product_id in ('app.monavi.sub.pro.family', 'app.monavi.sub.pro.family.annual')
on conflict (owner_id) do nothing;
