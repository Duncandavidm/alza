-- Validacion de datos en la base (no solo en la app) y limite de escritura
-- por usuario. La app escribe directo en estas tablas via la API de
-- Supabase; RLS decide QUIEN puede escribir, estas reglas deciden QUE.
--
-- 1) CHECKs de largo de texto, rangos de montos y fechas. Se agregan
--    NOT VALID (aplican a toda fila nueva o editada) y luego se intenta
--    VALIDATE para las filas existentes; si alguna fila vieja no cumple,
--    la regla igual queda activa para lo nuevo.
-- 2) Limite de inserciones por usuario y por minuto en las tablas que la
--    app escribe (frena scripts que intenten llenar la base).

create or replace function public._add_check(p_table text, p_name text, p_expr text)
returns void language plpgsql as $$
begin
  if not exists (select 1 from pg_constraint where conname = p_name) then
    execute format('alter table public.%I add constraint %I check (%s) not valid', p_table, p_name, p_expr);
  end if;
  begin
    execute format('alter table public.%I validate constraint %I', p_table, p_name);
  exception when others then
    raise notice 'Filas existentes no cumplen %, queda NOT VALID', p_name;
  end;
end $$;

do $$
declare
  money text := 'between -100000000 and 100000000';
begin
  -- transactions
  perform public._add_check('transactions','chk_tx_amount', 'amount '||money);
  perform public._add_check('transactions','chk_tx_text', 'char_length(coalesce(category,'''')) <= 60 and char_length(coalesce(description,'''')) <= 300 and char_length(coalesce(original_currency,'''')) <= 5');
  perform public._add_check('transactions','chk_tx_orig_amount', 'original_amount is null or original_amount '||money);
  perform public._add_check('transactions','chk_tx_dates', 'occurred_at >= ''2000-01-01'' and occurred_at < ''2100-01-01''');
  perform public._add_check('transactions','chk_tx_tags', 'tags is null or cardinality(tags) <= 20');
  -- accounts
  perform public._add_check('accounts','chk_acc_text', 'char_length(coalesce(name,'''')) <= 80 and char_length(coalesce(currency,'''')) <= 5');
  perform public._add_check('accounts','chk_acc_balance', 'balance is null or balance '||money);
  -- bills
  perform public._add_check('bills','chk_bills_text', 'char_length(coalesce(name,'''')) <= 120 and char_length(coalesce(category,'''')) <= 60');
  perform public._add_check('bills','chk_bills_amount', 'amount <= 100000000');
  -- budgets
  perform public._add_check('budgets','chk_budgets_text', 'char_length(coalesce(category,'''')) <= 60 and char_length(coalesce(color,'''')) <= 20');
  perform public._add_check('budgets','chk_budgets_amount', 'limit_amount <= 100000000');
  -- business_settings
  perform public._add_check('business_settings','chk_biz_text', 'char_length(coalesce(business_name,'''')) <= 120 and char_length(coalesce(address,'''')) <= 300 and char_length(coalesce(phone,'''')) <= 40 and char_length(coalesce(tax_id,'''')) <= 40 and char_length(coalesce(brand_color,'''')) <= 20 and char_length(coalesce(logo_path,'''')) <= 300');
  -- debts
  perform public._add_check('debts','chk_debts_text', 'char_length(coalesce(creditor,'''')) <= 120');
  perform public._add_check('debts','chk_debts_nums', '(balance is null or balance '||money||') and (credit_limit is null or credit_limit '||money||') and (minimum_payment is null or minimum_payment '||money||') and (interest_rate_monthly is null or interest_rate_monthly between 0 and 100)');
  -- device tokens
  perform public._add_check('device_push_tokens','chk_push_token', 'char_length(token) <= 200');
  -- dgi receipts
  perform public._add_check('dgi_receipts','chk_dgi_text', 'char_length(coalesce(cufe,'''')) <= 120 and char_length(coalesce(jwt,'''')) <= 4000 and char_length(coalesce(digest_value,'''')) <= 200 and char_length(coalesce(ruc,'''')) <= 40 and char_length(coalesce(merchant_name,'''')) <= 200 and char_length(coalesce(numero_documento,'''')) <= 40');
  perform public._add_check('dgi_receipts','chk_dgi_amount', 'confirmed_amount is null or confirmed_amount between 0 and 100000000');
  -- feedback
  perform public._add_check('feedback_suggestions','chk_feedback_len', 'char_length(message) <= 2000');
  -- invoices / items
  perform public._add_check('invoices','chk_inv_text', 'char_length(coalesce(number,'''')) <= 40 and char_length(coalesce(customer_name,'''')) <= 120 and char_length(coalesce(customer_contact,'''')) <= 200 and char_length(coalesce(notes,'''')) <= 2000');
  perform public._add_check('invoices','chk_inv_amounts', '(subtotal is null or subtotal '||money||') and (total is null or total '||money||')');
  perform public._add_check('invoice_items','chk_items', 'char_length(coalesce(description,'''')) <= 300 and (quantity is null or quantity between 0 and 1000000) and (unit_price is null or unit_price '||money||') and (line_total is null or line_total '||money||')');
  -- linked cards / payment receipts / products
  perform public._add_check('linked_cards','chk_cards_alias', 'char_length(coalesce(alias,'''')) <= 60');
  perform public._add_check('payment_receipts','chk_receipts', 'char_length(coalesce(receipt_number,'''')) <= 60 and (amount is null or amount '||money||')');
  perform public._add_check('products','chk_products', 'char_length(coalesce(name,'''')) <= 120 and char_length(coalesce(unit,'''')) <= 30 and (cost_price is null or cost_price '||money||') and (sale_price is null or sale_price '||money||') and (margin_percent is null or margin_percent between -100 and 100000)');
  -- profiles
  perform public._add_check('profiles','chk_profiles_text', 'char_length(coalesce(full_name,'''')) <= 100 and char_length(coalesce(occupation,'''')) <= 100 and char_length(coalesce(variable_income_notes,'''')) <= 1000');
  perform public._add_check('profiles','chk_profiles_nums', '(age is null or age between 0 and 120) and (dependents_count is null or dependents_count between 0 and 30)');
  perform public._add_check('profiles','chk_profiles_goals', '(short_term_goals is null or cardinality(short_term_goals) <= 20) and (long_term_goals is null or cardinality(long_term_goals) <= 20)');
  -- recurring / savings
  perform public._add_check('recurring_transactions','chk_rec', 'char_length(coalesce(name,'''')) <= 120 and char_length(coalesce(category,'''')) <= 60 and amount <= 100000000');
  perform public._add_check('savings_contributions','chk_contrib', 'amount '||money);
  perform public._add_check('savings_goals','chk_goals', 'char_length(coalesce(name,'''')) <= 80 and char_length(coalesce(emoji,'''')) <= 16 and target_amount <= 100000000 and current_amount <= 100000000');
  perform public._add_check('sponsored_savings_enrollments','chk_enroll', 'char_length(coalesce(external_account_ref,'''')) <= 120');
  -- diagnosticos
  perform public._add_check('app_diagnostics','chk_diag', 'pg_column_size(payload) <= 200000 and char_length(coalesce(app_version,'''')) <= 40 and char_length(coalesce(os_version,'''')) <= 80');
