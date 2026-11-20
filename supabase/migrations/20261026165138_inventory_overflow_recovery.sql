-- Existing game saves may exceed the new slot capacity. Permit cleanup without permitting additional overflow.
create function inventory_private.used_slots(p_owner uuid,p_position text) returns integer language sql stable set search_path='' as $$
 select coalesce(sum(ceil(c::numeric/case when stackable then 100 else 1 end)),0)::integer from
 (select i.definition_id,i.condition,coalesce(s.stackable,false) stackable,count(*) c from public.item_instances i left join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=p_owner and i.inventory_position=p_position and i.location='stash' group by i.definition_id,i.condition,s.stackable) groups;
$$;
revoke all on function inventory_private.used_slots(uuid,text) from public,anon,authenticated;
create or replace function inventory_private.change(p_request_id uuid,p_expected_revision bigint,p_action jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); prior jsonb; rev bigint; op text:=p_action->>'type'; source_pos text; dest text; ids uuid[]; item public.item_instances; spec inventory_private.specs; old_id uuid; slot_count integer; home_max integer; bag_max integer; n integer; before_home integer; before_person integer;
begin
 if u is null then raise exception 'Sign in to change Inventory.' using errcode='28000';end if;
 if p_request_id is null or p_expected_revision is null or p_action is null then raise exception 'Missing request identifiers.';end if;
 -- Same first lock as reserve_mission_loadout/reserve_mission_weapon.
 perform 1 from public.profiles where id=u for update;
 if not found then raise exception 'Create your contractor profile first.';end if;
 select payload into prior from inventory_private.requests where owner_id=u and request_id=p_request_id;
 if found then
  if prior<>p_action then raise exception 'Request identifier was already used for different changes.';end if;
  return inventory_private.snapshot();
 end if;
 insert into inventory_private.settings(owner_id) values(u) on conflict do nothing;
 select revision,home_slots into rev,home_max from inventory_private.settings where owner_id=u for update;
 if rev<>p_expected_revision then raise exception 'Inventory changed. Refresh and review before trying again.' using errcode='40001';end if;
 if exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission') then raise exception 'Inventory changes are locked during deployment.';end if;
 before_home:=inventory_private.used_slots(u,'home');before_person:=inventory_private.used_slots(u,'person');
 if op='claim_bag' then
  if exists(select 1 from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=u and s.equip_slot='bag' and i.location in ('stash','mission','delivery')) then raise exception 'You already own a backpack. Equip it from storage.';end if;
  insert into public.item_instances(owner_id,definition_id,condition,location,source,inventory_position) values(u,'starter-backpack',100,'stash','starter-backpack','bag');
 elsif op='transfer' then
  source_pos:=p_action->>'from';dest:=case source_pos when 'home' then 'person' when 'person' then 'home' end;
  if dest is null or jsonb_typeof(p_action->'ids') is distinct from 'array' then raise exception 'Invalid transfer.';end if;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(p_action->'ids');
  n:=coalesce(cardinality(ids),0);
  if n<1 or n>100 or n<>(select count(distinct v) from unnest(ids) v) then raise exception 'Choose 1 to 100 unique items.';end if;
  perform 1 from public.item_instances where owner_id=u and id=any(ids) order by id for update;
  if (select count(*) from public.item_instances where owner_id=u and id=any(ids) and location='stash' and inventory_position=source_pos and mission_run_id is null)<>n then raise exception 'Some items are unavailable or have already moved.';end if;
  if (select count(distinct (definition_id,condition)) from public.item_instances where owner_id=u and id=any(ids))<>1 then raise exception 'Transfer matching items together.';end if;
  update public.item_instances set inventory_position=dest where owner_id=u and id=any(ids);
 elsif op='equip' then
  source_pos:=p_action->>'from';
  if source_pos not in ('home','person') or source_pos is null then raise exception 'Invalid equipment source.';end if;
  select * into item from public.item_instances where id=(p_action->>'id')::uuid and owner_id=u and inventory_position=source_pos and location='stash' and mission_run_id is null for update;
  if not found then raise exception 'Item is not available to equip.';end if;
  select * into spec from inventory_private.specs where definition_id=item.definition_id;
  if spec.equip_slot is null then raise exception 'This item has no equipment position.';end if;
  select id into old_id from public.item_instances where owner_id=u and inventory_position=spec.equip_slot and location='stash' for update;
  if old_id is not null then update public.item_instances set inventory_position=source_pos where id=old_id;end if;
  update public.item_instances set inventory_position=spec.equip_slot where id=item.id;
 elsif op='unequip' then
  dest:=p_action->>'slot';if dest is null or dest not in ('primary','backup','shield','bag') then raise exception 'Invalid equipment position.';end if;
  if dest='bag' and exists(select 1 from public.item_instances where owner_id=u and inventory_position='person' and location='stash') then raise exception 'Transfer backpack contents home before removing the backpack.';end if;
  update public.item_instances set inventory_position='home' where owner_id=u and inventory_position=dest and location='stash' and mission_run_id is null;
  if not found then raise exception 'This equipment position is empty.';end if;
 else raise exception 'Unsupported Inventory action.';
 end if;
 select coalesce(s.bag_slots,0) into bag_max from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=u and i.inventory_position='bag' and i.location='stash';
 bag_max:=coalesce(bag_max,0);
 for dest in select unnest(array['home','person']) loop
  select coalesce(sum(ceil(c::numeric/case when stackable then 100 else 1 end)),0) into slot_count from
   (select i.definition_id,i.condition,coalesce(s.stackable,false) stackable,count(*) c from public.item_instances i left join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=u and i.inventory_position=dest and i.location='stash' group by i.definition_id,i.condition,s.stackable) groups;
  if slot_count>(case when dest='home' then home_max else bag_max end) and slot_count>(case when dest='home' then before_home else before_person end) then raise exception 'Not enough % storage slots.',dest;end if;
 end loop;
 insert into inventory_private.requests(owner_id,request_id,payload) values(u,p_request_id,p_action);
 update inventory_private.settings set revision=revision+1 where owner_id=u;
 return inventory_private.snapshot();
end $$;
