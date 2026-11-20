-- Revive API: shared usernames with server-assigned six-digit tags.
-- Run AFTER 001_accounts_inventory.sql in Supabase SQL Editor.
-- Safe to rerun. Existing account IDs, items, usernames, and tags are preserved.
begin;

alter table public.profiles add column if not exists discriminator text;
-- Before this migration usernames were unique, so backfill cannot collide per name.
update public.profiles
set discriminator=pg_catalog.lpad((pg_catalog.floor(pg_catalog.random()*1000000)::integer)::text,6,'0')
where discriminator is null;
alter table public.profiles alter column discriminator set not null;
do $$ begin
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.profiles'::regclass and conname='profiles_discriminator_format') then
    alter table public.profiles add constraint profiles_discriminator_format check (discriminator ~ '^[0-9]{6}$');
  end if;
end $$;
create unique index if not exists profiles_handle_unique on public.profiles(lower(username),discriminator);
drop index if exists public.profiles_username_unique;

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
  candidate_tag text;
  collision_constraint text;
  attempt integer;
begin
  if account_id is null then raise exception 'Sign in before choosing a username.' using errcode='28000'; end if;
  if chosen_username is null or chosen_username !~ '^[A-Za-z][A-Za-z0-9_]{2,23}$' then
    raise exception 'Use 3-24 characters: start with a letter, then letters, numbers, or underscores.' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account_id::text,0));
  select * into result from public.profiles where id=account_id;
  if found then return result; end if;
  for attempt in 1..32 loop
    candidate_tag := pg_catalog.lpad((pg_catalog.floor(pg_catalog.random()*1000000)::integer)::text,6,'0');
    begin
      insert into public.profiles(id,username,discriminator)
      values (account_id,chosen_username,candidate_tag) returning * into result;
      exit;
    exception when unique_violation then
      get stacked diagnostics collision_constraint=constraint_name;
      -- Retry only a tag collision, not unrelated constraints.
      if collision_constraint <> 'profiles_handle_unique' then raise; end if;
    end;
  end loop;
  if result.id is null then
    raise exception 'Could not assign a username tag. Please try again.' using errcode='P0001';
  end if;
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
