-- First self-purchase: discovered shop -> Chroma payment -> own-home delivery.
-- Local SQL file avoids the CLI analytics request rejected earlier in this task.
begin;
create table if not exists public.shops (
 shop_id text primary key,
 name text not null,
 website_enabled boolean not null default true
);
insert into public.shops(shop_id,name) values('hyphen','Hyphen Surplus') on conflict(shop_id) do nothing;
create table if not exists public.shop_visits (
 account_id uuid not null references public.profiles(id) on delete cascade,
 shop_id text not null references public.shops(shop_id),
 visited_at timestamptz not null default now(),
 primary key(account_id,shop_id)
);
create index if not exists shop_visits_shop on public.shop_visits(shop_id);
create table if not exists public.purchase_orders (
 id uuid primary key default gen_random_uuid(),
 account_id uuid not null references public.profiles(id) on delete cascade,
 request_id uuid not null,
 shop_id text not null references public.shops(shop_id),
 offer_id text not null references public.surplus_offers(id),
 definition_id text not null references public.item_definitions(id),
 item_id uuid not null unique default gen_random_uuid(),
 item_name text not null,
 condition integer not null check(condition between 1 and 100),
 amount integer not null check(amount>0),
 created_at timestamptz not null default clock_timestamp(),
 unique(account_id,request_id)
);
create index if not exists purchase_orders_account_time on public.purchase_orders(account_id,created_at desc,id desc);
create index if not exists purchase_orders_shop on public.purchase_orders(shop_id);
create index if not exists purchase_orders_offer on public.purchase_orders(offer_id);
create index if not exists purchase_orders_definition on public.purchase_orders(definition_id);
create table if not exists public.order_deliveries (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.purchase_orders(id) on delete cascade,
 unit_id text not null references public.housing_units(unit_id),
 address text not null,
 status text not null default 'queued' check(status in ('queued','delivered')),
 delivered_at timestamptz,
 check((status='queued' and delivered_at is null) or (status='delivered' and delivered_at is not null))
);
create index if not exists order_deliveries_unit on public.order_deliveries(unit_id);
alter table public.shops enable row level security;
alter table public.shop_visits enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.order_deliveries enable row level security;
revoke all on public.shops,public.shop_visits,public.purchase_orders,public.order_deliveries from public,anon,authenticated;
grant select on public.shops,public.shop_visits,public.purchase_orders,public.order_deliveries to authenticated;
grant select on public.shops,public.shop_visits,public.purchase_orders,public.order_deliveries to service_role;
drop policy if exists shops_read_catalog on public.shops;
create policy shops_read_catalog on public.shops for select to authenticated using(true);
drop policy if exists shop_visits_read_own on public.shop_visits;
create policy shop_visits_read_own on public.shop_visits for select to authenticated using(account_id=(select auth.uid()));
drop policy if exists purchase_orders_read_own on public.purchase_orders;
create policy purchase_orders_read_own on public.purchase_orders for select to authenticated using(account_id=(select auth.uid()));
drop policy if exists order_deliveries_read_own on public.order_deliveries;
create policy order_deliveries_read_own on public.order_deliveries for select to authenticated using(exists(select 1 from public.purchase_orders o where o.id=order_id and o.account_id=(select auth.uid())));

create or replace function public.record_shop_visit(p_account_id uuid,p_shop_id text default 'hyphen')
returns timestamptz language plpgsql security definer set search_path='' as $checkout$
declare stamp timestamptz;
begin
 insert into public.shop_visits(account_id,shop_id) values(p_account_id,p_shop_id) on conflict(account_id,shop_id) do nothing;
 select visited_at into stamp from public.shop_visits where account_id=p_account_id and shop_id=p_shop_id;
 return stamp;
end;
$checkout$;
revoke all on function public.record_shop_visit(uuid,text) from public,anon,authenticated;
grant execute on function public.record_shop_visit(uuid,text) to service_role;

create or replace function revive_internal.purchase_order_record(p_order_id uuid)
returns jsonb language sql stable set search_path='' as $checkout$
 select pg_catalog.to_jsonb(o)||pg_catalog.jsonb_build_object('delivery',pg_catalog.to_jsonb(d))
 from public.purchase_orders o join public.order_deliveries d on d.order_id=o.id where o.id=p_order_id;
$checkout$;
revoke all on function revive_internal.purchase_order_record(uuid) from public,anon,authenticated,service_role;

