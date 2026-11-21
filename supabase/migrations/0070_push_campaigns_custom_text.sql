-- Aviso de un comercio (merchant_id): si custom_text es false, el titulo y
-- el mensaje se arman para cada persona (merchant_push_for_users) y lo
-- guardado en title/body es solo la referencia del panel.
alter table public.push_campaigns add column if not exists custom_text boolean not null default false;
