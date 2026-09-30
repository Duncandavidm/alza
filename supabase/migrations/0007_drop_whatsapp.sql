-- Se descarta el bot de WhatsApp (no se va a usar).
drop table if exists public.whatsapp_link_codes;
alter table public.profiles drop column if exists whatsapp_number;
