-- Quitar los retos por comercio (se aplicaron con una version anterior de
-- 0083 y se descartaron: premiaban comprar mas en un comercio en vez de
-- pedir factura en lo que ya se compra). Los premios ya entregados, si los
-- hubiera, quedan en reward_redemptions como cualquier regalo.
drop function if exists public.issue_merchant_challenge_rewards();
drop function if exists public.my_merchant_challenges();
drop table if exists public.merchant_challenge_grants;
drop table if exists public.merchant_challenges;
-- El indice de facturas por RUC y fecha se queda: tambien lo usan los
-- segmentos por comercio de Notificaciones.