create or replace function public.get_hyphen_checkout()
returns jsonb language plpgsql stable security definer set search_path='' as $checkout$
declare a uuid:=auth.uid(); state text; dest jsonb; offers jsonb:='[]'::jsonb;
begin
 if a is null then raise exception 'Sign in to visit Hyphen.' using errcode='28000'; end if;
 if not exists(select 1 from public.profiles where id=a) then state:='needs_profile';
 elsif not exists(select 1 from public.shops where shop_id='hyphen' and website_enabled) then state:='unavailable';
 elsif not exists(select 1 from public.shop_visits where account_id=a and shop_id='hyphen') then state:='shop_locked';
 else
  select pg_catalog.jsonb_build_object('unit_id',h.unit_id,'address',u.address) into dest from public.home_assignments h join public.housing_units u using(unit_id) where h.account_id=a;
  state:=case when dest is null then 'needs_home' else 'ready' end;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',o.id,'definition_id',o.definition_id,'name',o.label,'condition',o.condition,'price',o.price,'category',d.category,'manufacturer',d.manufacturer,'description',d.description) order by o.price,o.id),'[]'::jsonb)
  into offers from public.surplus_offers o join public.item_definitions d on d.id=o.definition_id where o.active;
 end if;
 return pg_catalog.jsonb_build_object('account_id',a,'state',state,'shop_id','hyphen','home',dest,'offers',offers,'balance',coalesce((select balance from public.chroma_wallets where account_id=a),0));
end;
$checkout$;
revoke all on function public.get_hyphen_checkout() from public,anon,authenticated;
grant execute on function public.get_hyphen_checkout() to authenticated;

create or replace function public.place_hyphen_order(p_request_id uuid,p_offer_id text,p_expected_price integer,p_home_unit text)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
declare a uuid:=auth.uid(); existing public.purchase_orders; offer public.surplus_offers; dest public.home_assignments; address_snapshot text; bal bigint; chosen_name text; created_id uuid; reserved_item uuid;
begin
 if a is null then raise exception 'Sign in before purchasing.' using errcode='28000'; end if;
 if p_request_id is null or p_offer_id is null or p_expected_price is null or p_expected_price<1 or p_home_unit is null then raise exception 'Invalid purchase request.' using errcode='22023'; end if;
 perform 1 from public.profiles where id=a for update;
 if not found then raise exception 'Create your contractor profile first.' using errcode='22023'; end if;
 select * into existing from public.purchase_orders where account_id=a and request_id=p_request_id;
 if found then
  if existing.offer_id<>p_offer_id or existing.amount<>p_expected_price or not exists(select 1 from public.order_deliveries where order_id=existing.id and unit_id=p_home_unit) then raise exception 'This purchase ID belongs to a different request.' using errcode='22023'; end if;
  return revive_internal.purchase_order_record(existing.id);
 end if;
 if exists(select 1 from public.surplus_receipts where account_id=a and request_id=p_request_id) then raise exception 'This purchase ID is already used.' using errcode='22023'; end if;
 if not exists(select 1 from public.shops where shop_id='hyphen' and website_enabled) then raise exception 'Hyphen is unavailable.' using errcode='22023'; end if;
 if not exists(select 1 from public.shop_visits where account_id=a and shop_id='hyphen') then raise exception 'Visit Hyphen in the game before using this shop online.' using errcode='22023'; end if;
 select * into dest from public.home_assignments where account_id=a for share;
 if not found or dest.unit_id<>p_home_unit then raise exception 'Your delivery home changed or is not assigned. Refresh before purchasing.' using errcode='22023'; end if;
 select address into address_snapshot from public.housing_units where unit_id=dest.unit_id;
 select * into offer from public.surplus_offers where id=p_offer_id and active for share;
 if not found then raise exception 'This item is no longer available.' using errcode='22023'; end if;
 if offer.price<>p_expected_price then raise exception 'The price changed. Refresh and review the purchase again.' using errcode='22023'; end if;
 select balance into bal from public.chroma_wallets where account_id=a for update;
 if bal is null or bal<offer.price then raise exception 'Not enough Chroma for this purchase.' using errcode='22023'; end if;
 chosen_name:=offer.label;
 insert into public.purchase_orders(account_id,request_id,shop_id,offer_id,definition_id,item_name,condition,amount)
 values(a,p_request_id,'hyphen',offer.id,offer.definition_id,chosen_name,offer.condition,offer.price) returning id,item_id into created_id,reserved_item;
 insert into public.order_deliveries(order_id,unit_id,address) values(created_id,dest.unit_id,address_snapshot);
 update public.chroma_wallets set balance=balance-offer.price where account_id=a returning balance into bal;
 -- The existing banking trigger links this shop receipt to its currency debit.
 insert into public.surplus_receipts(account_id,request_id,request,result)
 values(a,p_request_id,pg_catalog.jsonb_build_object('action','home_purchase','offer_id',p_offer_id,'expected_price',p_expected_price,'home_unit',p_home_unit),
 pg_catalog.jsonb_build_object('request_id',p_request_id,'action','buy','item_id',reserved_item,'name',chosen_name,'condition',offer.condition,'amount',offer.price,'delta',-offer.price,'balance',bal,'kit_id',null,'order_id',created_id));
 return revive_internal.purchase_order_record(created_id);
