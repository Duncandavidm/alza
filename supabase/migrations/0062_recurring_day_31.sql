-- Dia de pago 1-31 (antes 1-28). "30" o "31" en un mes mas corto cuenta
-- como el ultimo dia del mes (la app y los recordatorios ya lo manejan asi).
-- Muchas personas cobran el 15 y el 30: pedirles "pon 28" confundia.
alter table public.recurring_transactions
  drop constraint if exists recurring_transactions_day_of_month_check;
alter table public.recurring_transactions
  add constraint recurring_transactions_day_of_month_check
  check (day_of_month between 1 and 31);
