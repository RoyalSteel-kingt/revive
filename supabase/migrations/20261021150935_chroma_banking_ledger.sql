-- Chroma is account-wide banking. Hyphen retains its own detailed receipts.
begin;
lock table public.chroma_wallets, public.surplus_receipts in share row exclusive mode;
create schema if not exists revive_internal;
revoke all on schema revive_internal from public,anon,authenticated;

create table if not exists public.chroma_transactions (
 id uuid primary key default gen_random_uuid(),
 ordinal bigint generated always as identity unique,
 account_id uuid not null references public.profiles(id) on delete cascade,
 delta bigint not null,
 balance_before bigint not null check(balance_before between 0 and 1000000000000),
 balance_after bigint not null check(balance_after between 0 and 1000000000000),
 source text not null default 'account' check(source in ('account','hyphen','opening')),
 reference uuid,
 description text not null,
 kind text not null default 'movement' check(kind in ('movement','opening')),
 created_at timestamptz not null default clock_timestamp(),
 recorded_xid xid8,
 check(balance_after-balance_before=delta),
 check((kind='movement' and delta<>0) or (kind='opening' and delta=0))
);
create index if not exists chroma_transactions_account_time on public.chroma_transactions(account_id,created_at desc,id desc);
create index if not exists chroma_transactions_pending_link on public.chroma_transactions(account_id,recorded_xid,ordinal desc) where source='account' and reference is null;
create unique index if not exists chroma_transactions_receipt_unique on public.chroma_transactions(account_id,reference) where source='hyphen';
create unique index if not exists chroma_transactions_opening_unique on public.chroma_transactions(account_id) where kind='opening';
alter table public.chroma_transactions enable row level security;
revoke all on public.chroma_transactions from public,anon,authenticated,service_role;
grant select on public.chroma_transactions to authenticated,service_role;
drop policy if exists chroma_transactions_read_own on public.chroma_transactions;
create policy chroma_transactions_read_own on public.chroma_transactions for select to authenticated using ((select auth.uid())=account_id);
comment on table public.chroma_transactions is 'Chroma banking: all recorded wallet movements. Shop receipts remain in their respective shop tables. Player access is read-only.';

-- Import only actual recorded currency movements, without replaying trades.
insert into public.chroma_transactions(account_id,delta,balance_before,balance_after,source,reference,description,kind,created_at)
 select account_id,(result->>'delta')::bigint,(result->>'balance')::bigint-(result->>'delta')::bigint,
 (result->>'balance')::bigint,'hyphen',request_id,
 'Hyphen ' || case result->>'action' when 'buy' then 'purchase: ' else 'sale: ' end || coalesce(result->>'name','Item'),'movement',created_at
 from public.surplus_receipts where (result->>'delta')::bigint<>0
 on conflict(account_id,reference) where source='hyphen' do nothing;
-- Checkpoints explain existing balances without inventing an income source.
insert into public.chroma_transactions(account_id,delta,balance_before,balance_after,source,description,kind)
 select w.account_id,0,w.balance,w.balance,'opening','Balance when banking history began','opening'
 from public.chroma_wallets w where not exists(select 1 from public.chroma_transactions t where t.account_id=w.account_id and t.kind='opening')
 on conflict(account_id) where kind='opening' do nothing;

create or replace function revive_internal.capture_chroma_movement()
returns trigger language plpgsql security definer set search_path='' as $bank$
declare before_balance bigint;
begin
 if TG_OP='UPDATE' and NEW.account_id<>OLD.account_id then raise exception 'A Chroma wallet cannot change owner.'; end if;
 before_balance:=case when TG_OP='INSERT' then 0 else OLD.balance end;
 if NEW.balance=before_balance then return NEW; end if;
 insert into public.chroma_transactions(account_id,delta,balance_before,balance_after,description,recorded_xid)
 values(NEW.account_id,NEW.balance-before_balance,before_balance,NEW.balance,
 case when NEW.balance>before_balance then 'Account credit' else 'Account debit' end,pg_catalog.pg_current_xact_id());
 return NEW;
end;
$bank$;
revoke all on function revive_internal.capture_chroma_movement() from public,anon,authenticated,service_role;
drop trigger if exists capture_chroma_movement on public.chroma_wallets;
create trigger capture_chroma_movement after insert or update on public.chroma_wallets for each row execute function revive_internal.capture_chroma_movement();

-- Link the shop receipt to the movement in the SAME database transaction.
-- The existing shop's price, inventory and replay logic remains unchanged.
create or replace function revive_internal.link_hyphen_chroma_receipt()
returns trigger language plpgsql security definer set search_path='' as $bank$
declare movement_id uuid; change bigint:=(NEW.result->>'delta')::bigint;
begin
 if change=0 then return NEW; end if;
 select id into movement_id from public.chroma_transactions
 where account_id=NEW.account_id and recorded_xid=pg_catalog.pg_current_xact_id()
 and source='account' and reference is null and delta=change and balance_after=(NEW.result->>'balance')::bigint
 order by ordinal desc limit 1;
 if movement_id is null then raise exception 'Hyphen receipt has no matching Chroma movement.'; end if;
 update public.chroma_transactions set source='hyphen',reference=NEW.request_id,
 description='Hyphen ' || case NEW.result->>'action' when 'buy' then 'purchase: ' else 'sale: ' end || coalesce(NEW.result->>'name','Item')
 where id=movement_id;
 return NEW;
end;
$bank$;
revoke all on function revive_internal.link_hyphen_chroma_receipt() from public,anon,authenticated,service_role;
drop trigger if exists link_hyphen_chroma_receipt on public.surplus_receipts;
create trigger link_hyphen_chroma_receipt after insert on public.surplus_receipts for each row execute function revive_internal.link_hyphen_chroma_receipt();
notify pgrst,'reload schema';
commit;
