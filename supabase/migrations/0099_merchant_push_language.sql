-- 0099: aviso de comercio nuevo en el idioma de cada persona (1.1.0).
create or replace function public.merchant_push_for_users(p_merchant_id uuid, p_user_ids uuid[])
returns table(user_id uuid, title text, body text, image_url text)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with m as (select * from public.partner_merchants where id = p_merchant_id),
  benefit as (
    select ri.name from public.reward_items ri, m
    where ri.merchant_id = m.id and ri.status = 'active' and ri.free_benefit
    order by ri.sort_order, ri.created_at limit 1
  ),
  product as (
    select ri.name, ri.points_cost from public.reward_items ri, m
    where ri.merchant_id = m.id and ri.status = 'active' and not ri.free_benefit and ri.audience = 'catalogo'
    order by ri.points_cost limit 1
  ),
  people as (
    select u as uid,
           public.reward_balance(u, 'cashback') as balance,
           coalesce((select pr.language from public.profiles pr where pr.id = u), 'es') = 'en' as en
    from unnest(p_user_ids) u
  )
  select p.uid,
         case when (select name from benefit) is not null
              then case when p.en then 'You have ' || (select name from benefit) || ' at ' || m.name || ' 🎉'
                        else 'Tienes ' || (select name from benefit) || ' en ' || m.name || ' 🎉' end
              else case when p.en then m.name || ' is now on MonAvi 🎉'
                        else m.name || ' ya está en MonAvi 🎉' end end,
         concat_ws(' ',
           case when (select name from benefit) is not null
                then case when p.en then 'Because you use MonAvi. Scan your receipt and earn cashback too.'
                          else 'Por ser de MonAvi. Escanea tu factura fiscal y gana cashback también.' end end,
           case when (select name from product) is null then null
                when p.balance >= (select points_cost from product)
                then case when p.en then 'You already have enough cashback for ' || (select name from product) || '! Claim it in the app.'
                          else '¡Ya te alcanza para ' || (select name from product) || ' con tu cashback! Reclámalo en la app.' end
                else case when p.en
                          then 'You need $' || trim(to_char(((select points_cost from product) - p.balance) / 100.0, 'FM999990.00'))
                               || ' more cashback for ' || (select name from product) || '.'
                          else 'Te faltan $' || trim(to_char(((select points_cost from product) - p.balance) / 100.0, 'FM999990.00'))
                               || ' de cashback para ' || (select name from product) || '.' end end),
         m.logo_url
  from people p, m;
$function$;
