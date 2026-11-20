-- Housing workspace. Existing assignments remain free; no background charges are introduced.
create schema housing_private;
revoke all on schema housing_private from public,anon;
grant usage on schema housing_private to authenticated;
alter table public.housing_units add column unique_home boolean not null default false,
 add column title text not null default 'Constellation apartment',
 add column description text not null default 'A familiar place to return to.',
 add column icon text not null default 'window',
 add column slots integer not null default 25 check(slots>0),
 add column price integer not null default 0 check(price>=0),
 add column available_from timestamptz, add column available_until timestamptz;
create table housing_private.discoveries(owner_id uuid references public.profiles(id),unit_id text references public.housing_units(unit_id),found_at timestamptz not null default now(),primary key(owner_id,unit_id));
create table housing_private.departures(unit_id text primary key references public.housing_units(unit_id),owner_id uuid not null references public.profiles(id),left_at timestamptz not null default now(),release_at timestamptz not null);
create index on housing_private.departures(owner_id);
create table housing_private.contracts(owner_id uuid primary key references public.profiles(id),unit_id text not null references public.housing_units(unit_id),debt integer not null check(debt>=0));
create table housing_private.storage(owner_id uuid primary key references public.profiles(id),due_at timestamptz not null,fee integer not null check(fee>0));
create table housing_private.config(id boolean primary key default true check(id),storage_fee integer not null check(storage_fee>0));
insert into housing_private.config values(true,20);
create table housing_private.values(definition_id text primary key references public.item_definitions(id),value integer not null check(value>0));
insert into housing_private.values values('flux-rifle',80),('starter-backpack',20),('meal-pack',8),('focus-01',10),('flux-service-kit',15);
create table housing_private.rentals(item_id uuid primary key references public.item_instances(id) on delete cascade);
create table housing_private.holds(item_id uuid primary key references public.item_instances(id),owner_id uuid not null references public.profiles(id),kind text not null check(kind in ('collateral','storage')));
create index on housing_private.holds(owner_id,kind);
create table housing_private.requests(owner_id uuid references public.profiles(id),request_id uuid,payload jsonb not null,primary key(owner_id,request_id));
create table housing_private.invites(owner_id uuid references public.profiles(id),guest_id uuid references public.profiles(id),unit_id text references public.housing_units(unit_id),primary key(owner_id,guest_id),check(owner_id<>guest_id));
do $$declare t text;begin for t in select tablename from pg_tables where schemaname='housing_private' loop execute format('alter table housing_private.%I enable row level security',t);end loop;end$$;
revoke all on all tables in schema housing_private from public,anon,authenticated;
alter table public.item_instances drop constraint item_instances_location_check;
alter table public.item_instances add constraint item_instances_location_check check(location in ('stash','delivery','mission','housing'));
-- Protect held property across old game/shop entrypoints as well as the new website.
create function housing_private.guard_item() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from housing_private.holds where item_id=old.id) then raise exception 'Item is held in Housing. Release it there first.';end if;
 if tg_op='DELETE' and old.location<>'mission' and exists(select 1 from housing_private.rentals where item_id=old.id) then raise exception 'Rental equipment cannot be sold or gifted.';end if;
 if tg_op='UPDATE' and new.owner_id<>old.owner_id and exists(select 1 from housing_private.rentals where item_id=old.id) then raise exception 'Rental equipment cannot be gifted.';end if;
 if tg_op='DELETE' then return old;end if;return new;end$$;
revoke all on function housing_private.guard_item() from public,anon,authenticated;
create trigger housing_guard before update or delete on public.item_instances for each row execute function housing_private.guard_item();
-- Onboarding bag is owned once. Subsequent free bags are recorded rentals.
create table housing_private.bag_grants(owner_id uuid primary key references public.profiles(id));
alter table housing_private.bag_grants enable row level security;
revoke all on housing_private.bag_grants from public,anon,authenticated;
insert into housing_private.bag_grants select distinct owner_id from public.item_instances where definition_id='starter-backpack';
create function housing_private.mark_bag() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.source='rental' then insert into housing_private.rentals values(new.id);end if;
 if new.source='starter-backpack' then
  insert into housing_private.bag_grants values(new.owner_id) on conflict do nothing;
  if not found then insert into housing_private.rentals values(new.id);end if;
 end if;return new;end$$;
