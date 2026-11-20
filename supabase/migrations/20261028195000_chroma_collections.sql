-- Serving remains the existing wallet. No existing balances or prices change.
create schema banking_private;
revoke all on schema banking_private from public,anon,authenticated;
grant usage on schema banking_private to authenticated;
create table banking_private.pockets(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check(length(name) between 1 and 60),target bigint check(target between 1 and 1000000000000),
 general boolean not null default false,balance bigint not null default 0 check(balance between 0 and 1000000000000),created_at timestamptz not null default now()
);
create unique index banking_general on banking_private.pockets(owner_id) where general;
create index banking_pockets_owner on banking_private.pockets(owner_id);
create table banking_private.requests(owner_id uuid not null references public.profiles(id) on delete cascade,id uuid not null,payload jsonb not null,result jsonb not null,primary key(owner_id,id));
create table banking_private.activity(id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id) on delete cascade,request_id uuid not null,description text not null,amount bigint not null default 0,fee bigint not null default 0,created_at timestamptz not null default clock_timestamp());
create index banking_activity_owner on banking_private.activity(owner_id,created_at desc,id desc);
alter table banking_private.pockets enable row level security;
alter table banking_private.requests enable row level security;
alter table banking_private.activity enable row level security;
revoke all on all tables in schema banking_private from public,anon,authenticated;
alter table public.chroma_transactions drop constraint chroma_transactions_source_check;
alter table public.chroma_transactions add constraint chroma_transactions_source_check check(source in('account','hyphen','opening','savings'));

create function banking_private.workspace() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r jsonb;
begin
 if u is null then raise exception 'Sign in to use banking.';end if;
 perform 1 from public.profiles where id=u for update;
 if not found then raise exception 'Create your contractor profile first.';end if;
 insert into banking_private.pockets(owner_id,name,general) values(u,'General Collections',true) on conflict(owner_id) where general do nothing;
 select jsonb_build_object('serving',coalesce((select balance from public.chroma_wallets where account_id=u),0),
 'deployed',exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission'),
 'pockets',(select coalesce(jsonb_agg(to_jsonb(p)-'owner_id' order by p.general desc,p.created_at,p.id),'[]') from banking_private.pockets p where owner_id=u),
 'activity',(select coalesce(jsonb_agg(to_jsonb(a)-'owner_id' order by a.created_at desc,a.id desc),'[]') from(select * from banking_private.activity where owner_id=u order by created_at desc,id desc limit 100)a)) into r;
 return r;
end $$;
revoke all on function banking_private.workspace() from public,anon,authenticated;
grant execute on function banking_private.workspace() to authenticated;
create function public.get_banking_workspace() returns jsonb language sql security invoker set search_path='' as $$select banking_private.workspace()$$;
revoke all on function public.get_banking_workspace() from public,anon;
grant execute on function public.get_banking_workspace() to authenticated;

