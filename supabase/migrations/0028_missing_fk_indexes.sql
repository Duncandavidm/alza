-- El advisor de performance marco 3 foreign keys sin indice: 2 que se
-- quedaron sin cubrir en la Fase 1 (card_transactions.linked_card_id,
-- linked_cards.account_id) y una nueva de la Fase 3
-- (savings_bank_reports.goal_id).
create index card_transactions_linked_card_id_idx on public.card_transactions (linked_card_id);
create index linked_cards_account_id_idx on public.linked_cards (account_id);
create index savings_bank_reports_goal_id_idx on public.savings_bank_reports (goal_id);
