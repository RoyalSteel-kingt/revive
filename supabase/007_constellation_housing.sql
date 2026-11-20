-- Additive housing proof. Run after your existing 001-006 migrations.
-- Four physical units match the supplied Unity corridor. No rent or billing.
begin;
create table if not exists public.housing_units (
 unit_id text primary key,
 address text not null unique
);
insert into public.housing_units values
 ('constellation-c-101','Constellation / Block C / Unit 101'),
 ('constellation-c-102','Constellation / Block C / Unit 102'),
 ('constellation-c-103','Constellation / Block C / Unit 103'),
 ('constellation-c-104','Constellation / Block C / Unit 104')
on conflict (unit_id) do nothing;
create table if not exists public.home_assignments (
 account_id uuid primary key references public.profiles(id) on delete cascade,
 unit_id text not null unique references public.housing_units(unit_id),
 assigned_at timestamptz not null default now()
);
create table if not exists public.home_decorations (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references public.profiles(id) on delete cascade,
 unit_id text not null references public.housing_units(unit_id),
 definition_id text not null default 'constellation-keepsake' check (definition_id='constellation-keepsake'),
 x double precision not null default 0 check (x between -2.5 and 2.5),
 y double precision not null default 0.4 check (y=0.4),
 z double precision not null default 3 check (z between 0.75 and 5.25),
 yaw double precision not null default 0 check (yaw>=0 and yaw<360),
 revision integer not null default 0 check (revision>=0),
 updated_at timestamptz not null default now()
);
alter table public.housing_units enable row level security;
alter table public.home_assignments enable row level security;
alter table public.home_decorations enable row level security;
revoke all on public.housing_units,public.home_assignments,public.home_decorations from public,anon,authenticated;
grant select on public.housing_units,public.home_assignments,public.home_decorations to authenticated;
grant all on public.housing_units,public.home_assignments,public.home_decorations to service_role;
drop policy if exists homes_read_self on public.home_assignments;
create policy homes_read_self on public.home_assignments for select to authenticated using (account_id=(select auth.uid()));
drop policy if exists decorations_read_self on public.home_decorations;
create policy decorations_read_self on public.home_decorations for select to authenticated using (owner_id=(select auth.uid()));
drop policy if exists units_read_own on public.housing_units;
create policy units_read_own on public.housing_units for select to authenticated using (exists(select 1 from public.home_assignments a where a.unit_id=housing_units.unit_id and a.account_id=(select auth.uid())));

-- Internal formatter; clients cannot pass arbitrary account IDs to it.
create or replace function public.constellation_home_record(p_account_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select pg_catalog.jsonb_build_object('unit_id',a.unit_id,'address',u.address,
  'resident',p.username||coalesce('#'||p.discriminator,''),
  'decoration',pg_catalog.to_jsonb(d))
 from public.home_assignments a join public.housing_units u using(unit_id)
 join public.profiles p on p.id=a.account_id
 left join public.home_decorations d on d.owner_id=a.account_id and d.unit_id=a.unit_id
 where a.account_id=p_account_id
$$;
revoke all on function public.constellation_home_record(uuid) from public,anon,authenticated;

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
   where not exists(select 1 from public.home_assignments a where a.unit_id=u.unit_id)
   order by u.unit_id for update of u skip locked limit 1;
  if chosen is null then raise exception 'Constellation test corridor is full. No apartment was assigned.'; end if;
  insert into public.home_assignments(account_id,unit_id) values(p_account_id,chosen);
 end if;
 insert into public.home_decorations(owner_id,unit_id) values(p_account_id,chosen)
 on conflict(owner_id) do nothing;
 return public.constellation_home_record(p_account_id);
end $$;
revoke all on function public.ensure_constellation_home(uuid) from public,anon,authenticated;
grant execute on function public.ensure_constellation_home(uuid) to service_role;

create or replace function public.get_my_constellation_home()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to view your home.' using errcode='28000'; end if;
 return public.constellation_home_record(auth.uid());
end $$;
revoke all on function public.get_my_constellation_home() from public,anon,authenticated;
grant execute on function public.get_my_constellation_home() to authenticated;

create or replace function public.place_constellation_decoration(
 p_account_id uuid,p_decoration_id uuid,p_unit_id text,p_x double precision,p_z double precision,
 p_yaw double precision,p_expected_revision integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.home_decorations;
begin
 perform 1 from public.home_assignments where account_id=p_account_id and unit_id=p_unit_id for update;
 if not found then raise exception 'This apartment does not belong to this account.'; end if;
 select * into d from public.home_decorations where id=p_decoration_id and owner_id=p_account_id and unit_id=p_unit_id for update;
 if not found then raise exception 'Owned decoration not found.'; end if;
 if p_x is null or p_z is null or p_yaw is null or p_expected_revision is null or
    not(p_x between -2.5 and 2.5) or not(p_z between 0.75 and 5.25) or not(p_yaw>=0 and p_yaw<360) then
  raise exception 'Placement is outside the apartment floor.';
 end if;
 -- A repeated placement after a lost response returns its already-saved result.
 if d.x=p_x and d.z=p_z and d.yaw=p_yaw then return public.constellation_home_record(p_account_id); end if;
 if d.revision<>p_expected_revision then raise exception 'Decoration changed. Reload its placement before moving it again.' using errcode='40001'; end if;
 update public.home_decorations set x=p_x,z=p_z,yaw=p_yaw,revision=revision+1,updated_at=now() where id=d.id;
 return public.constellation_home_record(p_account_id);
end $$;
revoke all on function public.place_constellation_decoration(uuid,uuid,text,double precision,double precision,double precision,integer) from public,anon,authenticated;
grant execute on function public.place_constellation_decoration(uuid,uuid,text,double precision,double precision,double precision,integer) to service_role;
notify pgrst,'reload schema';
commit;