end $$;

drop function public._add_check(text, text, text);

-- 2) Limite de inserciones por usuario y minuto ----------------------------
create or replace function public.enforce_insert_rate_limit()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_max int := coalesce(tg_argv[0]::int, 60);
  v_count int;
begin
  -- Solo aplica a usuarios con sesion (la app). El servidor (service role,
  -- cron, triggers internos) no tiene auth.uid() y no se limita.
  if v_user is null then return new; end if;
  execute format('select count(*) from public.%I where user_id = $1 and created_at > now() - interval ''1 minute''', tg_table_name)
    into v_count using v_user;
  if v_count >= v_max then
    raise exception 'Demasiadas solicitudes. Espera un momento e intenta de nuevo.' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.enforce_insert_rate_limit() from public, anon, authenticated;

create index if not exists transactions_user_created_idx on public.transactions (user_id, created_at desc);
create index if not exists dgi_receipts_user_created_idx on public.dgi_receipts (user_id, created_at desc);

do $$
declare r record;
begin
  for r in select * from (values
    ('transactions',120),('dgi_receipts',30),('feedback_suggestions',5),('user_categories',30),
    ('savings_contributions',60),('bills',30),('app_diagnostics',30),('invoices',30),('accounts',20),
    ('budgets',30),('savings_goals',20),('recurring_transactions',30),('debts',20),('products',60),
    ('payment_receipts',60)) as v(tbl, lim)
  loop
    execute format('drop trigger if exists %I on public.%I', r.tbl||'_insert_rate_limit', r.tbl);
    execute format('create trigger %I before insert on public.%I for each row execute function public.enforce_insert_rate_limit(%s)',
      r.tbl||'_insert_rate_limit', r.tbl, r.lim);
  end loop;
end $$;
