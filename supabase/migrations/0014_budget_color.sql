-- Color personalizado por presupuesto (rediseño del dashboard: cada barra
-- de presupuesto se puede pintar de un color a elegir, como en el picker
-- de referencia). Nullable: un presupuesto sin color asignado cae a un
-- color por defecto calculado en el cliente (ver BudgetColorPalette.swift).
alter table public.budgets
  add column color text;
