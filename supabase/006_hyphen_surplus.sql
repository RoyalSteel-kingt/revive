-- The Revive / Hyphen Surplus. Run AFTER installed migrations 001–005.
-- Safe to rerun. No existing items, tags, starter grants, or mission functions change.
begin;
create table if not exists public.chroma_wallets (
 account_id uuid primary key references public.profiles(id) on delete cascade,
 balance bigint not null default 0 check(balance between 0 and 1000000000000)
);
create table if not exists public.surplus_offers (
 id text primary key,
 definition_id text not null references public.item_definitions(id),
 label text not null,
 condition integer not null check(condition between 1 and 100),
 price integer not null check(price>0),
 active boolean not null default true
);
create table if not exists public.surplus_sell_prices (
 definition_id text primary key references public.item_definitions(id),
 full_condition_value integer not null check(full_condition_value>0)
);
create table if not exists public.surplus_receipts (
 account_id uuid not null references public.profiles(id) on delete cascade,
 request_id uuid not null,
 request jsonb not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(account_id,request_id)
);
create index if not exists surplus_receipts_account_time on public.surplus_receipts(account_id,created_at desc);
insert into public.surplus_offers(id,definition_id,label,condition,price) values
 ('worn-flux-rifle','flux-rifle','Recovered Flux Rifle',25,60),
 ('flux-service-kit','flux-service-kit','Flux Service Kit',100,40),
 ('daybreak-broth','daybreak-recovery-broth','Daybreak Recovery Broth',100,25),
 ('good-orbit-citrus','good-orbit-citrus-drink','Good Orbit Citrus Drink',100,20)
on conflict(id) do nothing;
insert into public.surplus_sell_prices(definition_id,full_condition_value) values
 ('flux-rifle',60),('flux-service-kit',35),('daybreak-recovery-broth',25),
 ('good-orbit-citrus-drink',20),('focus-01',30),('meal-pack',25)
on conflict(definition_id) do nothing;
-- Correct only the previous default text; leave custom lore untouched.
update public.item_definitions set description='SF Field Engineering | Emitter contacts, coolant seals, and calibration shims. Use one secured kit at Hyphen Surplus to restore up to 40 condition points to a stashed Flux Rifle.'
where id='flux-service-kit' and description='SF Field Engineering | A sealed kit of emitter contacts, coolant seals, and calibration shims for Flux Rifles. Collectible supply; repair use is planned, not yet available.';
alter table public.chroma_wallets enable row level security;
alter table public.surplus_offers enable row level security;
alter table public.surplus_sell_prices enable row level security;
alter table public.surplus_receipts enable row level security;
revoke all on public.chroma_wallets,public.surplus_offers,public.surplus_sell_prices,public.surplus_receipts from public,anon,authenticated;
grant select on public.chroma_wallets,public.surplus_receipts to authenticated;
grant all on public.chroma_wallets,public.surplus_offers,public.surplus_sell_prices,public.surplus_receipts to service_role;
drop policy if exists wallet_read_self on public.chroma_wallets;
create policy wallet_read_self on public.chroma_wallets for select to authenticated using ((select auth.uid())=account_id);
drop policy if exists surplus_receipt_read_self on public.surplus_receipts;
create policy surplus_receipt_read_self on public.surplus_receipts for select to authenticated using ((select auth.uid())=account_id);

create or replace function public.get_surplus_terminal()
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); result jsonb;
begin
 if a is null then raise exception 'Sign in to open Hyphen Surplus.' using errcode='28000'; end if;
 if not exists(select 1 from public.profiles where id=a) then raise exception 'Register your contractor name first.' using errcode='22023'; end if;
 select pg_catalog.jsonb_build_object(
 'balance',coalesce((select balance from public.chroma_wallets where account_id=a),0),
 'mission_active',exists(select 1 from public.mission_runs where account_id=a and status='active'),
 'repair_points',40,
 'offers',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',o.id,'definition_id',o.definition_id,'name',o.label,'condition',o.condition,'price',o.price,'category',d.category,'manufacturer',d.manufacturer,'description',d.description) order by o.price desc,o.id) from public.surplus_offers o join public.item_definitions d on d.id=o.definition_id where o.active),'[]'::jsonb),
 'quotes',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('item_id',i.id,'value',greatest(1,(s.full_condition_value*i.condition)/100))) from public.item_instances i join public.surplus_sell_prices s on s.definition_id=i.definition_id where i.owner_id=a and i.location='stash' and i.mission_run_id is null),'[]'::jsonb),
 'receipts',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('request_id',t.request_id,'result',t.result,'created_at',t.created_at) order by t.created_at desc) from (select r.request_id,r.result,r.created_at from public.surplus_receipts r where r.account_id=a order by r.created_at desc limit 12) t),'[]'::jsonb)
 ) into result;
 return result;
end $$;