create function banking_private.change(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();s jsonb;old banking_private.requests;src banking_private.pockets;dst banking_private.pockets;
 typ text:=p_action->>'type';f text:=p_action->>'from';t text:=p_action->>'to';n text:=btrim(p_action->>'name');
 amt bigint;fee bigint:=0;serving bigint;deployed boolean;target_value bigint;desc_text text;result jsonb;
begin
 if u is null or p_request is null or p_action is null or jsonb_typeof(p_action)<>'object' then raise exception 'Invalid banking request.';end if;
 s:=banking_private.workspace();
 select * into old from banking_private.requests where owner_id=u and id=p_request;
 if found then if old.payload<>p_action then raise exception 'This request belongs to another action.';end if;return old.result;end if;
 serving:=(s->>'serving')::bigint;deployed:=(s->>'deployed')::boolean;
 if typ in('create','edit') then
  if n is null or length(n) not between 1 and 60 then raise exception 'Use a goal name of 1–60 characters.';end if;
  target_value:=nullif(p_action->>'target','')::bigint;
  if target_value is not null and target_value not between 1 and 1000000000000 then raise exception 'Enter a positive whole-Chroma target.';end if;
  if typ='create' then
   if (select count(*) from banking_private.pockets where owner_id=u and not general)>=50 then raise exception 'You can keep up to 50 savings goals.';end if;
   insert into banking_private.pockets(owner_id,name,target) values(u,n,target_value);
   desc_text:='Created goal: '||n;
  else
   update banking_private.pockets set name=n,target=target_value where id=(p_action->>'id')::uuid and owner_id=u and not general;
   if not found then raise exception 'Savings goal unavailable.';end if;desc_text:='Updated goal: '||n;
  end if;
 elsif typ in('transfer','close') then
  if typ='close' then
   select * into src from banking_private.pockets where id=(p_action->>'id')::uuid and owner_id=u and not general for update;
   if not found then raise exception 'Savings goal unavailable.';end if;
   f:=src.id::text;amt:=src.balance;
   if amt<>coalesce((p_action->>'amount')::bigint,-1) then raise exception 'Goal balance changed. Review again.';end if;
  else amt:=(p_action->>'amount')::bigint;end if;
  if f is null or t is null or f=t or amt is null or amt<0 or amt>1000000000000 or (typ='transfer' and amt=0) then raise exception 'Choose different balances and a positive whole amount.';end if;
  if f<>'serving' then
   select * into src from banking_private.pockets where id=f::uuid and owner_id=u for update;
   if not found then raise exception 'Source savings unavailable.';end if;
   if src.balance<amt then raise exception 'Not enough saved Chroma.';end if;
  end if;
  if t<>'serving' then
   select * into dst from banking_private.pockets where id=t::uuid and owner_id=u for update;
   if not found then raise exception 'Destination savings unavailable.';end if;
   if dst.balance+amt>1000000000000 then raise exception 'Destination balance is too large.';end if;
  end if;
  if deployed and (f='serving' or t='serving') and amt>0 then fee:=(amt+99)/100;end if;
  if fee<>coalesce((p_action->>'fee')::bigint,-1) or deployed is distinct from (p_action->>'deployed')::boolean then raise exception 'Deployment or fee changed. Review this transfer again.';end if;
  if f='serving' and serving<amt+fee then raise exception 'Not enough Serving Chroma, including the fee.';end if;
  if t='serving' and amt>0 and amt<=fee then raise exception 'Transfer amount must exceed its deployment fee.';end if;
  if t='serving' and serving+amt-fee>1000000000000 then raise exception 'Serving balance is too large.';end if;
  insert into public.chroma_wallets(account_id,balance) values(u,0) on conflict(account_id) do nothing;
  if f='serving' then update public.chroma_wallets set balance=balance-amt-fee where account_id=u and balance>=amt+fee;if not found then raise exception 'Serving changed. Review again.';end if;
  else update banking_private.pockets set balance=balance-amt where id=src.id;end if;
  if t='serving' then update public.chroma_wallets set balance=balance+amt-fee where account_id=u;
  else update banking_private.pockets set balance=balance+amt where id=dst.id;end if;
  desc_text:=case when typ='close' then 'Closed goal: '||src.name||' → ' else '' end||case when f='serving' then 'Serving' else src.name end||' → '||case when t='serving' then 'Serving' else dst.name end;
  -- Label the wallet movement as an internal savings transfer, not income/spending.
  update public.chroma_transactions set source='savings',reference=p_request,description=desc_text||case when fee>0 then ' (deployment fee: '||fee||' Chroma)' else '' end
   where account_id=u and recorded_xid=pg_catalog.pg_current_xact_id() and source='account' and reference is null
    and ordinal=(select max(ordinal) from public.chroma_transactions where account_id=u and recorded_xid=pg_catalog.pg_current_xact_id() and source='account' and reference is null)
    and (f='serving' or t='serving') and amt>0;
  if typ='close' then delete from banking_private.pockets where id=src.id;end if;
 else raise exception 'Unknown banking action.';end if;
 insert into banking_private.activity(owner_id,request_id,description,amount,fee) values(u,p_request,desc_text,coalesce(amt,0),fee);
 result:=jsonb_build_object('request_id',p_request,'fee',fee);
 insert into banking_private.requests values(u,p_request,p_action,result);return result;
end $$;
revoke all on function banking_private.change(uuid,jsonb) from public,anon,authenticated;
grant execute on function banking_private.change(uuid,jsonb) to authenticated;
create function public.change_banking_workspace(p_request uuid,p_action jsonb) returns jsonb language sql security invoker set search_path='' as $$select banking_private.change(p_request,p_action)$$;
revoke all on function public.change_banking_workspace(uuid,jsonb) from public,anon;
grant execute on function public.change_banking_workspace(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
