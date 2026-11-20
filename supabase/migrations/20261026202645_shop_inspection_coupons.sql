create table shop_private.coupon_rules(attachment_id uuid primary key references mail_private.attachments(id),shop_id text references public.shops(shop_id),percent_off integer not null check(percent_off between 1 and 90),minimum integer not null default 0 check(minimum>=0));
create table shop_private.favorites(owner_id uuid not null references public.profiles(id) on delete cascade,shop_id text not null references public.shops(shop_id),primary key(owner_id,shop_id));
alter table shop_private.coupon_rules enable row level security;alter table shop_private.favorites enable row level security;
revoke all on shop_private.coupon_rules,shop_private.favorites from public,anon,authenticated;
grant usage on schema shop_private to service_role;grant all on shop_private.coupon_rules to service_role;
alter table public.purchase_orders add column applied_coupon uuid references mail_private.coupons(attachment_id),add column listed_price integer;
create index purchase_applied_coupon on public.purchase_orders(applied_coupon);
alter function shop_private.catalog(text) rename to catalog_base;
revoke all on function shop_private.catalog_base(text) from public,anon,authenticated;
create function shop_private.catalog(p_shop text) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();c jsonb;begin
c:=shop_private.catalog_base(p_shop);
return c||jsonb_build_object('equipped',coalesce((select jsonb_object_agg(i.inventory_position,jsonb_build_object('name',d.name,'condition',i.condition,'weight',s.weight_lb,'capacity',s.bag_slots,'allowance',s.bag_allowance)) from public.item_instances i join public.item_definitions d on d.id=i.definition_id left join inventory_private.specs s on s.definition_id=d.id where i.owner_id=u and i.location='stash' and i.inventory_position in ('primary','backup','shield','bag')),'{}'::jsonb),'offers',(select jsonb_agg(v||jsonb_build_object('manufacturer',d.manufacturer,'weight',s.weight_lb,'slot',s.equip_slot,'capacity',s.bag_slots,'allowance',s.bag_allowance,'stackable',s.stackable)) from jsonb_array_elements(c->'offers')v join public.item_definitions d on d.id=v->>'definition_id' left join inventory_private.specs s on s.definition_id=d.id),
'coupons',coalesce((select jsonb_agg(jsonb_build_object('id',a.attachment_id,'label',a.label,'quantity',a.quantity,'shop_id',r.shop_id,'percent_off',r.percent_off,'minimum',r.minimum)) from mail_private.coupons a left join shop_private.coupon_rules r on r.attachment_id=a.attachment_id where a.owner_id=u),'[]'::jsonb),
'orders',coalesce((select jsonb_agg(x) from (select id,item_name,amount,listed_price,applied_coupon,created_at from public.purchase_orders where account_id=u and shop_id=p_shop order by created_at desc limit 50)x),'[]'::jsonb));end;$$;
revoke all on function shop_private.catalog(text) from public,anon;grant execute on function shop_private.catalog(text) to authenticated;
create or replace function shop_private.directory() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();begin return jsonb_build_object('visited',coalesce((select jsonb_agg(shop_id) from public.shop_visits where account_id=u),'[]'::jsonb),'favorites',coalesce((select jsonb_agg(shop_id) from shop_private.favorites where owner_id=u),'[]'::jsonb),'balance',coalesce((select balance from public.chroma_wallets where account_id=u),0));end;$$;
create function shop_private.favorite(p_shop text,p_value boolean) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=shop_private.guard();begin
if not exists(select 1 from public.shop_visits where account_id=u and shop_id=p_shop) then raise exception 'Discover this shop first.';end if;
if p_value then insert into shop_private.favorites values(u,p_shop) on conflict do nothing;else delete from shop_private.favorites where owner_id=u and shop_id=p_shop;end if;end;$$;
revoke all on function shop_private.favorite(text,boolean) from public,anon;grant execute on function shop_private.favorite(text,boolean) to authenticated;
create function public.shop_favorite(p_shop text,p_value boolean) returns void language sql security invoker set search_path='' as $$select shop_private.favorite(p_shop,p_value);$$;
revoke all on function public.shop_favorite(text,boolean) from public,anon;grant execute on function public.shop_favorite(text,boolean) to authenticated;
create function shop_private.purchase_coupon(p_shop text,p_request uuid,p_offer text,p_price integer,p_home text,p_coupon uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=shop_private.guard();o shop_private.offers;old public.purchase_orders;c jsonb;actual_price integer;listed integer;coupon mail_private.coupons;rule shop_private.coupon_rules;order_id uuid;item_label text;address_text text;begin
if p_request is null or p_price is null or p_price<=0 or p_home is null then raise exception 'Invalid purchase.';end if;
select * into old from public.purchase_orders where account_id=u and request_id=p_request;
if found then if old.shop_id<>p_shop or old.catalog_offer is distinct from p_offer or old.amount<>p_price or old.catalog_home is distinct from p_home or old.applied_coupon is distinct from p_coupon then raise exception 'Request ID used for a different purchase.';end if;return revive_internal.purchase_order_record(old.id);end if;
if exists(select 1 from shop_private.sales where owner_id=u and request_id=p_request) or exists(select 1 from public.surplus_receipts where account_id=u and request_id=p_request) then raise exception 'Request ID already used.';end if;
c:=shop_private.catalog(p_shop);
if c->'home'->>'unit_id' is distinct from p_home then raise exception 'Your home changed. Refresh before purchasing.';end if;
select * into o from shop_private.offers where id=p_offer and shop_id=p_shop for share;if not found then raise exception 'Offer unavailable.';end if;
select (v->>'price')::integer into actual_price from jsonb_array_elements(c->'offers')v where v->>'id'=p_offer;
listed:=actual_price;
if p_coupon is not null then
 select * into coupon from mail_private.coupons where attachment_id=p_coupon and owner_id=u for update;
 if not found or coupon.quantity<1 then raise exception 'Coupon is unavailable or already used.';end if;
 select * into rule from shop_private.coupon_rules where attachment_id=p_coupon;
 if not found then raise exception 'Coupon terms are not available.';end if;
 if rule.shop_id is not null and rule.shop_id<>p_shop then raise exception 'Coupon is for another shop.';end if;
 if actual_price<rule.minimum then raise exception 'Coupon minimum spend has not been reached.';end if;
 actual_price:=greatest(1,actual_price-floor(actual_price*rule.percent_off/100.0)::integer);
 if actual_price=listed then raise exception 'This coupon cannot save Chroma on this item.';end if;
end if;
if actual_price is distinct from p_price then raise exception 'Price changed. Review the current price.';end if;
update public.chroma_wallets set balance=balance-p_price where account_id=u and balance>=p_price;if not found then raise exception 'Not enough Chroma.';end if;
select name into item_label from public.item_definitions where id=o.definition_id;
insert into public.purchase_orders(account_id,request_id,shop_id,offer_id,catalog_offer,catalog_home,applied_coupon,listed_price,definition_id,item_name,condition,amount) values(u,p_request,p_shop,null,p_offer,p_home,p_coupon,listed,o.definition_id,item_label,o.condition,p_price) returning id into order_id;
insert into public.order_deliveries(order_id,unit_id,address) values(order_id,p_home,c->'home'->>'address');
update public.chroma_transactions set reference=order_id,description=(select name from public.shops where shop_id=p_shop)||' purchase: '||item_label where account_id=u and source='account' and reference is null and recorded_xid=pg_current_xact_id() and delta=-p_price;
if p_coupon is not null then update mail_private.coupons set quantity=quantity-1 where attachment_id=p_coupon;end if;
return revive_internal.purchase_order_record(order_id);end;$$;
revoke all on function shop_private.purchase_coupon(text,uuid,text,integer,text,uuid) from public,anon;grant execute on function shop_private.purchase_coupon(text,uuid,text,integer,text,uuid) to authenticated;
create function public.shop_purchase_coupon(p_shop text,p_request uuid,p_offer text,p_price integer,p_home text,p_coupon uuid default null) returns jsonb language sql security invoker set search_path='' as $$select shop_private.purchase_coupon(p_shop,p_request,p_offer,p_price,p_home,p_coupon);$$;
revoke all on function public.shop_purchase_coupon(text,uuid,text,integer,text,uuid) from public,anon;grant execute on function public.shop_purchase_coupon(text,uuid,text,integer,text,uuid) to authenticated;
create or replace function public.issue_mail(p_owner uuid,p_key text,p_sender text,p_subject text,p_body text,p_kind text,p_expiry timestamptz default null,p_attachments jsonb default '[]') returns uuid language plpgsql security invoker set search_path='' as $$
declare l uuid;a jsonb;attachment uuid;begin
 insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,expires_at) values(p_owner,p_key,p_sender,p_subject,p_body,p_kind,p_expiry) on conflict(owner_id,source_key) do nothing returning id into l;
 if l is null then select id into l from mail_private.letters where owner_id=p_owner and source_key=p_key;return l;end if;
 for a in select value from jsonb_array_elements(p_attachments) loop insert into mail_private.attachments(letter_id,kind,label,amount) values(l,a->>'kind',a->>'label',coalesce((a->>'amount')::bigint,1)) returning id into attachment;
