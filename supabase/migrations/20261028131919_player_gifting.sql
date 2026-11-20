create schema gift_private;
revoke all on schema gift_private from public,anon;
grant usage on schema gift_private to authenticated;
insert into public.item_definitions(id,name,category,description,manufacturer) values('gift-box','Gift Box','part','Packaging for up to ten individual gift items. Shipping is charged separately.','Parcel Cooperative');
insert into inventory_private.specs values('gift-box','misc',.5,false,null,null,null);
insert into shop_private.offers(id,shop_id,definition_id,price,condition,rotation) values('hyphen:gift-box','hyphen','gift-box',5,100,99);
alter table public.item_instances drop constraint item_instances_location_check;
alter table public.item_instances add constraint item_instances_location_check check(location in('stash','mission','delivery','housing','gift'));
create table gift_private.settings(owner_id uuid primary key references public.profiles(id),receive_friends boolean not null default true,receive_strangers boolean not null default false);
create table gift_private.config(id boolean primary key default true check(id),base_fee integer not null check(base_fee>=0),per_lb numeric not null check(per_lb>=0),hand_fee integer not null check(hand_fee>=0));
insert into gift_private.config values(true,5,1,2);
create table gift_private.gifts(id uuid primary key default gen_random_uuid(),sender uuid not null references public.profiles(id),recipient uuid not null references public.profiles(id),kind text not null check(kind in('physical','chroma')),route text not null check(route in('courier','hand','digital')),status text not null check(status in('preparing','in_transit','delivered','collected','returned','cancelled')),amount integer not null default 0 check(amount between 0 and 5000),units integer not null default 0 check(units between 0 and 10),weight numeric not null default 0,fee integer not null default 0,letter text not null default '' check(length(letter)<=1000),created_at timestamptz not null default now(),counted boolean not null default true,check(sender<>recipient));
create index on gift_private.gifts(sender,created_at);
create index on gift_private.gifts(recipient,created_at);
create table gift_private.held(item_id uuid primary key references public.item_instances(id),gift_id uuid not null references gift_private.gifts(id),is_box boolean not null default false);
create index on gift_private.held(gift_id);
create table gift_private.requests(owner_id uuid references public.profiles(id),request_id uuid,payload jsonb not null,gift_id uuid references gift_private.gifts(id),primary key(owner_id,request_id));
do $$declare t text;begin for t in select tablename from pg_tables where schemaname='gift_private' loop execute format('alter table gift_private.%I enable row level security',t);end loop;end$$;
revoke all on all tables in schema gift_private from public,anon,authenticated;
alter table mail_private.letters add column gift_id uuid references gift_private.gifts(id);
create function gift_private.guard_item() returns trigger language plpgsql security definer set search_path='' as $$begin if exists(select 1 from gift_private.held where item_id=old.id) then raise exception 'This item is sealed in a gift.';end if;if tg_op='DELETE' then return old;end if;return new;end$$;
revoke all on function gift_private.guard_item() from public,anon,authenticated;
create trigger gift_hold_guard before update or delete on public.item_instances for each row execute function gift_private.guard_item();
create function gift_private.lock_account(p_owner uuid) returns uuid language plpgsql set search_path='' as $$declare u uuid:=p_owner;begin
 if u is null or not exists(select 1 from public.profiles where id=u) then raise exception 'Sign in with your contractor account.' using errcode='28000';end if;
 perform pg_advisory_xact_lock(28131919);
 perform 1 from public.profiles where id in(select sender from gift_private.gifts where sender=u or recipient=u union select recipient from gift_private.gifts where sender=u or recipient=u union select u) order by id for update;
 if exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission') then raise exception 'Gifting is unavailable during deployment.';end if;return u;
