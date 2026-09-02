-- Cover every optional Money foreign key used by owner-scoped joins and deletes.
create index if not exists money_bills_user_category_idx
  on public.money_bills(user_id, category_id)
  where category_id is not null;

create index if not exists money_contributions_user_transaction_idx
  on public.money_savings_contributions(user_id, transaction_id)
  where transaction_id is not null;

create index if not exists money_transactions_user_income_source_idx
  on public.money_transactions(user_id, income_source_id)
  where income_source_id is not null;

create index if not exists money_transactions_user_paycheck_idx
  on public.money_transactions(user_id, paycheck_id)
  where paycheck_id is not null;

create index if not exists money_transactions_user_bill_idx
  on public.money_transactions(user_id, bill_id)
  where bill_id is not null;
