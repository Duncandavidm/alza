-- Frecuencia en recurrentes (1.0.2): hasta ahora todo era mensual
-- (day_of_month). El onboarding ahora pregunta "¿cada cuanto te pagan?".
--   - monthly: como siempre, usa day_of_month.
--   - weekly:  usa weekday (1 = domingo ... 7 = sabado, igual que
--              Calendar de iOS); day_of_month queda en 1 como relleno.
--   - daily:   todos los dias; day_of_month queda en 1 como relleno.
-- Quincenal NO es una frecuencia: se guarda como dos filas mensuales (p.ej.
-- dias 15 y 28), asi funciona igual en todo lo que ya existe.
--
-- Aditivo y con default 'monthly': las versiones 1.0 / 1.0.1 de la app
-- ignoran las columnas nuevas y siguen funcionando igual.

alter table public.recurring_transactions
  add column if not exists frequency text not null default 'monthly',
  add column if not exists weekday smallint;

alter table public.recurring_transactions
  drop constraint if exists recurring_transactions_frequency_check;
alter table public.recurring_transactions
  add constraint recurring_transactions_frequency_check
  check (frequency in ('monthly', 'weekly', 'daily'));

alter table public.recurring_transactions
  drop constraint if exists recurring_transactions_weekday_check;
alter table public.recurring_transactions
  add constraint recurring_transactions_weekday_check
  check (
    (frequency = 'weekly' and weekday between 1 and 7)
    or (frequency <> 'weekly' and weekday is null)
  );
