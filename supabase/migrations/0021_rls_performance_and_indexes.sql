-- Dos hallazgos del advisor de performance/seguridad de Supabase, de cara
-- a escalar:
--
-- 1) Las 22 RLS policies de la app llaman auth.uid() directo en el
--    using/with check. Postgres puede volver a evaluar esa llamada por
--    cada fila en vez de una sola vez por query — con tablas chicas no se
--    nota, pero con mas usuarios y mas filas en transactions/invoices/etc.
--    degrada la latencia de cada query. El fix recomendado por Supabase es
--    envolverla en (select auth.uid()) para que el planner la trate como
--    un InitPlan evaluado una sola vez.
--    https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
--
-- 2) De paso, family_groups_select tenia un bug real: el EXISTS comparaba
--    "fm.group_id = fm.id" en vez de "fm.group_id = family_groups.id".
--    family_members tambien tiene una columna "id", asi que Postgres
--    resolvia la referencia ambigua contra la tabla interna (fm) en vez
--    de la externa (family_groups) — la condicion nunca era cierta, asi
--    que un miembro (no dueno) nunca podia ver su family_groups por esta
--    policy. No se habia notado porque el RPC get_my_family_group()
--    (security definer) no pasa por aqui, pero es una trampa si algo
--    llega a leer la tabla directo.

alter policy "accounts_all_own" on public.accounts
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "ai_insights_select_own" on public.ai_insights
  using ((select auth.uid()) = user_id);

alter policy "ai_insights_update_own" on public.ai_insights
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "app_diagnostics_insert_own" on public.app_diagnostics
  with check ((select auth.uid()) = user_id);

alter policy "bills_all_own" on public.bills
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "budgets_all_own" on public.budgets
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "business_settings_all_own" on public.business_settings
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "debts_all_own" on public.debts
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "family_groups_select" on public.family_groups
  using (
    (select auth.uid()) = owner_id
    or exists (
      select 1 from public.family_members fm
      where fm.group_id = family_groups.id and fm.member_id = (select auth.uid())
    )
  );

alter policy "family_members_delete" on public.family_members
  using (
    (select auth.uid()) = member_id
    or exists (
      select 1 from public.family_groups fg
      where fg.id = family_members.group_id and fg.owner_id = (select auth.uid())
    )
  );

alter policy "family_members_select" on public.family_members
  using (
    (select auth.uid()) = member_id
    or exists (
      select 1 from public.family_groups fg
      where fg.id = family_members.group_id and fg.owner_id = (select auth.uid())
    )
  );

alter policy "feedback_suggestions_all_own" on public.feedback_suggestions
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "invoice_items_all_own" on public.invoice_items
  using (
    exists (
      select 1 from public.invoices i
      where i.id = invoice_items.invoice_id and i.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.invoices i
      where i.id = invoice_items.invoice_id and i.user_id = (select auth.uid())
    )
  );

alter policy "invoices_all_own" on public.invoices
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "payment_receipts_all_own" on public.payment_receipts
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "products_all_own" on public.products
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "profiles_select_own" on public.profiles
  using ((select auth.uid()) = id);

alter policy "profiles_update_own" on public.profiles
  using ((select auth.uid()) = id);

alter policy "recurring_transactions_all_own" on public.recurring_transactions
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "savings_goals_all_own" on public.savings_goals
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "subscriptions_select_own" on public.subscriptions
  using ((select auth.uid()) = user_id);

alter policy "transactions_all_own" on public.transactions
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Foreign keys sin indice de cobertura — sin esto, cada join o delete en
-- cascada contra la tabla referenciada hace un seq scan que se pone mas
-- lento a medida que crece.
create index if not exists app_diagnostics_user_id_idx on public.app_diagnostics (user_id);
create index if not exists bills_account_id_idx on public.bills (account_id);
create index if not exists bills_recurring_transaction_id_idx on public.bills (recurring_transaction_id);
create index if not exists family_members_group_id_idx on public.family_members (group_id);
create index if not exists invoice_items_product_id_idx on public.invoice_items (product_id);
create index if not exists invoices_account_id_idx on public.invoices (account_id);
create index if not exists payment_receipts_user_id_idx on public.payment_receipts (user_id);
create index if not exists recurring_transactions_account_id_idx on public.recurring_transactions (account_id);
create index if not exists savings_goals_account_id_idx on public.savings_goals (account_id);