revoke all on function housing_private.mark_bag() from public,anon,authenticated;
create trigger housing_bag after insert on public.item_instances for each row execute function housing_private.mark_bag();

create function housing_private.check_owner() returns uuid language plpgsql security definer set search_path='' as $$declare u uuid:=auth.uid();begin
 if u is null then raise exception 'Sign in to view Housing.' using errcode='28000';end if;
 perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
 if exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission') then raise exception 'Housing is locked during deployment.';end if;return u;end$$;
revoke all on function housing_private.check_owner() from public,anon,authenticated;
create function housing_private.storage_due(p_owner uuid) returns bigint language sql stable set search_path='' as $$
 select case when now()>=due_at then (1+floor(extract(epoch from(now()-due_at))/1209600))::bigint*fee else 0 end from housing_private.storage where owner_id=p_owner
$$;
revoke all on function housing_private.storage_due(uuid) from public,anon,authenticated;
create function housing_private.snapshot() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=housing_private.check_owner();begin return jsonb_build_object(
 'revision',coalesce((select revision from inventory_private.settings where owner_id=u),0),
 'balance',coalesce((select balance from public.chroma_wallets where account_id=u),0),
 'home',(select to_jsonb(h)||jsonb_build_object('debt',coalesce(c.debt,0)) from public.home_assignments a join public.housing_units h using(unit_id) left join housing_private.contracts c on c.owner_id=a.account_id where a.account_id=u),
 'offers',coalesce((select jsonb_agg(to_jsonb(h) order by h.unique_home,h.title) from public.housing_units h where not exists(select 1 from public.home_assignments a where a.unit_id=h.unit_id) and not exists(select 1 from housing_private.departures d where d.unit_id=h.unit_id and d.release_at>now()) and (not h.unique_home or exists(select 1 from housing_private.discoveries d where d.unit_id=h.unit_id and d.owner_id=u)) and (h.available_from is null or h.available_from<=now()) and (h.available_until is null or h.available_until>now())),'[]'::jsonb),
 'reclaim',coalesce((select jsonb_agg(to_jsonb(h)||jsonb_build_object('left_at',d.left_at,'grace_until',d.left_at+interval '30 minutes','priority_until',d.left_at+interval '24 hours 30 minutes')) from housing_private.departures d join public.housing_units h using(unit_id) where d.owner_id=u and d.release_at>now()),'[]'::jsonb),
 'storage',(select to_jsonb(s)||jsonb_build_object('due',housing_private.storage_due(u),'locked',housing_private.storage_due(u)>0) from housing_private.storage s where owner_id=u),
 'storage_fee',(select storage_fee from housing_private.config where id),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',d.name,'condition',i.condition,'position',i.inventory_position,'kind',coalesce(h.kind,'available'),'value',case when r.item_id is null then coalesce(floor(v.value*i.condition/100.0),0) else 0 end,'rental',r.item_id is not null) order by i.created_at,i.id) from public.item_instances i join public.item_definitions d on d.id=i.definition_id left join housing_private.holds h on h.item_id=i.id left join housing_private.values v on v.definition_id=i.definition_id left join housing_private.rentals r on r.item_id=i.id where i.owner_id=u and (i.location='housing' or (i.location='stash' and i.inventory_position in ('home','person')))),'[]'::jsonb),
 'invites',coalesce((select jsonb_agg(jsonb_build_object('guest_id',p.id,'handle',p.username||'#'||p.discriminator)) from housing_private.invites i join public.profiles p on p.id=i.guest_id join public.home_assignments a on a.account_id=i.owner_id and a.unit_id=i.unit_id where i.owner_id=u),'[]'::jsonb),
 'visiting',coalesce((select jsonb_agg(jsonb_build_object('title',h.title,'address',h.address,'unit_id',h.unit_id)) from housing_private.invites i join public.home_assignments a on a.account_id=i.owner_id and a.unit_id=i.unit_id join public.housing_units h on h.unit_id=i.unit_id where i.guest_id=u),'[]'::jsonb)
 );end$$;
