-- Las enseñanzas del Método MonAvi ya no se muestran como lecciones en la
-- app: solo las usa la IA (análisis y respuestas). La app no las lee.
update public.finance_teachings set show_in_app = false where show_in_app;
alter table public.finance_teachings alter column show_in_app set default false;
drop policy if exists finance_teachings_read on public.finance_teachings;