end;
$checkout$;
revoke all on function public.place_hyphen_order(uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.place_hyphen_order(uuid,text,integer,text) to authenticated;

create or replace function public.complete_order_delivery(p_delivery_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
declare owner_id uuid; order_row public.purchase_orders; delivery public.order_deliveries;
begin
 select o.account_id into owner_id from public.purchase_orders o join public.order_deliveries d on d.order_id=o.id where d.id=p_delivery_id;
 if owner_id is null then raise exception 'Delivery not found.' using errcode='22023'; end if;
 perform 1 from public.profiles where id=owner_id for update;
 select o.* into order_row from public.purchase_orders o join public.order_deliveries d on d.order_id=o.id where d.id=p_delivery_id for update of o;
 select * into delivery from public.order_deliveries where id=p_delivery_id for update;
 if delivery.status='delivered' then return revive_internal.purchase_order_record(order_row.id); end if;
 perform 1 from public.home_assignments where account_id=owner_id and unit_id=delivery.unit_id for share;
 if not found then raise exception 'Home assignment changed; this delivery requires rerouting.' using errcode='22023'; end if;
 insert into public.item_instances(id,owner_id,definition_id,condition,location,source)
 values(order_row.item_id,owner_id,order_row.definition_id,order_row.condition,'stash','hyphen-order');
 update public.order_deliveries set status='delivered',delivered_at=clock_timestamp() where id=p_delivery_id;
 return revive_internal.purchase_order_record(order_row.id);
end;
$checkout$;
revoke all on function public.complete_order_delivery(uuid) from public,anon,authenticated;
grant execute on function public.complete_order_delivery(uuid) to service_role;

-- Close the legacy direct-to-stash purchase path; retain existing sale/repair logic.
do $checkout$ begin
 if pg_catalog.to_regprocedure('revive_internal.legacy_surplus_trade(uuid,text,uuid,text,uuid,integer)') is null then
  alter function public.surplus_trade(uuid,text,uuid,text,uuid,integer) rename to legacy_surplus_trade;
  alter function public.legacy_surplus_trade(uuid,text,uuid,text,uuid,integer) set schema revive_internal;
 end if;
 if pg_catalog.to_regprocedure('revive_internal.legacy_surplus_terminal()') is null then
  alter function public.get_surplus_terminal() rename to legacy_surplus_terminal;
  alter function public.legacy_surplus_terminal() set schema revive_internal;
 end if;
end $checkout$;
revoke all on function revive_internal.legacy_surplus_trade(uuid,text,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function revive_internal.legacy_surplus_terminal() from public,anon,authenticated,service_role;
create or replace function public.surplus_trade(p_request_id uuid,p_action text,p_item_id uuid default null,p_offer_id text default null,p_kit_id uuid default null,p_expected_amount integer default null)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
begin
 if auth.uid() is null then raise exception 'Sign in before trading.' using errcode='28000'; end if;
 if exists(select 1 from public.surplus_receipts where account_id=auth.uid() and request_id=p_request_id) then
  return revive_internal.legacy_surplus_trade(p_request_id,p_action,p_item_id,p_offer_id,p_kit_id,p_expected_amount);
 end if;
 if p_action='buy' then raise exception 'Use the Hyphen checkout for home delivery.' using errcode='22023'; end if;
 if not exists(select 1 from public.shop_visits where account_id=auth.uid() and shop_id='hyphen') then raise exception 'Visit Hyphen in the game first.' using errcode='22023'; end if;
 return revive_internal.legacy_surplus_trade(p_request_id,p_action,p_item_id,p_offer_id,p_kit_id,p_expected_amount);
end;
$checkout$;
create or replace function public.get_surplus_terminal()
returns jsonb language plpgsql stable security definer set search_path='' as $checkout$
begin
 if auth.uid() is null then raise exception 'Sign in to visit Hyphen.' using errcode='28000'; end if;
 if not exists(select 1 from public.shop_visits where account_id=auth.uid() and shop_id='hyphen') then raise exception 'Visit Hyphen in the game first.' using errcode='22023'; end if;
 return revive_internal.legacy_surplus_terminal();
end;
$checkout$;
revoke all on function public.surplus_trade(uuid,text,uuid,text,uuid,integer),public.get_surplus_terminal() from public,anon,authenticated;
grant execute on function public.surplus_trade(uuid,text,uuid,text,uuid,integer),public.get_surplus_terminal() to authenticated;
notify pgrst,'reload schema';
commit;
