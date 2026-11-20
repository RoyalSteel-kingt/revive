-- Revive website identity. Apply to the EXISTING Supabase project.
-- Requires existing profiles with six-digit tags (001 + 002, already in the export).
-- Does not call register_profile, grant equipment, or enroll a player with SF.
begin;

create or replace function public.get_my_contractor_identity()
returns jsonb language plpgsql stable security definer set search_path=''
as $identity$
declare
  owner_id uuid := auth.uid();
  person public.profiles;
  membership jsonb := pg_catalog.jsonb_build_object('state','unavailable');
  sf_date timestamptz;
begin
  if owner_id is null then raise exception 'Sign in to read your contractor identity.' using errcode='28000'; end if;
  select * into person from public.profiles where id=owner_id;
  -- Optional: the new SF introduction may not be installed yet.
  if pg_catalog.to_regclass('public.sf_contractor_registrations') is not null then
    execute 'select registered_at from public.sf_contractor_registrations where account_id=$1'
      into sf_date using owner_id;
    membership := pg_catalog.jsonb_build_object('state',case when sf_date is null then 'unregistered' else 'registered' end,'registered_at',sf_date);
  end if;
  return pg_catalog.jsonb_build_object('account_id',owner_id,
    'profile',case when person.id is null then null else pg_catalog.jsonb_build_object(
      'id',person.id,'username',person.username,'discriminator',person.discriminator,'created_at',person.created_at) end,
    'sf',membership,'can_create',true);
end;
$identity$;

create or replace function public.create_my_contractor_identity(p_username text)
returns jsonb language plpgsql security definer set search_path=''
as $identity$
declare
  owner_id uuid := auth.uid();
  person public.profiles;
  chosen_name text := pg_catalog.btrim(p_username);
  candidate_tag text;
  collision_constraint text;
  attempt integer;
begin
  if owner_id is null then raise exception 'Sign in before creating your contractor profile.' using errcode='28000'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
  select * into person from public.profiles where id=owner_id;
  if person.id is not null then return public.get_my_contractor_identity(); end if;
  if chosen_name is null or chosen_name !~ '^[A-Za-z][A-Za-z0-9_]{2,23}$' then
    raise exception 'Use 3-24 characters: start with a letter, then letters, numbers or underscores.' using errcode='22023';
  end if;
  for attempt in 1..32 loop
    candidate_tag := pg_catalog.lpad((pg_catalog.floor(pg_catalog.random()*1000000)::integer)::text,6,'0');
    begin
      insert into public.profiles(id,username,discriminator) values(owner_id,chosen_name,candidate_tag) returning * into person;
      exit;
    exception when unique_violation then
      get stacked diagnostics collision_constraint=constraint_name;
      if collision_constraint <> 'profiles_handle_unique' then raise; end if;
    end;
  end loop;
  if person.id is null then raise exception 'Could not assign a name tag. Please try again.' using errcode='P0001'; end if;
  return public.get_my_contractor_identity();
end;
$identity$;

revoke all on function public.get_my_contractor_identity() from public,anon,authenticated;
revoke all on function public.create_my_contractor_identity(text) from public,anon,authenticated;
grant execute on function public.get_my_contractor_identity() to authenticated;
grant execute on function public.create_my_contractor_identity(text) to authenticated;
notify pgrst, 'reload schema';
commit;