revoke all on function housing_private.snapshot() from public,anon;
grant execute on function housing_private.snapshot() to authenticated;
create function public.get_housing_workspace() returns jsonb language sql security invoker set search_path='' as $$select housing_private.snapshot()$$;
revoke all on function public.get_housing_workspace() from public,anon;
grant execute on function public.get_housing_workspace() to authenticated;

-- Trusted game bridge: entering, investigating or an NPC transfer records discovery.
create function public.record_housing_discovery(p_owner uuid,p_unit text) returns void language plpgsql security definer set search_path='' as $$begin
 perform 1 from public.profiles where id=p_owner for update;if not found then raise exception 'Unknown contractor.';end if;
 perform 1 from public.housing_units h where unit_id=p_unit and unique_home and (available_from is null or available_from<=now()) and (available_until is null or available_until>now()) for update;
 if not found or exists(select 1 from public.home_assignments where unit_id=p_unit) or exists(select 1 from housing_private.departures where unit_id=p_unit and release_at>now()) then raise exception 'Location unavailable.';end if;
 insert into housing_private.discoveries values(p_owner,p_unit,now()) on conflict do nothing;
end$$;
revoke all on function public.record_housing_discovery(uuid,text) from public,anon,authenticated;
grant execute on function public.record_housing_discovery(uuid,text) to service_role;
-- Move overflow by actual stack usage. Item UUIDs and condition never change.
create function housing_private.fit_home(p_owner uuid,p_slots integer) returns void language plpgsql set search_path='' as $$declare i uuid;begin
 while inventory_private.used_slots(p_owner,'home')>p_slots loop
  select id into i from public.item_instances where owner_id=p_owner and location='stash' and inventory_position='home' order by created_at desc,id desc limit 1;
  update public.item_instances set location='housing' where id=i;
  insert into housing_private.holds values(i,p_owner,'storage');
 end loop;
 if exists(select 1 from housing_private.holds where owner_id=p_owner and kind='storage') then
  insert into housing_private.storage select p_owner,now()+interval '14 days',storage_fee from housing_private.config where id on conflict do nothing;
 end if;
