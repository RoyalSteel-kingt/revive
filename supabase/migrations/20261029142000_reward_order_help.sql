create table rewards_private.help_cases(order_id uuid primary key references rewards_private.orders(id),category text not null check(category in('missing','damaged','incorrect','other')),status text not null default 'open' check(status in('open','waiting_player','resolved')),revision bigint not null default 1,updated_at timestamptz not null default clock_timestamp());
create table rewards_private.help_messages(id uuid primary key default gen_random_uuid(),order_id uuid not null references rewards_private.help_cases(order_id),actor uuid not null references public.profiles(id),author text not null check(author in('owner','customer')),body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default clock_timestamp());
create index reward_help_messages_order on rewards_private.help_messages(order_id,created_at desc,id desc);
create index reward_help_messages_rate on rewards_private.help_messages(actor,created_at desc);
alter table rewards_private.help_cases enable row level security;
alter table rewards_private.help_messages enable row level security;
revoke all on rewards_private.help_cases,rewards_private.help_messages from public,anon,authenticated;
create function rewards_private.help(p_order uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();staff boolean;case_row rewards_private.help_cases;r jsonb;
begin
 if u is null then raise exception 'Sign in to view order help.';end if;
 staff:=exists(select 1 from notice_private.staff where owner_id=u and role='owner');
 if not staff and (exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission')) then raise exception 'Private order help is unavailable during deployment.';end if;
 if p_order is null then
  select coalesce(jsonb_agg(to_jsonb(h) order by h.updated_at desc),'[]') into r from rewards_private.help_cases h join rewards_private.orders ord on ord.id=h.order_id where ord.owner_id=u or staff;return r;
 end if;
 if not exists(select 1 from rewards_private.orders where id=p_order and (owner_id=u or staff)) then raise exception 'Order unavailable.';end if;
 select * into case_row from rewards_private.help_cases where order_id=p_order;
 if not found then return jsonb_build_object('case',null,'messages','[]'::jsonb,'has_older',false);end if;
 return jsonb_build_object('case',to_jsonb(case_row),'messages',(select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at,m.id),'[]') from (select id,author,body,created_at from rewards_private.help_messages where order_id=p_order order by created_at desc,id desc limit 200)m),'has_older',(select count(*)>200 from rewards_private.help_messages where order_id=p_order));
end $$;
revoke all on function rewards_private.help(uuid) from public,anon;grant execute on function rewards_private.help(uuid) to authenticated;
create function public.get_reward_help(p_order uuid default null) returns jsonb language sql security invoker set search_path='' as $$select rewards_private.help(p_order)$$;
revoke all on function public.get_reward_help(uuid) from public,anon;grant execute on function public.get_reward_help(uuid) to authenticated;

create function rewards_private.change_help(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();staff boolean;typ text:=p_action->>'type';ord rewards_private.orders;h rewards_private.help_cases;receipt rewards_private.receipts;msg text:=btrim(p_action->>'body');result jsonb;notify_owner uuid;
begin
 if u is null or p_request is null or p_action is null then raise exception 'Sign in with a valid request.';end if;
 perform pg_advisory_xact_lock(28202500);
 select * into receipt from rewards_private.receipts where owner_id=u and id=p_request;
 if found then if receipt.hash<>md5(p_action::text) then raise exception 'This request belongs to another action.';end if;return receipt.result;end if;
 staff:=exists(select 1 from notice_private.staff where owner_id=u and role='owner');
 -- Read path applies the same ownership and deployment checks to writes.
 perform rewards_private.help((p_action->>'id')::uuid);
 select * into ord from rewards_private.orders where id=(p_action->>'id')::uuid and (owner_id=u or staff) for update;
 if not found then raise exception 'Order unavailable.';end if;
 select * into h from rewards_private.help_cases where order_id=ord.id for update;
 if (select count(*) from rewards_private.audit where actor=u and action like 'help_%' and created_at>now()-interval '1 hour')>=30 then raise exception 'Please wait before sending more order-help updates.';end if;
 if typ='help_open' then
  if ord.owner_id<>u or h.order_id is not null then raise exception 'Open the existing order-help conversation.';end if;
  if msg is null or length(msg) not between 1 and 2000 then raise exception 'Describe the problem in 1–2,000 characters.';end if;
  insert into rewards_private.help_cases(order_id,category) values(ord.id,p_action->>'category');
  insert into rewards_private.help_messages(order_id,actor,author,body) values(ord.id,u,'customer',msg);
 elsif typ in('help_reply','help_resolve','help_reopen') then
  if h.order_id is null or h.revision is distinct from (p_action->>'revision')::bigint then raise exception 'Order help changed. Open the latest conversation before updating.';end if;
  if typ='help_reply' then
   if h.status='resolved' then raise exception 'Reopen this case before replying.';end if;
   if msg is null or length(msg) not between 1 and 2000 then raise exception 'Write 1–2,000 characters.';end if;
   insert into rewards_private.help_messages(order_id,actor,author,body) values(ord.id,u,case when staff then 'owner' else 'customer' end,msg);
  elsif typ='help_resolve' then
   if h.status='resolved' then raise exception 'Case is already resolved.';end if;
   if msg is null or length(msg) not between 1 and 2000 then raise exception 'Add a resolution note of 1–2,000 characters.';end if;
   insert into rewards_private.help_messages(order_id,actor,author,body) values(ord.id,u,case when staff then 'owner' else 'customer' end,msg);
  else
   if h.status<>'resolved' then raise exception 'Case is already open.';end if;
  end if;
  update rewards_private.help_cases set status=case when typ='help_resolve' then 'resolved' when typ='help_reopen' then 'open' when staff then 'waiting_player' else 'open' end,revision=revision+1,updated_at=clock_timestamp() where order_id=ord.id;
 else raise exception 'Unknown order-help action.';end if;
 if staff and ord.owner_id<>u then
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind) values(ord.owner_id,'reward-help:'||p_request,'Revive','An update on your order-help case','There is an update to your private order-help conversation. Open Real-world rewards in Shops, then choose Order help on your order.','shop');
 elsif not staff then
  for notify_owner in select owner_id from notice_private.staff where role='owner' loop
   insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind) values(notify_owner,'reward-help:'||p_request||':'||u,'Revive','An order needs your attention','A player updated a private order-help case. Open the fulfillment desk in Real-world rewards.','system');
  end loop;
 end if;
 insert into rewards_private.audit(actor,action,reference) values(u,typ,ord.id);
 result:=jsonb_build_object('id',ord.id,'type',typ);insert into rewards_private.receipts values(u,p_request,md5(p_action::text),result);return result;
end $$;
revoke all on function rewards_private.change_help(uuid,jsonb) from public,anon;grant execute on function rewards_private.change_help(uuid,jsonb) to authenticated;
create function public.change_reward_help(p_request uuid,p_action jsonb) returns jsonb language sql security invoker set search_path='' as $$select rewards_private.change_help(p_request,p_action)$$;
revoke all on function public.change_reward_help(uuid,jsonb) from public,anon;grant execute on function public.change_reward_help(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