end$$;
revoke all on function gift_private.lock_account(uuid) from public,anon,authenticated;
create function gift_private.lock_owner() returns uuid language sql set search_path='' as $$select gift_private.lock_account(auth.uid())$$;
revoke all on function gift_private.lock_owner() from public,anon,authenticated;
create function gift_private.consume_box(g uuid) returns void language plpgsql set search_path='' as $$declare i uuid;begin for i in delete from gift_private.held where gift_id=g and is_box returning item_id loop delete from public.item_instances where id=i;end loop;end$$;
revoke all on function gift_private.consume_box(uuid) from public,anon,authenticated;
create function gift_private.return_gift(g uuid,cancelled boolean default false) returns void language plpgsql set search_path='' as $$declare r gift_private.gifts;i uuid;slots integer;begin
 select * into r from gift_private.gifts where id=g for update;if r.status in('collected','returned','cancelled') then return;end if;
 if cancelled or r.status='preparing' then
  if r.fee+r.amount>0 then insert into public.chroma_wallets(account_id,balance) values(r.sender,r.fee+r.amount) on conflict(account_id) do update set balance=public.chroma_wallets.balance+excluded.balance;end if;
 else
  perform gift_private.consume_box(g);
  if r.amount>0 then insert into public.chroma_wallets(account_id,balance) values(r.sender,r.amount) on conflict(account_id) do update set balance=public.chroma_wallets.balance+excluded.balance;end if;
 end if;
 for i in delete from gift_private.held where gift_id=g returning item_id loop update public.item_instances set location='stash',inventory_position='home' where id=i;end loop;
 insert into inventory_private.settings(owner_id) values(r.sender) on conflict do nothing;select home_slots into slots from inventory_private.settings where owner_id=r.sender;perform housing_private.fit_home(r.sender,slots);update inventory_private.settings set revision=revision+1 where owner_id=r.sender;
 update gift_private.gifts set status=case when cancelled then 'cancelled' else 'returned' end,counted=not cancelled where id=g;
end$$;
revoke all on function gift_private.return_gift(uuid,boolean) from public,anon,authenticated;
create function gift_private.settle(u uuid) returns void language plpgsql set search_path='' as $$declare r gift_private.gifts;begin
 for r in select * from gift_private.gifts where (sender=u or recipient=u) and status not in('collected','returned','cancelled') order by id for update loop
 if r.route='courier' and r.status='preparing' and now()>=r.created_at+interval '1 minute' then perform gift_private.consume_box(r.id);update gift_private.gifts set status='in_transit' where id=r.id;r.status:='in_transit';end if;
 if social_private.blocked(r.sender,r.recipient) then perform gift_private.return_gift(r.id);elsif r.route='courier' and now()>=r.created_at+interval '5 minutes' then update gift_private.gifts set status='delivered' where id=r.id;end if;
 end loop;
end$$;
revoke all on function gift_private.settle(uuid) from public,anon,authenticated;
create function gift_private.snapshot() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=gift_private.lock_owner();begin perform gift_private.settle(u);return jsonb_build_object(
 'balance',coalesce((select balance from public.chroma_wallets where account_id=u),0),'revision',coalesce((select revision from inventory_private.settings where owner_id=u),0),
 'reset_at',(date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')+interval '1 day',
 'used_items',coalesce((select sum(units) from gift_private.gifts where sender=u and counted and (created_at at time zone 'UTC')::date=(now() at time zone 'UTC')::date),0),
 'used_chroma',coalesce((select sum(amount) from gift_private.gifts where sender=u and counted and (created_at at time zone 'UTC')::date=(now() at time zone 'UTC')::date),0),
 'settings',coalesce((select to_jsonb(s)-'owner_id' from gift_private.settings s where owner_id=u),'{"receive_friends":true,"receive_strangers":false}'::jsonb),'fees',(select to_jsonb(c)-'id' from gift_private.config c where id),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',d.name,'def',i.definition_id,'condition',i.condition,'weight',s.weight_lb)) from public.item_instances i join public.item_definitions d on d.id=i.definition_id join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=u and location='stash' and inventory_position in('home','person') and mission_run_id is null and not exists(select 1 from housing_private.rentals r where r.item_id=i.id)),'[]'::jsonb),
 'friends',coalesce((select jsonb_agg(jsonb_build_object('handle',p.username||'#'||p.discriminator)) from social_private.friends f join public.profiles p on p.id=case when f.a=u then f.b else f.a end where u in(f.a,f.b) and f.status='accepted' and not social_private.blocked(u,p.id)),'[]'::jsonb),
 'gifts',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'sent',g.sender=u,'handle',p.username||'#'||p.discriminator,'kind',g.kind,'route',g.route,'status',g.status,'amount',g.amount,'units',case when g.sender=u or g.status='collected' then g.units else null end,'weight',case when g.sender=u then g.weight else null end,'fee',case when g.sender=u then g.fee else null end,'letter',g.letter,'created_at',g.created_at,'cancel_until',case when g.route='courier' then g.created_at+interval '1 minute' else null end,'contents',case when g.sender=u or g.status='collected' then coalesce((select jsonb_agg(d.name) from gift_private.held h join public.item_instances i on i.id=h.item_id join public.item_definitions d on d.id=i.definition_id where h.gift_id=g.id and not h.is_box),'[]'::jsonb) else '[]'::jsonb end) order by g.created_at desc) from gift_private.gifts g join public.profiles p on p.id=case when g.sender=u then g.recipient else g.sender end where g.sender=u or g.recipient=u),'[]'::jsonb));end$$;
