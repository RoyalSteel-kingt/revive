-- Revive API / milestone 1: authenticated profiles and read-only inventory.
-- Run once in your project's Supabase SQL Editor. Safe to run again.
-- Each new profile receives one starter Flux Rifle, exactly once.
begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z][A-Za-z0-9_]{2,23}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_unique on public.profiles (lower(username));

create table if not exists public.item_definitions (
  id text primary key,
  name text not null,
  category text not null check (category in ('weapon','part','food','companion')),
  description text not null default ''
);
insert into public.item_definitions(id,name,category,description) values
 ('flux-rifle','Flux Rifle','weapon','Your starter field rifle. Every account receives its own unique instance.'),
 ('focus-01','Focusing assembly','part','A replacement focusing assembly for the Flux Rifle.'),
 ('meal-pack','Meal pack','food','A sealed field meal for expeditions.')
on conflict (id) do nothing;

create table if not exists public.item_instances (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  definition_id text not null references public.item_definitions(id),
  condition integer not null default 100 check (condition between 0 and 100),
  location text not null default 'stash' check (location in ('stash','delivery','mission')),
  source text not null,
  created_at timestamptz not null default now()
);
create index if not exists item_instances_owner_index on public.item_instances(owner_id);
create unique index if not exists item_instances_one_starter on public.item_instances(owner_id) where source='starter';

alter table public.profiles enable row level security;
alter table public.item_definitions enable row level security;
alter table public.item_instances enable row level security;

-- Reset the privileges of THESE new tables only. No client may edit inventory.
revoke all on public.profiles,public.item_definitions,public.item_instances from anon,authenticated;
grant select on public.profiles,public.item_definitions,public.item_instances to authenticated;
grant all on public.profiles,public.item_definitions,public.item_instances to service_role;

drop policy if exists profiles_read_self on public.profiles;
create policy profiles_read_self on public.profiles for select to authenticated using ((select auth.uid())=id);
drop policy if exists definitions_read_authenticated on public.item_definitions;
create policy definitions_read_authenticated on public.item_definitions for select to authenticated using (true);
drop policy if exists instances_read_self on public.item_instances;
create policy instances_read_self on public.item_instances for select to authenticated using ((select auth.uid())=owner_id);

-- Definer privileges are necessary for this single controlled onboarding grant.
-- The account ID comes from the authenticated token, never from a client argument.
create or replace function public.register_profile(p_username text)
returns public.profiles
language plpgsql
security definer
set search_path=''
as $$
declare
  account_id uuid := auth.uid();
  chosen_username text := trim(p_username);
  result public.profiles;
begin
  if account_id is null then raise exception 'Sign in before choosing a username.' using errcode='28000'; end if;
  if chosen_username is null or chosen_username !~ '^[A-Za-z][A-Za-z0-9_]{2,23}$' then
    raise exception 'Use 3-24 characters: start with a letter, then letters, numbers, or underscores.' using errcode='22023';
  end if;
  -- Concurrent registration calls share this transaction lock for the same account.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account_id::text,0));
  select * into result from public.profiles where id=account_id;
  if found then return result; end if;
  insert into public.profiles(id,username) values (account_id,chosen_username) returning * into result;
  insert into public.item_instances(owner_id,definition_id,condition,location,source)
    values (account_id,'flux-rifle',100,'stash','starter')
    on conflict (owner_id) where source='starter' do nothing;
  return result;
end;
$$;
revoke all on function public.register_profile(text) from public,anon,authenticated;
grant execute on function public.register_profile(text) to authenticated;

notify pgrst, 'reload schema';
commit;