-- A transaction receipt makes retrying a lost response safe. Prices, owner, location,
-- eligibility, and balance are checked here, never trusted from browser state.
create or replace function public.surplus_trade(
 p_request_id uuid,p_action text,p_item_id uuid default null,p_offer_id text default null,
 p_kit_id uuid default null,p_expected_amount integer default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid:=auth.uid(); req jsonb; receipt public.surplus_receipts; item public.item_instances;
 kit public.item_instances; offer public.surplus_offers; bal bigint; amount integer;
 label text; result jsonb; delta integer:=0;
begin
 if a is null then raise exception 'Sign in before trading.' using errcode='28000'; end if;
 if p_request_id is null or p_action is null or p_action not in ('sell','buy','repair') or p_expected_amount is null or p_expected_amount<1 then raise exception 'Invalid trade request.' using errcode='22023'; end if;
 req:=pg_catalog.jsonb_build_object('action',p_action,'item_id',p_item_id,'offer_id',p_offer_id,'kit_id',p_kit_id,'expected_amount',p_expected_amount);
 -- Same account lock as mission reservation: a deployment and a trade cannot race.
 perform 1 from public.profiles where id=a for update;
 if not found then raise exception 'Register your contractor name first.' using errcode='22023'; end if;
 select * into receipt from public.surplus_receipts where account_id=a and request_id=p_request_id;
 if found then
  if receipt.request is distinct from req then raise exception 'This transaction ID belongs to a different request.' using errcode='22023'; end if;
  return receipt.result;
 end if;
 if exists(select 1 from public.mission_runs where account_id=a and status='active') then raise exception 'Finish your mission and wait for its save before trading.' using errcode='22023'; end if;
 insert into public.chroma_wallets(account_id) values(a) on conflict(account_id) do nothing;
 select balance into bal from public.chroma_wallets where account_id=a for update;
 if p_action='buy' then
  if p_offer_id is null or p_item_id is not null or p_kit_id is not null then raise exception 'Invalid purchase.' using errcode='22023'; end if;
  select * into offer from public.surplus_offers where id=p_offer_id and active for share;
  if not found then raise exception 'This offer is no longer available.' using errcode='22023'; end if;
  amount:=offer.price; label:=offer.label;
  if p_expected_amount<>amount then raise exception 'Price changed. Refresh and review this purchase again.' using errcode='22023'; end if;
  if bal<amount then raise exception 'Not enough Chroma. Sell secured supplies first.' using errcode='22023'; end if;
  insert into public.item_instances(owner_id,definition_id,condition,location,source)
  values(a,offer.definition_id,offer.condition,'stash','hyphen-surplus') returning * into item;
  delta:=-amount;
 elsif p_action='sell' then
  if p_item_id is null or p_offer_id is not null or p_kit_id is not null then raise exception 'Invalid sale.' using errcode='22023'; end if;
  select * into item from public.item_instances where id=p_item_id and owner_id=a for update;
  if not found or item.owner_id<>a or item.location<>'stash' or item.mission_run_id is not null then raise exception 'This item is no longer available in your stash.' using errcode='22023'; end if;
  select greatest(1,(s.full_condition_value*item.condition)/100),d.name into amount,label from public.surplus_sell_prices s join public.item_definitions d on d.id=s.definition_id where s.definition_id=item.definition_id;
  if not found then raise exception 'Hyphen does not accept this item yet.' using errcode='22023'; end if;
  if p_expected_amount<>amount then raise exception 'Sale value changed. Refresh and review the item again.' using errcode='22023'; end if;
  delete from public.item_instances where id=item.id;
  delta:=amount;
 else
  if p_item_id is null or p_kit_id is null or p_item_id=p_kit_id or p_offer_id is not null then raise exception 'Choose a rifle and a separate service kit.' using errcode='22023'; end if;
  select * into item from public.item_instances where id=p_item_id and owner_id=a for update;
  if not found or item.owner_id<>a or item.location<>'stash' or item.mission_run_id is not null or item.definition_id<>'flux-rifle' or item.condition>=100 then raise exception 'Choose a damaged Flux Rifle in your stash.' using errcode='22023'; end if;
  select * into kit from public.item_instances where id=p_kit_id and owner_id=a for update;
  if not found or kit.owner_id<>a or kit.location<>'stash' or kit.mission_run_id is not null or kit.definition_id<>'flux-service-kit' or kit.condition<=0 then raise exception 'Choose an available Flux Service Kit from your stash.' using errcode='22023'; end if;
  amount:=least(40,100-item.condition);label:='Flux Rifle';
  if p_expected_amount<>amount then raise exception 'Rifle condition changed. Refresh and review this repair again.' using errcode='22023'; end if;
  delete from public.item_instances where id=kit.id;
  update public.item_instances set condition=condition+amount where id=item.id returning * into item;
 end if;
 update public.chroma_wallets set balance=balance+delta where account_id=a returning balance into bal;
 result:=pg_catalog.jsonb_build_object('request_id',p_request_id,'action',p_action,'item_id',item.id,'name',label,'condition',item.condition,'amount',amount,'delta',delta,'balance',bal,'kit_id',p_kit_id);
 insert into public.surplus_receipts(account_id,request_id,request,result) values(a,p_request_id,req,result);
 return result;
end $$;
revoke all on function public.get_surplus_terminal() from public,anon,authenticated;
revoke all on function public.surplus_trade(uuid,text,uuid,text,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_surplus_terminal() to authenticated;
grant execute on function public.surplus_trade(uuid,text,uuid,text,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