if a->>'kind'='coupon' and a ? 'percent_off' then insert into shop_private.coupon_rules values(attachment,a->>'shop_id',(a->>'percent_off')::integer,coalesce((a->>'minimum')::integer,0));end if;end loop;return l;end;$$;
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
 select l.id,l.order_id,l.sender,l.subject,l.body,l.kind,l.created_at,l.read_at,l.archived_at,l.expires_at,
 case when l.order_id is null then null else jsonb_build_object('status',case when d.collected_at is not null or i.id is not null and i.location<>'delivery' then 'collected' when d.status='delivered' then 'delivered' when clock_timestamp()>=l.created_at+interval '1 minute' then 'in_transit' else 'preparing' end,'eta',l.created_at+interval '5 minutes','address',coalesce(h.address,d.address)) end as delivery,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'label',a.label,'amount',a.amount,'claimed_at',a.claimed_at)) from mail_private.attachments a where a.letter_id=l.id),'[]'::jsonb) as attachments
 from mail_private.letters l left join public.order_deliveries d on d.order_id=l.order_id left join public.purchase_orders o on o.id=l.order_id left join public.item_instances i on i.id=o.item_id
 left join public.home_assignments ha on ha.account_id=u left join public.housing_units h on h.unit_id=ha.unit_id
 where l.owner_id=u
 )x),'[]'::jsonb),'coupons',coalesce((select jsonb_agg(jsonb_build_object('label',label,'quantity',quantity)) from mail_private.coupons where owner_id=u),'[]'::jsonb));
end;$$;
notify pgrst,'reload schema';
