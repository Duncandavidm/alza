-- Tipos de movimiento claramente diferenciados (mejora del "cuaderno del dia").
alter table public.transactions
  add column movement_type text not null default 'gasto'
    check (movement_type in ('ingreso', 'gasto', 'pago_proveedor', 'inversion', 'transferencia'));

-- Backfill de filas existentes usando el signo de amount como se hacia antes.
update public.transactions
set movement_type = case when amount >= 0 then 'ingreso' else 'gasto' end;
