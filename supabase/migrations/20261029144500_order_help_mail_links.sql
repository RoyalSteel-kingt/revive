alter table mail_private.letters add column reward_order_id uuid references rewards_private.orders(id);
create or replace function rewards_private.change_help(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,reward_order_id) values(ord.owner_id,'reward-help:'||p_request,'Revive','An update on your order-help case','There is an update to your private order-help conversation. Open Real-world rewards in Shops, then choose Order help on your order.','shop',ord.id);
 elsif not staff then
  for notify_owner in select owner_id from notice_private.staff where role='owner' loop
   insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,reward_order_id) values(notify_owner,'reward-help:'||p_request||':'||u,'Revive','An order needs your attention','A player updated a private order-help case. Open the fulfillment desk in Real-world rewards.','system',ord.id);
  end loop;
 end if;
 insert into rewards_private.audit(actor,action,reference) values(u,typ,ord.id);
 result:=jsonb_build_object('id',ord.id,'type',typ);insert into rewards_private.receipts values(u,p_request,md5(p_action::text),result);return result;
end $$;
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
 select l.id,l.order_id,l.reward_order_id,l.gift_id,(select status from gift_private.gifts where id=l.gift_id) as gift_status,l.sender,l.subject,l.body,l.kind,l.created_at,l.read_at,l.archived_at,l.expires_at,
 case when l.order_id is null then null else jsonb_build_object('status',case when d.collected_at is not null or i.id is not null and i.location<>'delivery' then 'collected' when d.status='delivered' then 'delivered' when clock_timestamp()>=l.created_at+interval '1 minute' then 'in_transit' else 'preparing' end,'eta',l.created_at+interval '5 minutes','address',coalesce(h.address,d.address)) end as delivery,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'label',a.label,'amount',a.amount,'claimed_at',a.claimed_at)) from mail_private.attachments a where a.letter_id=l.id),'[]'::jsonb) as attachments
 from mail_private.letters l left join public.order_deliveries d on d.order_id=l.order_id left join public.purchase_orders o on o.id=l.order_id left join public.item_instances i on i.id=o.item_id
 left join public.home_assignments ha on ha.account_id=u left join public.housing_units h on h.unit_id=ha.unit_id
 where l.owner_id=u
 )x),'[]'::jsonb),'coupons',coalesce((select jsonb_agg(jsonb_build_object('label',label,'quantity',quantity)) from mail_private.coupons where owner_id=u),'[]'::jsonb));
end;$$;

notify pgrst,'reload schema';