revoke all on function gift_private.snapshot() from public,anon;
grant execute on function gift_private.snapshot() to authenticated;
create function public.get_gifting_workspace() returns jsonb language sql security invoker set search_path='' as $$select gift_private.snapshot()$$;
revoke all on function public.get_gifting_workspace() from public,anon;grant execute on function public.get_gifting_workspace() to authenticated;
create function gift_private.quote(p_record jsonb) returns jsonb language plpgsql set search_path='' as $$declare u uuid:=auth.uid();v uuid;k text:=p_record->>'kind';route text:=p_record->>'route';ids uuid[];box uuid;w numeric:=0;n integer:=0;fee integer:=0;amt integer:=coalesce((p_record->>'amount')::integer,0);is_friend boolean;note text:='';cfg gift_private.config;setting gift_private.settings;begin
 perform gift_private.lock_owner();select id into v from public.profiles where username=split_part(p_record->>'handle','#',1) and discriminator=split_part(p_record->>'handle','#',2);
 if v is null or v=u then raise exception 'Recipient unavailable.';end if;
 perform 1 from public.profiles where id=v for update;perform pg_advisory_xact_lock(27203554);
 if social_private.blocked(u,v) then raise exception 'Recipient unavailable.';end if;
 is_friend:=social_private.friendly(u,v);select * into setting from gift_private.settings where owner_id=v;
 if (is_friend and not coalesce(setting.receive_friends,true)) or (not is_friend and not coalesce(setting.receive_strangers,false)) then raise exception 'This recipient is not accepting this type of gift.';end if;
 if p_record->>'letter_mode'='personal' then if not is_friend then raise exception 'Personal letters are available only between friends.';end if;note:=coalesce(p_record->>'letter','');
 elsif p_record->>'letter_mode'='template' then note:=case p_record->>'template' when 'hello' then 'A little something for your journey.' when 'luck' then 'Wishing you good luck out there!' when 'thanks' then 'Thank you for making this world a little brighter.' else null end;if note is null then raise exception 'Choose a prepared greeting.';end if;
 elsif p_record->>'letter_mode' is distinct from 'none' then raise exception 'Choose a letter option.';end if;
 if length(note)>1000 then raise exception 'Letters can contain up to 1,000 characters.';end if;
 select * into cfg from gift_private.config where id;
 if k='physical' then
  if route not in('courier','hand') or route is null then raise exception 'Choose a delivery route.';end if;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(p_record->'ids');n:=coalesce(cardinality(ids),0);box:=(p_record->>'box')::uuid;
  if n<1 or n>10 or n<>(select count(distinct x) from unnest(ids)x) or box=any(ids) then raise exception 'Choose 1 to 10 individual items, separate from the box.';end if;
  if (select count(*) from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.id=any(ids||array[box]) and i.owner_id=u and i.location='stash' and i.inventory_position in('home','person') and i.mission_run_id is null and not exists(select 1 from housing_private.rentals r where r.item_id=i.id))<>n+1 then raise exception 'Some selected items are unavailable or rented.';end if;
  if not exists(select 1 from public.item_instances where id=box and definition_id='gift-box') then raise exception 'Choose an owned Gift Box.';end if;
  select sum(s.weight_lb) into w from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.id=any(ids);
  fee:=case route when 'courier' then cfg.base_fee+ceil(w*cfg.per_lb)::integer else cfg.hand_fee end;amt:=0;
 elsif k='chroma' then route:='digital';if amt<1 or amt>5000 then raise exception 'Choose 1 to 5,000 Chroma.';end if;
 else raise exception 'Choose items or Chroma.';end if;
 if n+coalesce((select sum(units) from gift_private.gifts where sender=u and counted and (created_at at time zone 'UTC')::date=(now() at time zone 'UTC')::date),0)>10 or amt+coalesce((select sum(amount) from gift_private.gifts where sender=u and counted and (created_at at time zone 'UTC')::date=(now() at time zone 'UTC')::date),0)>5000 then raise exception 'This gift exceeds your daily gifting allowance.';end if;
 if coalesce((select balance from public.chroma_wallets where account_id=u),0)<fee+amt then raise exception 'Not enough Chroma for this gift and its delivery.';end if;
 return jsonb_build_object('recipient',v,'handle',p_record->>'handle','friend',is_friend,'kind',k,'route',route,'units',n,'weight',w,'fee',fee,'amount',amt,'letter',note,'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'def',i.definition_id,'name',d.name,'condition',i.condition,'position',i.inventory_position) order by i.id) from public.item_instances i join public.item_definitions d on d.id=i.definition_id where i.id=any(ids||array[box])),'[]'::jsonb),'revision',coalesce((select revision from inventory_private.settings where owner_id=u),0));end$$;
revoke all on function gift_private.quote(jsonb) from public,anon,authenticated;
create function gift_private.review(p_record jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return gift_private.quote(p_record);end$$;
revoke all on function gift_private.review(jsonb) from public,anon;grant execute on function gift_private.review(jsonb) to authenticated;
create function public.quote_player_gift(p_record jsonb) returns jsonb language sql security invoker set search_path='' as $$select gift_private.review(p_record)$$;
revoke all on function public.quote_player_gift(jsonb) from public,anon;grant execute on function public.quote_player_gift(jsonb) to authenticated;
create function gift_private.change(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=gift_private.lock_owner();q jsonb;g gift_private.gifts;prior jsonb;gid uuid;v uuid;box uuid;i uuid;begin
 if p_request is null or p_action is null then raise exception 'Missing request.';end if;
 select payload into prior from gift_private.requests where owner_id=u and request_id=p_request;if found then if prior<>p_action then raise exception 'Request already used for another gift action.';end if;return gift_private.snapshot();end if;
 perform gift_private.settle(u);
 if p_action->>'type'='settings' then
  insert into gift_private.settings values(u,(p_action->>'receive_friends')::boolean,(p_action->>'receive_strangers')::boolean) on conflict(owner_id) do update set receive_friends=excluded.receive_friends,receive_strangers=excluded.receive_strangers;
 elsif p_action->>'type'='send' then
  q:=gift_private.quote(p_action->'record');v:=(q->>'recipient')::uuid;
  if q is distinct from p_action->'quote' then raise exception 'Gift details or Inventory changed. Review the gift again.' using errcode='40001';end if;
  gid:=gen_random_uuid();
  insert into gift_private.gifts(id,sender,recipient,kind,route,status,amount,units,weight,fee,letter) values(gid,u,v,q->>'kind',q->>'route',case when q->>'kind'='chroma' then 'delivered' else 'preparing' end,(q->>'amount')::integer,(q->>'units')::integer,(q->>'weight')::numeric,(q->>'fee')::integer,q->>'letter');
  if (q->>'amount')::integer+(q->>'fee')::integer>0 then update public.chroma_wallets set balance=balance-(q->>'amount')::integer-(q->>'fee')::integer where account_id=u;end if;
  if q->>'kind'='physical' then
   box:=(p_action->'record'->>'box')::uuid;
   for i in select value::uuid from jsonb_array_elements_text(p_action->'record'->'ids') union all select box loop
    update public.item_instances set location='gift' where id=i;
    insert into gift_private.held values(i,gid,i=box);
   end loop;
   insert into inventory_private.settings(owner_id,revision) values(u,1) on conflict(owner_id) do update set revision=inventory_private.settings.revision+1;
  end if;
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,gift_id) select v,'gift:'||gid,p.username||'#'||p.discriminator,case when q->>'kind'='physical' then 'A sealed gift is on its way' else 'A digital gift for you' end,coalesce(nullif(q->>'letter',''),'A gift for your journey. No reply is required.'),'gift',gid from public.profiles p where p.id=u;
 else
  select * into g from gift_private.gifts where id=(p_action->>'gift')::uuid and u in(sender,recipient) for update;if not found then raise exception 'Gift unavailable.';end if;gid:=g.id;
  perform pg_advisory_xact_lock(27203554);
  if p_action->>'type'='cancel' then if g.sender<>u or g.status<>'preparing' then raise exception 'This gift has already dispatched and cannot be cancelled.';end if;perform gift_private.return_gift(g.id,true);
  elsif p_action->>'type'='return' then if g.recipient<>u or g.status not in('preparing','in_transit','delivered') then raise exception 'Only an untouched gift can be returned.';end if;perform gift_private.return_gift(g.id);
  elsif p_action->>'type'='claim' then
   if g.recipient<>u or g.kind<>'chroma' or g.status<>'delivered' then raise exception 'Only an unclaimed digital gift can be received on the website.';end if;
   if social_private.blocked(g.sender,g.recipient) then raise exception 'This gift is being returned.';end if;
   insert into public.chroma_wallets(account_id,balance) values(u,g.amount) on conflict(account_id) do update set balance=public.chroma_wallets.balance+excluded.balance;
   update gift_private.gifts set status='collected' where id=g.id;
  else raise exception 'Unsupported gift action.';end if;
 end if;
 insert into gift_private.requests values(u,p_request,p_action,gid);return gift_private.snapshot();end$$;
revoke all on function gift_private.change(uuid,jsonb) from public,anon;grant execute on function gift_private.change(uuid,jsonb) to authenticated;
create function public.change_gifting_workspace(p_request uuid,p_action jsonb) returns jsonb language sql security invoker set search_path='' as $$select gift_private.change(p_request,p_action)$$;
revoke all on function public.change_gifting_workspace(uuid,jsonb) from public,anon;grant execute on function public.change_gifting_workspace(uuid,jsonb) to authenticated;
create function public.deliver_player_gift(p_sender uuid,p_gift uuid,p_mode text) returns void language plpgsql security definer set search_path='' as $$declare g gift_private.gifts;begin
 perform gift_private.lock_account(p_sender);perform gift_private.settle(p_sender);select * into g from gift_private.gifts where id=p_gift and sender=p_sender and kind='physical' and route='hand' for update;
 if not found then raise exception 'Hand-delivery gift unavailable.';end if;
 perform pg_advisory_xact_lock(27203554);if social_private.blocked(g.sender,g.recipient) then raise exception 'Recipient unavailable.';end if;
 if p_mode='pickup' then
  if g.status='in_transit' then return;end if;if g.status<>'preparing' then raise exception 'Package unavailable for pickup.';end if;perform gift_private.consume_box(g.id);update gift_private.gifts set status='in_transit' where id=g.id;
 elsif p_mode in('home','player') then
  if g.status='delivered' then return;end if;if g.status<>'in_transit' then raise exception 'Pick up the sealed package first.';end if;
  if p_mode='home' and not exists(select 1 from housing_private.invites i join public.home_assignments a on a.account_id=i.owner_id and a.unit_id=i.unit_id where i.owner_id=g.recipient and i.guest_id=g.sender) then raise exception 'A current home invitation is required.';end if;
  update gift_private.gifts set status='delivered' where id=g.id;
 else raise exception 'Unknown delivery interaction.';end if;end$$;
revoke all on function public.deliver_player_gift(uuid,uuid,text) from public,anon,authenticated;grant execute on function public.deliver_player_gift(uuid,uuid,text) to service_role;
create function public.collect_player_gift(p_recipient uuid,p_gift uuid) returns void language plpgsql security definer set search_path='' as $$declare g gift_private.gifts;i uuid;lim integer;begin
 perform gift_private.lock_account(p_recipient);perform gift_private.settle(p_recipient);select * into g from gift_private.gifts where id=p_gift and recipient=p_recipient and kind='physical' for update;
 if not found then raise exception 'Gift unavailable.';end if;if g.status='collected' then return;end if;if g.status<>'delivered' then raise exception 'Gift has not arrived.';end if;
 perform pg_advisory_xact_lock(27203554);if social_private.blocked(g.sender,g.recipient) then raise exception 'Gift is being returned.';end if;
 if not exists(select 1 from public.home_assignments where account_id=p_recipient) then raise exception 'A home is needed to collect this package.';end if;
 perform gift_private.consume_box(g.id);
 for i in delete from gift_private.held where gift_id=g.id returning item_id loop update public.item_instances set owner_id=p_recipient,location='stash',inventory_position='home',source='player-gift:'||g.id where id=i;end loop;
 select coalesce((select home_slots from inventory_private.settings where owner_id=p_recipient),25) into lim;
 if inventory_private.used_slots(p_recipient,'home')>lim then raise exception 'Home storage is full. The sealed package is safe.';end if;
 update gift_private.gifts set status='collected' where id=g.id;insert into inventory_private.settings(owner_id,revision) values(p_recipient,1) on conflict(owner_id) do update set revision=inventory_private.settings.revision+1;end$$;
revoke all on function public.collect_player_gift(uuid,uuid) from public,anon,authenticated;grant execute on function public.collect_player_gift(uuid,uuid) to service_role;
-- Keep outstanding gift notices in Mail; controls link to the Gifts view.
create function gift_private.guard_archive() returns trigger language plpgsql security definer set search_path='' as $$begin if new.archived_at is not null and old.archived_at is null and new.gift_id is not null and exists(select 1 from gift_private.gifts where id=new.gift_id and status not in('collected','returned','cancelled')) then raise exception 'Complete or return this gift before archiving its notice.';end if;return new;end$$;
revoke all on function gift_private.guard_archive() from public,anon,authenticated;
create trigger gift_archive_guard before update on mail_private.letters for each row execute function gift_private.guard_archive();
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
 select l.id,l.order_id,l.gift_id,(select status from gift_private.gifts where id=l.gift_id) as gift_status,l.sender,l.subject,l.body,l.kind,l.created_at,l.read_at,l.archived_at,l.expires_at,
 case when l.order_id is null then null else jsonb_build_object('status',case when d.collected_at is not null or i.id is not null and i.location<>'delivery' then 'collected' when d.status='delivered' then 'delivered' when clock_timestamp()>=l.created_at+interval '1 minute' then 'in_transit' else 'preparing' end,'eta',l.created_at+interval '5 minutes','address',coalesce(h.address,d.address)) end as delivery,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'label',a.label,'amount',a.amount,'claimed_at',a.claimed_at)) from mail_private.attachments a where a.letter_id=l.id),'[]'::jsonb) as attachments
 from mail_private.letters l left join public.order_deliveries d on d.order_id=l.order_id left join public.purchase_orders o on o.id=l.order_id left join public.item_instances i on i.id=o.item_id
 left join public.home_assignments ha on ha.account_id=u left join public.housing_units h on h.unit_id=ha.unit_id
 where l.owner_id=u
 )x),'[]'::jsonb),'coupons',coalesce((select jsonb_agg(jsonb_build_object('label',label,'quantity',quantity)) from mail_private.coupons where owner_id=u),'[]'::jsonb));
end;$$;
