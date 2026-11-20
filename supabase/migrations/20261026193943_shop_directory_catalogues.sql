alter table public.order_deliveries add column collected_at timestamptz;
create schema shop_private;revoke all on schema shop_private from public,anon;grant usage on schema shop_private to authenticated;
create table shop_private.offers(id text primary key,shop_id text not null references public.shops(shop_id),definition_id text not null references public.item_definitions(id),price integer not null check(price>0),condition integer not null default 100 check(condition between 1 and 100),rotation integer not null);
create index shop_offers_shop on shop_private.offers(shop_id);
create table shop_private.sales(owner_id uuid not null references public.profiles(id),request_id uuid not null,item_id uuid not null,price integer not null,item_name text not null,created_at timestamptz not null default clock_timestamp(),primary key(owner_id,request_id));
alter table shop_private.offers enable row level security;alter table shop_private.sales enable row level security;revoke all on all tables in schema shop_private from public,anon,authenticated;
alter table public.purchase_orders alter column offer_id drop not null;
alter table public.purchase_orders add column catalog_offer text references shop_private.offers(id);
alter table public.purchase_orders add column catalog_home text;
create index purchase_catalog_offer on public.purchase_orders(catalog_offer);
insert into public.shops values('hyphen','Hyphen Surplus',true) on conflict(shop_id) do nothing;
insert into public.shops values('collateral','Collateral',true) on conflict(shop_id) do nothing;
insert into public.shops values('loose-ends','Loose Ends',true) on conflict(shop_id) do nothing;
insert into public.shops values('trigger','Trigger',true) on conflict(shop_id) do nothing;
insert into public.shops values('carryall','Carryall',true) on conflict(shop_id) do nothing;
insert into public.shops values('buffer','Buffer',true) on conflict(shop_id) do nothing;
insert into public.shops values('doubleback','Doubleback',true) on conflict(shop_id) do nothing;
insert into public.shops values('noodle-rush','Noodle Rush',true) on conflict(shop_id) do nothing;
insert into public.shops values('aurelle','Aurelle',true) on conflict(shop_id) do nothing;
insert into public.shops values('greenhouse','Greenhouse',true) on conflict(shop_id) do nothing;
insert into public.shops values('benchwork','Benchwork',true) on conflict(shop_id) do nothing;
insert into public.shops values('mend','Mend',true) on conflict(shop_id) do nothing;
insert into public.shops values('roughstock','Roughstock',true) on conflict(shop_id) do nothing;
insert into public.shops values('foundry-exchange','Foundry Exchange',true) on conflict(shop_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('flux-rifle','Flux Rifle','weapon','A dependable field rifle. Also stocked as general surplus.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('flux-rifle','gear',7.5,false,'primary',null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('field-dagger','Field dagger','weapon','Compact backup equipment.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('field-dagger','gear',1.5,false,'backup',null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('field-shield','Field shield-tech','part','An attached shield-tech unit. Gameplay support is being developed separately.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('field-shield','gear',3,false,'shield',null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('starter-backpack','Starter backpack','part','Eight item slots and a 50 lb allowance. Free starter replacement remains available in Inventory when eligible.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('starter-backpack','gear',2,false,'bag',8,50) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('trail-backpack','Trail backpack','part','Twelve item slots and a 65 lb allowance.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('trail-backpack','gear',3,false,'bag',12,65) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('flux-service-kit','Flux Service Kit','part','Equipment maintenance supplies. Repair services are handled in person.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('flux-service-kit','materials',1.5,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('focus-01','Focusing assembly','part','A replacement focusing component.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('focus-01','materials',1,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('meal-pack','Meal pack','food','A sealed field meal.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('meal-pack','care',2,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('daybreak-recovery-broth','Daybreak Recovery Broth','food','Packaged broth for a warm meal.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('daybreak-recovery-broth','care',2,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('good-orbit-citrus-drink','Citrus drink','food','A bottled citrus refreshment. Existing product name is retained in saved records.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('good-orbit-citrus-drink','care',0.5,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('doubleback-burger','Doubleback burger','food','A generously packed burger, prepared for home delivery.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('doubleback-burger','care',1,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('doubleback-fries','Seasoned fries','food','Doubleback’s familiar side order.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('doubleback-fries','care',0.5,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('noodle-bowl','Rush noodle bowl','food','Noodles and vegetables in a sealed takeaway bowl.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('noodle-bowl','care',1.5,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('aurelle-supper','Aurelle supper','food','An elaborate prepared meal. A higher price reflects dining style, not a promised combat advantage.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('aurelle-supper','care',2,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('greenhouse-bowl','Greenhouse grain bowl','food','A balanced takeaway meal with grains and vegetables.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('greenhouse-bowl','care',1.2,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('health-stim','Health-stim stick','part','A compact recovery supply. Gameplay effects are handled by the game.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('health-stim','care',0.2,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('recovered-relay','Recovered relay','part','A salvaged relay sold as a physical component.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('recovered-relay','misc',2,false,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('salvage-wire','Salvage wire bundle','part','Recovered wire for future maintenance and fabrication.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('salvage-wire','materials',0.5,true,null,null,null) on conflict(definition_id) do nothing;
insert into public.item_definitions(id,name,category,description,manufacturer) values('refined-alloy','Refined alloy','part','Processed material for future fabrication.','Independent suppliers') on conflict(id) do nothing;
insert into inventory_private.specs values('refined-alloy','materials',0.3,true,null,null,null) on conflict(definition_id) do nothing;
insert into shop_private.offers values('hyphen:flux-service-kit','hyphen','flux-service-kit',40,100,0);
insert into shop_private.offers values('hyphen:meal-pack','hyphen','meal-pack',20,100,1);
insert into shop_private.offers values('hyphen:flux-rifle','hyphen','flux-rifle',140,100,2);
insert into shop_private.offers values('collateral:flux-rifle','collateral','flux-rifle',140,100,0);
insert into shop_private.offers values('collateral:recovered-relay','collateral','recovered-relay',12,100,1);
insert into shop_private.offers values('loose-ends:recovered-relay','loose-ends','recovered-relay',12,100,0);
insert into shop_private.offers values('loose-ends:salvage-wire','loose-ends','salvage-wire',10,100,1);
insert into shop_private.offers values('trigger:flux-rifle','trigger','flux-rifle',140,100,0);
insert into shop_private.offers values('trigger:field-dagger','trigger','field-dagger',45,100,1);
insert into shop_private.offers values('trigger:flux-service-kit','trigger','flux-service-kit',40,100,2);
insert into shop_private.offers values('trigger:starter-backpack','trigger','starter-backpack',20,100,3);
insert into shop_private.offers values('carryall:starter-backpack','carryall','starter-backpack',20,100,0);
insert into shop_private.offers values('carryall:trail-backpack','carryall','trail-backpack',80,100,1);
insert into shop_private.offers values('carryall:field-dagger','carryall','field-dagger',45,100,2);
insert into shop_private.offers values('buffer:field-shield','buffer','field-shield',100,100,0);
insert into shop_private.offers values('buffer:starter-backpack','buffer','starter-backpack',20,100,1);
insert into shop_private.offers values('doubleback:doubleback-burger','doubleback','doubleback-burger',14,100,0);
insert into shop_private.offers values('doubleback:doubleback-fries','doubleback','doubleback-fries',8,100,1);
insert into shop_private.offers values('noodle-rush:noodle-bowl','noodle-rush','noodle-bowl',18,100,0);
insert into shop_private.offers values('noodle-rush:daybreak-recovery-broth','noodle-rush','daybreak-recovery-broth',25,100,1);
insert into shop_private.offers values('aurelle:aurelle-supper','aurelle','aurelle-supper',65,100,0);
insert into shop_private.offers values('aurelle:good-orbit-citrus-drink','aurelle','good-orbit-citrus-drink',20,100,1);
insert into shop_private.offers values('greenhouse:greenhouse-bowl','greenhouse','greenhouse-bowl',22,100,0);
insert into shop_private.offers values('greenhouse:daybreak-recovery-broth','greenhouse','daybreak-recovery-broth',25,100,1);
insert into shop_private.offers values('benchwork:flux-service-kit','benchwork','flux-service-kit',40,100,0);
insert into shop_private.offers values('benchwork:focus-01','benchwork','focus-01',30,100,1);
insert into shop_private.offers values('mend:health-stim','mend','health-stim',24,100,0);
insert into shop_private.offers values('mend:meal-pack','mend','meal-pack',20,100,1);
insert into shop_private.offers values('roughstock:salvage-wire','roughstock','salvage-wire',10,100,0);
insert into shop_private.offers values('roughstock:recovered-relay','roughstock','recovered-relay',12,100,1);
insert into shop_private.offers values('foundry-exchange:refined-alloy','foundry-exchange','refined-alloy',18,100,0);
insert into shop_private.offers values('foundry-exchange:focus-01','foundry-exchange','focus-01',30,100,1);
create function shop_private.guard() returns uuid language plpgsql security definer set search_path='' as $$declare u uuid:=auth.uid();begin
if u is null then raise exception 'Sign in to open Shops.' using errcode='28000';end if;
perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
if exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission') then raise exception 'Shops are unavailable during deployment.';end if;return u;end;$$;
revoke all on function shop_private.guard() from public,anon,authenticated;
create function shop_private.directory() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();begin
return jsonb_build_object('visited',coalesce((select jsonb_agg(shop_id) from public.shop_visits where account_id=u),'[]'::jsonb),'balance',coalesce((select balance from public.chroma_wallets where account_id=u),0));end;$$;
create function shop_private.catalog(p_shop text) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();begin
if not exists(select 1 from public.shop_visits where account_id=u and shop_id=p_shop) then raise exception 'Discover this shop in the game first.';end if;
if not exists(select 1 from public.shops where shop_id=p_shop and website_enabled) then raise exception 'Shop unavailable.';end if;
return jsonb_build_object('balance',coalesce((select balance from public.chroma_wallets where account_id=u),0),'home',(select jsonb_build_object('unit_id',h.unit_id,'address',x.address) from public.home_assignments h join public.housing_units x using(unit_id) where h.account_id=u),
'offers',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'definition_id',o.definition_id,'name',d.name,'description',d.description,'condition',o.condition,'base_price',o.price,'price',case when o.rotation=mod(floor(extract(epoch from clock_timestamp())/86400)::integer,(select count(*)::integer from shop_private.offers where shop_id=p_shop)) then greatest(1,floor(o.price*.85)::integer) else o.price end)) from shop_private.offers o join public.item_definitions d on d.id=o.definition_id where o.shop_id=p_shop),'[]'::jsonb),
'orders',coalesce((select jsonb_agg(x) from (select id,item_name,amount,created_at from public.purchase_orders where account_id=u and shop_id=p_shop order by created_at desc limit 50)x),'[]'::jsonb),
'sales',coalesce((select jsonb_agg(x) from (select item_name,price,created_at from shop_private.sales where owner_id=u and p_shop='hyphen' order by created_at desc limit 50)x),'[]'::jsonb));end;$$;
create function shop_private.purchase(p_shop text,p_request uuid,p_offer text,p_price integer,p_home text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=shop_private.guard();o shop_private.offers;old public.purchase_orders;c jsonb;actual_price integer;order_id uuid;item_label text;address_text text;begin
if p_request is null or p_price is null or p_price<=0 or p_home is null then raise exception 'Invalid purchase.';end if;
select * into old from public.purchase_orders where account_id=u and request_id=p_request;
if found then if old.shop_id<>p_shop or old.catalog_offer is distinct from p_offer or old.amount<>p_price or old.catalog_home is distinct from p_home then raise exception 'Request ID used for a different purchase.';end if;return revive_internal.purchase_order_record(old.id);end if;
if exists(select 1 from shop_private.sales where owner_id=u and request_id=p_request) or exists(select 1 from public.surplus_receipts where account_id=u and request_id=p_request) then raise exception 'Request ID already used.';end if;
c:=shop_private.catalog(p_shop);
if c->'home'->>'unit_id' is distinct from p_home then raise exception 'Your home changed. Refresh before purchasing.';end if;
select * into o from shop_private.offers where id=p_offer and shop_id=p_shop for share;if not found then raise exception 'Offer unavailable.';end if;
select (v->>'price')::integer into actual_price from jsonb_array_elements(c->'offers')v where v->>'id'=p_offer;
if actual_price is distinct from p_price then raise exception 'Price changed. Review the current price.';end if;
update public.chroma_wallets set balance=balance-p_price where account_id=u and balance>=p_price;if not found then raise exception 'Not enough Chroma.';end if;
select name into item_label from public.item_definitions where id=o.definition_id;
insert into public.purchase_orders(account_id,request_id,shop_id,offer_id,catalog_offer,catalog_home,definition_id,item_name,condition,amount) values(u,p_request,p_shop,null,p_offer,p_home,o.definition_id,item_label,o.condition,p_price) returning id into order_id;
insert into public.order_deliveries(order_id,unit_id,address) values(order_id,p_home,c->'home'->>'address');
update public.chroma_transactions set reference=order_id,description=(select name from public.shops where shop_id=p_shop)||' purchase: '||item_label where account_id=u and source='account' and reference is null and recorded_xid=pg_current_xact_id() and delta=-p_price;
return revive_internal.purchase_order_record(order_id);end;$$;
create function shop_private.sell(p_request uuid,p_item uuid,p_price integer) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();i public.item_instances;old shop_private.sales;value integer;label text;begin
if p_request is null or p_item is null or p_price is null then raise exception 'Invalid sale.';end if;
select * into old from shop_private.sales where owner_id=u and request_id=p_request;if found then if old.item_id<>p_item or old.price<>p_price then raise exception 'Request ID used for a different sale.';end if;return to_jsonb(old);end if;
if exists(select 1 from public.purchase_orders where account_id=u and request_id=p_request) or exists(select 1 from public.surplus_receipts where account_id=u and request_id=p_request) then raise exception 'Request ID already used.';end if;
if not exists(select 1 from public.shop_visits where account_id=u and shop_id='hyphen') then raise exception 'Discover Hyphen first.';end if;
select * into i from public.item_instances where id=p_item and owner_id=u and location='stash' and inventory_position in ('home','person') and mission_run_id is null for update;
if not found then raise exception 'Item unavailable. Unequip gear before selling it.';end if;
select greatest(1,floor(full_condition_value*i.condition/100.0)::integer) into value from public.surplus_sell_prices where definition_id=i.definition_id;
if value is null or value<>p_price then raise exception 'Sale quote changed or this item is not accepted.';end if;
select name into label from public.item_definitions where id=i.definition_id;
insert into public.chroma_wallets(account_id,balance) values(u,0) on conflict(account_id) do nothing;
update public.chroma_wallets set balance=balance+value where account_id=u;
insert into shop_private.sales values(u,p_request,p_item,value,label,clock_timestamp());update public.order_deliveries set collected_at=coalesce(collected_at,clock_timestamp()) where order_id in (select id from public.purchase_orders where item_id=i.id);delete from public.item_instances where id=i.id;
insert into inventory_private.settings(owner_id,revision) values(u,1) on conflict(owner_id) do update set revision=inventory_private.settings.revision+1;
update public.chroma_transactions set reference=p_request,description='Hyphen sale: '||label where account_id=u and source='account' and reference is null and recorded_xid=pg_current_xact_id() and delta=value;
return jsonb_build_object('item_name',label,'price',value);end;$$;
create function shop_private.quotes() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();begin
if not exists(select 1 from public.shop_visits where account_id=u and shop_id='hyphen') then raise exception 'Discover Hyphen first.';end if;
return coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',d.name,'condition',i.condition,'position',i.inventory_position,'price',greatest(1,floor(p.full_condition_value*i.condition/100.0)::integer))) from public.item_instances i join public.surplus_sell_prices p on p.definition_id=i.definition_id join public.item_definitions d on d.id=i.definition_id where i.owner_id=u and i.location='stash' and i.inventory_position in ('home','person') and i.mission_run_id is null),'[]'::jsonb);end;$$;
revoke all on function shop_private.directory() from public,anon;grant execute on function shop_private.directory() to authenticated;
create function public.shop_directory() returns jsonb language sql security invoker set search_path='' as $$select shop_private.directory();$$;revoke all on function public.shop_directory() from public,anon;grant execute on function public.shop_directory() to authenticated;
revoke all on function shop_private.catalog(text) from public,anon;grant execute on function shop_private.catalog(text) to authenticated;
create function public.shop_catalog(p_shop text) returns jsonb language sql security invoker set search_path='' as $$select shop_private.catalog(p_shop);$$;revoke all on function public.shop_catalog(text) from public,anon;grant execute on function public.shop_catalog(text) to authenticated;
revoke all on function shop_private.purchase(text,uuid,text,integer,text) from public,anon;grant execute on function shop_private.purchase(text,uuid,text,integer,text) to authenticated;
create function public.shop_purchase(p_shop text,p_request uuid,p_offer text,p_price integer,p_home text) returns jsonb language sql security invoker set search_path='' as $$select shop_private.purchase(p_shop,p_request,p_offer,p_price,p_home);$$;revoke all on function public.shop_purchase(text,uuid,text,integer,text) from public,anon;grant execute on function public.shop_purchase(text,uuid,text,integer,text) to authenticated;
revoke all on function shop_private.sell(uuid,uuid,integer) from public,anon;grant execute on function shop_private.sell(uuid,uuid,integer) to authenticated;
create function public.shop_sell(p_request uuid,p_item uuid,p_price integer) returns jsonb language sql security invoker set search_path='' as $$select shop_private.sell(p_request,p_item,p_price);$$;revoke all on function public.shop_sell(uuid,uuid,integer) from public,anon;grant execute on function public.shop_sell(uuid,uuid,integer) to authenticated;
revoke all on function shop_private.quotes() from public,anon;grant execute on function shop_private.quotes() to authenticated;
create function public.shop_quotes() returns jsonb language sql security invoker set search_path='' as $$select shop_private.quotes();$$;revoke all on function public.shop_quotes() from public,anon;grant execute on function public.shop_quotes() to authenticated;
notify pgrst,'reload schema';
create or replace function mail_private.snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=mail_private.guard();due_delivery record;begin
 -- Due deliveries settle on the next mail refresh. Absolute timestamps survive restarts/offline time.
 for due_delivery in select x.id from public.order_deliveries x join public.purchase_orders o on o.id=x.order_id where o.account_id=u and x.status='queued' and o.created_at+interval '5 minutes'<=clock_timestamp() loop
 if exists(select 1 from public.home_assignments where account_id=u) then perform public.complete_order_delivery(due_delivery.id);end if;
 end loop;
 insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,order_id,created_at)
 select u,'order:'||o.id,s.name,'A package for your home','Your order is being delivered to your current home. Its contents stay sealed until you collect it in-game.','shop',o.id,o.created_at
 from public.purchase_orders o join public.shops s using(shop_id) where o.account_id=u on conflict(owner_id,source_key) do nothing;
 return jsonb_build_object('limit',50,'now',clock_timestamp(),'letters',coalesce((
 select jsonb_agg(x order by x.created_at desc,x.id) from (
 select l.id,l.sender,l.subject,l.body,l.kind,l.created_at,l.read_at,l.archived_at,l.expires_at,
 case when l.order_id is null then null else jsonb_build_object('status',case when d.collected_at is not null or i.id is not null and i.location<>'delivery' then 'collected' when d.status='delivered' then 'delivered' when clock_timestamp()>=l.created_at+interval '1 minute' then 'in_transit' else 'preparing' end,'eta',l.created_at+interval '5 minutes','address',coalesce(h.address,d.address)) end as delivery,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'label',a.label,'amount',a.amount,'claimed_at',a.claimed_at)) from mail_private.attachments a where a.letter_id=l.id),'[]'::jsonb) as attachments
 from mail_private.letters l left join public.order_deliveries d on d.order_id=l.order_id left join public.purchase_orders o on o.id=l.order_id left join public.item_instances i on i.id=o.item_id
 left join public.home_assignments ha on ha.account_id=u left join public.housing_units h on h.unit_id=ha.unit_id
 where l.owner_id=u
 )x),'[]'::jsonb),'coupons',coalesce((select jsonb_agg(jsonb_build_object('label',label,'quantity',quantity)) from mail_private.coupons where owner_id=u),'[]'::jsonb));
end;$$;
create or replace function mail_private.collect_order(p_owner uuid,p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.purchase_orders;begin
 perform 1 from public.profiles where id=p_owner for update;
 if exists(select 1 from public.mission_runs where account_id=p_owner and status='active') then raise exception 'Return from deployment first.';end if;
 select * into o from public.purchase_orders where id=p_order and account_id=p_owner;
 if not found then raise exception 'Package unavailable.';end if;
 if exists(select 1 from public.item_instances where id=o.item_id and location='stash') then return;end if;
 if not exists(select 1 from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=p_owner and i.location='stash' and i.inventory_position='home' and i.definition_id=o.definition_id and i.condition=o.condition and s.stackable group by i.definition_id,i.condition having count(*)%100>0) and inventory_private.used_slots(p_owner,'home')>=coalesce((select home_slots from inventory_private.settings where owner_id=p_owner),25) then raise exception 'Home storage is full. Your package is safe.';end if;
 update public.item_instances set location='stash',inventory_position='home' where id=o.item_id and owner_id=p_owner and location='delivery';
 if not found then raise exception 'Package has not arrived.';end if;
 update public.order_deliveries set collected_at=coalesce(collected_at,clock_timestamp()) where order_id=p_order;
 insert into inventory_private.settings(owner_id,revision) values(p_owner,1) on conflict(owner_id) do update set revision=inventory_private.settings.revision+1;
end;$$;

create or replace function public.get_hyphen_checkout()
returns jsonb language plpgsql security definer set search_path='' as $checkout$
declare a uuid:=auth.uid(); state text; dest jsonb; offers jsonb:='[]'::jsonb;
begin
 perform shop_private.guard();
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

create or replace function public.place_hyphen_order(p_request_id uuid,p_offer_id text,p_expected_price integer,p_home_unit text)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
declare a uuid:=auth.uid(); existing public.purchase_orders; offer public.surplus_offers; dest public.home_assignments; address_snapshot text; bal bigint; chosen_name text; created_id uuid; reserved_item uuid;
begin
 perform shop_private.guard();
 if a is null then raise exception 'Sign in before purchasing.' using errcode='28000'; end if;
 if p_request_id is null or p_offer_id is null or p_expected_price is null or p_expected_price<1 or p_home_unit is null then raise exception 'Invalid purchase request.' using errcode='22023'; end if;
 perform 1 from public.profiles where id=a for update;
 if not found then raise exception 'Create your contractor profile first.' using errcode='22023'; end if;
 select * into existing from public.purchase_orders where account_id=a and request_id=p_request_id;
 if found then
  if existing.offer_id is distinct from p_offer_id or existing.amount<>p_expected_price or not exists(select 1 from public.order_deliveries where order_id=existing.id and unit_id=p_home_unit) then raise exception 'This purchase ID belongs to a different request.' using errcode='22023'; end if;
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

create or replace function public.surplus_trade(p_request_id uuid,p_action text,p_item_id uuid default null,p_offer_id text default null,p_kit_id uuid default null,p_expected_amount integer default null)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
begin
 perform shop_private.guard();
 if auth.uid() is null then raise exception 'Sign in before trading.' using errcode='28000'; end if;
 if exists(select 1 from public.surplus_receipts where account_id=auth.uid() and request_id=p_request_id) then
  return revive_internal.legacy_surplus_trade(p_request_id,p_action,p_item_id,p_offer_id,p_kit_id,p_expected_amount);
 end if;
 if exists(select 1 from shop_private.sales where owner_id=auth.uid() and request_id=p_request_id) or exists(select 1 from public.purchase_orders where account_id=auth.uid() and request_id=p_request_id and catalog_offer is not null) then raise exception 'Request ID already used.';end if;
 if p_action='sell' and not exists(select 1 from public.item_instances where id=p_item_id and owner_id=auth.uid() and location='stash' and inventory_position in ('home','person')) then raise exception 'Unequip gear before selling it.';end if;
 if p_action='buy' then raise exception 'Use the Hyphen checkout for home delivery.' using errcode='22023'; end if;
 if not exists(select 1 from public.shop_visits where account_id=auth.uid() and shop_id='hyphen') then raise exception 'Visit Hyphen in the game first.' using errcode='22023'; end if;
 return revive_internal.legacy_surplus_trade(p_request_id,p_action,p_item_id,p_offer_id,p_kit_id,p_expected_amount);
end;
$checkout$;

create or replace function public.get_surplus_terminal()
returns jsonb language plpgsql security definer set search_path='' as $checkout$
begin
 perform shop_private.guard();
 if auth.uid() is null then raise exception 'Sign in to visit Hyphen.' using errcode='28000'; end if;
 if not exists(select 1 from public.shop_visits where account_id=auth.uid() and shop_id='hyphen') then raise exception 'Visit Hyphen in the game first.' using errcode='22023'; end if;
 return revive_internal.legacy_surplus_terminal();
end;
$checkout$;

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
 if clock_timestamp()<order_row.created_at+interval '5 minutes' then raise exception 'Delivery is still in transit.';end if;
 update public.order_deliveries d set unit_id=h.unit_id,address=u.address from public.home_assignments h join public.housing_units u using(unit_id) where d.id=p_delivery_id and h.account_id=owner_id;
 if not found then raise exception 'A home is required for delivery.';end if;
 insert into public.item_instances(id,owner_id,definition_id,condition,location,source)
 values(order_row.item_id,owner_id,order_row.definition_id,order_row.condition,'delivery',order_row.shop_id||'-order');
 update public.order_deliveries set status='delivered',delivered_at=clock_timestamp() where id=p_delivery_id;
 return revive_internal.purchase_order_record(order_row.id);
end;
$checkout$;
