create or replace function rewards_private.change(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();typ text:=p_action->>'type';staff boolean;prior rewards_private.receipts;cfg rewards_private.config;p rewards_private.products;o rewards_private.orders;inv rewards_private.invitations;qty integer;fee integer;total bigint;addr jsonb;rid uuid;result jsonb;dest uuid;label text;
begin
 if u is null or p_request is null or p_action is null then raise exception 'Sign in with a valid request.';end if;
 -- Fulfillment touches other owners: take a shared workflow lock before profile locks.
 perform pg_advisory_xact_lock(28202500);
 perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
 select * into prior from rewards_private.receipts where owner_id=u and id=p_request;
 if typ='recover' then return case when prior.id is null then jsonb_build_object('found',false) else prior.result||jsonb_build_object('found',true) end;end if;
 if prior.id is not null then if prior.hash<>md5(p_action::text) then raise exception 'This request belongs to another action.';end if;return prior.result;end if;
 staff:=exists(select 1 from notice_private.staff where owner_id=u and role='owner');
 if typ in('settings','product','fulfill','invite','ready','refund') and not staff then raise exception 'Owner fulfillment access required.';end if;
 if typ not in('settings','product','fulfill','invite','ready','refund') and (exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission')) then raise exception 'Real-world ordering is unavailable during deployment.';end if;
 select * into cfg from rewards_private.config where id=true for update;
 if typ='settings' then
  update rewards_private.config set enabled=coalesce((p_action->>'enabled')::boolean,false),shipping=nullif(p_action->>'shipping','')::integer where id=true;
 elsif typ='product' then
  if nullif(p_action->>'id','') is not null then
   select * into p from rewards_private.products where id=(p_action->>'id')::uuid for update;
   if not found or p.revision is distinct from (p_action->>'revision')::integer then raise exception 'Product changed. Refresh before editing.';end if;
   rid:=p.id;
  else rid:=gen_random_uuid();end if;
  insert into rewards_private.products(id,name,category,description,photo,price,stock,listed,made_to_order,days) values(rid,btrim(p_action->>'name'),p_action->>'category',coalesce(p_action->>'description',''),nullif(p_action->>'photo',''),(p_action->>'price')::integer,(p_action->>'stock')::integer,coalesce((p_action->>'listed')::boolean,false),coalesce((p_action->>'made_to_order')::boolean,false),(p_action->>'days')::integer)
  on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,photo=excluded.photo,price=excluded.price,stock=excluded.stock,listed=excluded.listed,made_to_order=excluded.made_to_order,days=excluded.days,revision=rewards_private.products.revision+1;
 elsif typ in('buy','request') then
  if not exists(select 1 from rewards_private.progress where owner_id=u) or (select count(distinct shop_id) from public.shop_visits where account_id=u)<3 then raise exception 'Complete the tutorial and visit three different stores first.';end if;
  select * into p from rewards_private.products where id=(p_action->>'product')::uuid and listed for update;
  if not found then raise exception 'Product unavailable.';end if;
  if typ='request' then
   if p.stock>0 or not p.made_to_order then raise exception 'This product is not accepting made-to-order requests.';end if;
   insert into rewards_private.interest(owner_id,product_id) values(u,p.id) on conflict(owner_id,product_id) do update set status='requested';
  else
   if not cfg.enabled or cfg.shipping is null then raise exception 'Ordering has not opened yet.';end if;
   qty:=(p_action->>'quantity')::integer;if qty is null or qty not between 1 and 10 or p.stock<qty then raise exception 'Not enough available stock.';end if;
   total:=p.price::bigint*qty+cfg.shipping;
   if p.revision is distinct from (p_action->>'revision')::integer or total is distinct from (p_action->>'total')::bigint then raise exception 'Price, stock or shipping changed. Review again.';end if;
   addr:=rewards_private.address(p_action->'address');
   update public.chroma_wallets set balance=balance-total where account_id=u and balance>=total;if not found then raise exception 'Not enough Serving Chroma.';end if;
   update rewards_private.products set stock=stock-qty,revision=revision+1 where id=p.id;
   insert into rewards_private.orders(owner_id,product_id,item_name,quantity,unit_price,shipping,total,address) values(u,p.id,p.name,qty,p.price,cfg.shipping,total,addr) returning id into rid;
   update rewards_private.interest set status='withdrawn' where owner_id=u and product_id=p.id;
  end if;
 elsif typ='withdraw' then
  update rewards_private.interest set status='withdrawn' where id=(p_action->>'id')::uuid and owner_id=u;if not found then raise exception 'Request unavailable.';end if;
 elsif typ='invite' then
  select pr.id into dest from public.profiles pr where lower(pr.username||'#'||pr.discriminator)=lower(btrim(p_action->>'handle'));
  if dest is null then raise exception 'Exact player name and tag not found.';end if;
  insert into rewards_private.invitations(owner_id,label,body) values(dest,p_action->>'label',coalesce(p_action->>'body','')) returning id into rid;
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind) values(dest,'real-invite:'||rid,'Revive','A care package invitation','You have a milestone care package invitation. The package and US shipping are free. Open Real-world rewards in Shops to accept or decline.','system');
 elsif typ in('accept','decline') then
  select * into inv from rewards_private.invitations where id=(p_action->>'id')::uuid and owner_id=u for update;
  if not found or inv.status<>'invited' then raise exception 'Invitation no longer available.';end if;
  if typ='accept' then
   addr:=rewards_private.address(p_action->'address');
   insert into rewards_private.orders(owner_id,invitation_id,item_name,quantity,unit_price,shipping,total,address) values(u,inv.id,inv.label,1,0,0,0,addr) returning id into rid;
  end if;
  update rewards_private.invitations set status=case when typ='accept' then 'accepted' else 'declined' end where id=inv.id;
 elsif typ='ready' then
  update rewards_private.interest set status='ready' where id=(p_action->>'id')::uuid and status='requested' and exists(select 1 from rewards_private.products available_product where available_product.id=product_id and available_product.listed and available_product.stock>0) returning owner_id,id into dest,rid;
  if not found then raise exception 'Request unavailable.';end if;
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind) values(dest,'real-ready:'||rid||':'||p_request,'Revive','An update on your product request','Your requested real-world product is ready to review. No Chroma has been charged and stock is not reserved. Open Real-world rewards in Shops.','shop');
 elsif typ in('cancel','refund','fulfill') then
  select * into o from rewards_private.orders where id=(p_action->>'id')::uuid and (owner_id=u or staff) for update;
  if not found then raise exception 'Order unavailable.';end if;
  perform 1 from public.profiles where id=o.owner_id for update;
  rid:=o.id;
  if typ in('cancel','refund') then
   if o.status in('cancelled','refunded') then raise exception 'Order already refunded or cancelled.';end if;
   if typ='cancel' and (o.owner_id<>u or clock_timestamp()>=o.cancel_until or o.status<>'placed') then raise exception 'The 24-hour cancellation period has ended.';end if;
   if o.total>0 then insert into public.chroma_wallets(account_id,balance) values(o.owner_id,o.total) on conflict(account_id) do update set balance=public.chroma_wallets.balance+excluded.balance;end if;
   if o.product_id is not null and o.status in('placed','preparing') then update rewards_private.products set stock=stock+o.quantity,revision=revision+1 where id=o.product_id;end if;
   update rewards_private.orders set status=case when typ='cancel' then 'cancelled' else 'refunded' end,address=null where id=o.id;
  else
   if clock_timestamp()<o.cancel_until then raise exception 'The full 24-hour cancellation period must pass before preparation or shipping.';end if;
   label:=p_action->>'status';
   if not ((o.status='placed' and label='preparing') or (o.status='preparing' and label='shipped') or (o.status='shipped' and label='delivered')) then raise exception 'Invalid fulfillment transition.';end if;
   update rewards_private.orders set status=label,shipped_at=case when label='shipped' then clock_timestamp() else shipped_at end,tracking=case when label='shipped' then nullif(p_action->>'tracking','') else tracking end,address=case when label='delivered' then null else address end where id=o.id;
  end if;
 else raise exception 'Unknown rewards action.';end if;
 if rid is not null and typ in('buy','accept','cancel','refund','fulfill') then
  select * into o from rewards_private.orders where id=rid;
  insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind) values(o.owner_id,'real-order:'||p_request,'Revive','Real-world order update','Your real-world order is '||o.status||'. View its details in Real-world rewards under Shops. This is a physical shipment to your US postal address, not your in-game home.','shop');
 end if;
 insert into rewards_private.audit(actor,action,reference) values(u,typ,rid);
 result:=jsonb_build_object('id',rid,'type',typ);insert into rewards_private.receipts values(u,p_request,md5(p_action::text),result);return result;
end $$;
