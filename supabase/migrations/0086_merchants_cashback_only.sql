-- 0086: los puntos ya no se usan (desde 1.0.3). Los comercios que quedaron
-- con moneda "puntos" pasan a cashback. Sus productos conservan el valor
-- guardado (centavos: 800 = US$8.00). Ya aplicado en produccion el 25 nov 2026
-- (MaDay; no tenia canjes en puntos).
update public.partner_merchants set reward_currency = 'cashback' where reward_currency = 'puntos';
alter table public.partner_merchants alter column reward_currency set default 'cashback';