end$$;
revoke all on function housing_private.fit_home(uuid,integer) from public,anon,authenticated;
create function housing_private.change(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=housing_private.check_owner();op text:=p_action->>'type';prior jsonb;target public.housing_units;old_unit text;ids uuid[];i uuid;value_total bigint;cost bigint:=0;debt integer;lim integer;guest uuid;due bigint;periods bigint;
begin
 if p_request is null or p_action is null then raise exception 'Missing request.';end if;
 select payload into prior from housing_private.requests where owner_id=u and request_id=p_request;
 if found then if prior<>p_action then raise exception 'Request already used for different changes.';end if;return housing_private.snapshot();end if;
 insert into inventory_private.settings(owner_id) values(u) on conflict do nothing;
 if (p_action->>'revision')::bigint is distinct from (select revision from inventory_private.settings where owner_id=u) then raise exception 'Housing or Inventory changed. Refresh and review again.' using errcode='40001';end if;
 if op in ('move','reclaim') then
  -- Global short lock orders cross-unit moves and claims without deadlocks.
  perform pg_advisory_xact_lock(73421841);
  select * into target from public.housing_units where unit_id=p_action->>'unit' for update;
  if not found then raise exception 'Home unavailable.';end if;
  if exists(select 1 from public.home_assignments where unit_id=target.unit_id) then raise exception 'Home unavailable.';end if;
  if op='reclaim' then
   if not exists(select 1 from housing_private.departures where unit_id=target.unit_id and owner_id=u and release_at>now()) then raise exception 'Reclaim period ended.';end if;
  else
   if exists(select 1 from housing_private.departures where unit_id=target.unit_id and release_at>now()) or (target.unique_home and not exists(select 1 from housing_private.discoveries where unit_id=target.unit_id and owner_id=u)) or (target.available_from is not null and target.available_from>now()) or (target.available_until is not null and target.available_until<=now()) then raise exception 'Home unavailable.';end if;
  end if;
  if coalesce((select c.debt from housing_private.contracts c where owner_id=u),0)>0 then raise exception 'Settle your current collateral agreement before moving.';end if;
  if (p_action->>'price')::integer is distinct from target.price or (p_action->>'storage_fee')::integer is distinct from (select storage_fee from housing_private.config where id) then raise exception 'Terms changed. Refresh and review.';end if;
  if op='move' and p_action->>'payment'='collateral' and target.price>0 then
   select array_agg(value::uuid) into ids from jsonb_array_elements_text(p_action->'ids');
   if coalesce(cardinality(ids),0)=0 or cardinality(ids)<>(select count(distinct x) from unnest(ids)x) then raise exception 'Choose distinct owned items.';end if;
   if (select count(*) from public.item_instances where id=any(ids) and owner_id=u and location='stash' and inventory_position in ('home','person') and mission_run_id is null)<>cardinality(ids) or exists(select 1 from housing_private.rentals where item_id=any(ids)) then raise exception 'Only available owned items can be pledged.';end if;
   select coalesce(sum(floor(v.value*i.condition/100.0)),0) into value_total from public.item_instances i join housing_private.values v on v.definition_id=i.definition_id where i.id=any(ids);
   if value_total<ceil(target.price/2.0) then raise exception 'Collateral must cover at least 50 percent of the price.';end if;
   update public.item_instances set location='housing' where id=any(ids);
   insert into housing_private.holds select x,u,'collateral' from unnest(ids)x;
   debt:=target.price;
  else cost:=case when op='reclaim' then 0 else target.price end;debt:=0;end if;
  select unit_id into old_unit from public.home_assignments where account_id=u;
  if old_unit is not null then
   insert into housing_private.departures values(old_unit,u,now(),now()+interval '30 minutes'+interval '24 hours'+random()*interval '48 hours') on conflict(unit_id) do update set owner_id=u,left_at=excluded.left_at,release_at=excluded.release_at;
   delete from housing_private.discoveries where unit_id=old_unit;
  end if;
  delete from housing_private.departures where unit_id=target.unit_id;
  delete from housing_private.discoveries where unit_id=target.unit_id and owner_id<>u;
  delete from housing_private.invites where owner_id=u;
  insert into public.home_assignments(account_id,unit_id) values(u,target.unit_id) on conflict(account_id) do update set unit_id=excluded.unit_id,assigned_at=now();
  update public.home_decorations set unit_id=target.unit_id where owner_id=u;
  insert into housing_private.contracts values(u,target.unit_id,debt) on conflict(owner_id) do update set unit_id=excluded.unit_id,debt=excluded.debt;
  update inventory_private.settings set home_slots=target.slots where owner_id=u;
  perform housing_private.fit_home(u,target.slots);
 elsif op='settle' then
  select c.debt into cost from housing_private.contracts c where owner_id=u for update;
  if coalesce(cost,0)<=0 then raise exception 'No collateral payment is outstanding.';end if;
  if (p_action->>'price')::bigint is distinct from cost then raise exception 'Payment changed. Refresh.';end if;
  for i in delete from housing_private.holds where owner_id=u and kind='collateral' returning item_id loop update public.item_instances set location='stash',inventory_position='home' where id=i;end loop;
  update housing_private.contracts set debt=0 where owner_id=u;
  select home_slots into lim from inventory_private.settings where owner_id=u;
  perform housing_private.fit_home(u,lim);
 elsif op='pay_storage' then
  select housing_private.storage_due(u) into cost;
  if coalesce(cost,0)<=0 then raise exception 'No storage bill is due.';end if;
  if (p_action->>'price')::bigint is distinct from cost then raise exception 'Storage bill changed. Refresh.';end if;
  update housing_private.storage set due_at=due_at+((cost/fee)::integer*interval '14 days') where owner_id=u;
 elsif op in ('store','withdraw') then
  if coalesce(housing_private.storage_due(u),0)>0 then raise exception 'Storage is locked until the outstanding bill is paid.';end if;
  if (p_action->>'storage_fee')::integer is distinct from (select storage_fee from housing_private.config where id) then raise exception 'Storage terms changed. Refresh.';end if;
  i:=(p_action->>'id')::uuid;
  if op='store' then
   perform 1 from public.item_instances where id=i and owner_id=u and location='stash' and inventory_position='home' and mission_run_id is null;
   if not found then raise exception 'Item unavailable.';end if;
   update public.item_instances set location='housing' where id=i;insert into housing_private.holds values(i,u,'storage');
   insert into housing_private.storage select u,now()+interval '14 days',storage_fee from housing_private.config where id on conflict do nothing;
  else
   delete from housing_private.holds where item_id=i and owner_id=u and kind='storage';if not found then raise exception 'Stored item unavailable.';end if;
   update public.item_instances set location='stash',inventory_position='home' where id=i;
   select home_slots into lim from inventory_private.settings where owner_id=u;
   if inventory_private.used_slots(u,'home')>lim then raise exception 'Your home does not have enough room.';end if;
  end if;
  if not exists(select 1 from housing_private.holds where owner_id=u and kind='storage') then delete from housing_private.storage where owner_id=u;end if;
 elsif op='invite' then
  select id into guest from public.profiles where username=split_part(p_action->>'handle','#',1) and discriminator=split_part(p_action->>'handle','#',2);
  if guest is null or guest=u then raise exception 'Use another contractor’s exact name and six-digit tag.';end if;
  select unit_id into old_unit from public.home_assignments where account_id=u;if old_unit is null then raise exception 'A home is required.';end if;
  insert into housing_private.invites values(u,guest,old_unit) on conflict(owner_id,guest_id) do update set unit_id=excluded.unit_id;
 elsif op='revoke' then delete from housing_private.invites where owner_id=u and guest_id=(p_action->>'guest')::uuid;
 else raise exception 'Unsupported Housing action.';end if;
 if cost>0 then
  update public.chroma_wallets set balance=balance-cost where account_id=u and balance>=cost;
  if not found then raise exception 'Not enough Chroma. Your items and home have not changed.';end if;
 end if;
 update inventory_private.settings set revision=revision+1 where owner_id=u;
 insert into housing_private.requests values(u,p_request,p_action);
 return housing_private.snapshot();
end$$;
revoke all on function housing_private.change(uuid,jsonb) from public,anon;
grant execute on function housing_private.change(uuid,jsonb) to authenticated;
create function public.change_housing_workspace(p_request uuid,p_action jsonb) returns jsonb language sql security invoker set search_path='' as $$select housing_private.change(p_request,p_action)$$;
revoke all on function public.change_housing_workspace(uuid,jsonb) from public,anon;
grant execute on function public.change_housing_workspace(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';

create or replace function public.ensure_constellation_home(p_account_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare chosen text;
begin
 -- Serializes this account's allocation, including retries after a lost response.
 perform 1 from public.profiles where id=p_account_id for update;
 if not found then raise exception 'Registered account required.'; end if;
 select unit_id into chosen from public.home_assignments where account_id=p_account_id;
 if chosen is null then
  -- Unit row locks and unique constraints prevent two owners sharing a unit.
  select u.unit_id into chosen from public.housing_units u
   where not u.unique_home and not exists(select 1 from housing_private.departures d where d.unit_id=u.unit_id and d.release_at>now()) and not exists(select 1 from public.home_assignments a where a.unit_id=u.unit_id)
   order by u.unit_id for update of u skip locked limit 1;
  if chosen is null then raise exception 'Constellation test corridor is full. No apartment was assigned.'; end if;
  insert into public.home_assignments(account_id,unit_id) values(p_account_id,chosen);
 end if;
 insert into public.home_decorations(owner_id,unit_id) values(p_account_id,chosen)
 on conflict(owner_id) do nothing;
 return public.constellation_home_record(p_account_id);
end $$;
