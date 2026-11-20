create schema mail_private;
revoke all on schema mail_private from public,anon,authenticated;
grant usage on schema mail_private to authenticated;
create table mail_private.letters(
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete cascade,
 source_key text not null, sender text not null, subject text not null, body text not null,
 kind text not null check(kind in ('system','company','shop','gift','event')),
 created_at timestamptz not null default clock_timestamp(), read_at timestamptz, archived_at timestamptz,
 expires_at timestamptz, order_id uuid unique references public.purchase_orders(id),
 unique(owner_id,source_key), check(expires_at is null or kind='event')
);
create index mail_letters_owner on mail_private.letters(owner_id,created_at desc,id);
create table mail_private.attachments(
 id uuid primary key default gen_random_uuid(), letter_id uuid not null references mail_private.letters(id) on delete cascade,
 kind text not null check(kind in ('chroma','coupon')), label text not null,
 amount bigint not null default 1 check(amount between 1 and 1000000000), claimed_at timestamptz
);
create index mail_attachments_letter on mail_private.attachments(letter_id);
create table mail_private.coupons(attachment_id uuid primary key references mail_private.attachments(id),owner_id uuid not null references public.profiles(id), label text not null,quantity bigint not null);
create index mail_coupons_owner on mail_private.coupons(owner_id);
alter table mail_private.letters enable row level security;
alter table mail_private.attachments enable row level security;
alter table mail_private.coupons enable row level security;
revoke all on all tables in schema mail_private from public,anon,authenticated;
create function mail_private.guard() returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();begin
 if u is null then raise exception 'Sign in to open Mail.' using errcode='28000';end if;
 perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
 if exists(select 1 from public.mission_runs where account_id=u and status='active') or exists(select 1 from public.item_instances where owner_id=u and location='mission') then raise exception 'Mail is unavailable during deployment.';end if;
 return u;end;$$;
revoke all on function mail_private.guard() from public,anon,authenticated;
create or replace function public.complete_order_delivery(p_delivery_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $checkout$
declare owner_id uuid; order_row public.purchase_orders; delivery public.order_deliveries;
begin
 select o.account_id into owner_id from public.purchase_orders o join public.order_deliveries d on d.order_id=o.id where d.id=p_delivery_id;
 if owner_id is null then raise exception 'Delivery not found.' using errcode='22023'; end if;
 perform 1 from public.profiles where id=owner_id for update;
 select o.* into order_row from public.purchase_orders o join public.order_deliveries d on d.order_id=o.id where d.id=p_delivery_id for update of o;
 select * into delivery from public.order_deliveries where id=p_delivery_id for update;
 if delivery.status='delivered' then return revive_internal.purchase_order_record(order_row.id); end if;
 if clock_timestamp()<order_row.created_at+interval '5 minutes' then raise exception 'Delivery is still in transit.';end if;
 update public.order_deliveries d set unit_id=h.unit_id,address=u.address from public.home_assignments h join public.housing_units u using(unit_id) where d.id=p_delivery_id and h.account_id=owner_id;
 if not found then raise exception 'A home is required for delivery.';end if;
 insert into public.item_instances(id,owner_id,definition_id,condition,location,source)
 values(order_row.item_id,owner_id,order_row.definition_id,order_row.condition,'delivery','hyphen-order');
 update public.order_deliveries set status='delivered',delivered_at=clock_timestamp() where id=p_delivery_id;
 return revive_internal.purchase_order_record(order_row.id);
end;
$checkout$;
create function mail_private.snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
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
 select l.id,l.sender,l.subject,l.body,l.kind,l.created_at,l.read_at,l.archived_at,l.expires_at,
 case when l.order_id is null then null else jsonb_build_object('status',case when i.id is not null and i.location<>'delivery' then 'collected' when d.status='delivered' then 'delivered' when clock_timestamp()>=l.created_at+interval '1 minute' then 'in_transit' else 'preparing' end,'eta',l.created_at+interval '5 minutes','address',coalesce(h.address,d.address)) end as delivery,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'label',a.label,'amount',a.amount,'claimed_at',a.claimed_at)) from mail_private.attachments a where a.letter_id=l.id),'[]'::jsonb) as attachments
 from mail_private.letters l left join public.order_deliveries d on d.order_id=l.order_id left join public.purchase_orders o on o.id=l.order_id left join public.item_instances i on i.id=o.item_id
 left join public.home_assignments ha on ha.account_id=u left join public.housing_units h on h.unit_id=ha.unit_id
 where l.owner_id=u
 )x),'[]'::jsonb),'coupons',coalesce((select jsonb_agg(jsonb_build_object('label',label,'quantity',quantity)) from mail_private.coupons where owner_id=u),'[]'::jsonb));
end;$$;
create function mail_private.change(p_id uuid,p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=mail_private.guard();l mail_private.letters;a mail_private.attachments;begin
 select * into l from mail_private.letters where id=p_id and owner_id=u for update;
 if not found then raise exception 'Letter unavailable.';end if;
 if p_action='read' then update mail_private.letters set read_at=coalesce(read_at,clock_timestamp()) where id=l.id;
 elsif p_action='claim' then
 if l.expires_at<=clock_timestamp() then raise exception 'This reward has expired.';end if;
 for a in select * from mail_private.attachments where letter_id=l.id and claimed_at is null for update loop
 if a.kind='chroma' then
 insert into public.chroma_wallets(account_id,balance) values(u,0) on conflict(account_id) do nothing;
 update public.chroma_wallets set balance=balance+a.amount where account_id=u and balance+a.amount<=1000000000000;
 if not found then raise exception 'Chroma balance limit reached.';end if;
 else insert into mail_private.coupons values(a.id,u,a.label,a.amount) on conflict do nothing;end if;
 update mail_private.attachments set claimed_at=clock_timestamp() where id=a.id;
 end loop;
 elsif p_action='archive' then
 if exists(select 1 from mail_private.attachments where letter_id=l.id and claimed_at is null) and (l.expires_at is null or l.expires_at>clock_timestamp()) then raise exception 'Claim the digital attachments before archiving.';end if;
 if l.order_id is not null and not exists(select 1 from public.purchase_orders o join public.item_instances i on i.id=o.item_id where o.id=l.order_id and i.location<>'delivery') then raise exception 'Collect your physical package at home before archiving.';end if;
 update mail_private.letters set archived_at=coalesce(archived_at,clock_timestamp()) where id=l.id;
 elsif p_action='restore' then update mail_private.letters set archived_at=null where id=l.id;
 else raise exception 'Unsupported mail action.';end if;
 return mail_private.snapshot();end;$$;
revoke all on function mail_private.snapshot(),mail_private.change(uuid,text) from public,anon;
grant execute on function mail_private.snapshot(),mail_private.change(uuid,text) to authenticated;
create function public.get_mailbox() returns jsonb language sql security invoker set search_path='' as $$ select mail_private.snapshot();$$;
create function public.change_mail(p_id uuid,p_action text) returns jsonb language sql security invoker set search_path='' as $$ select mail_private.change(p_id,p_action);$$;
revoke all on function public.get_mailbox(),public.change_mail(uuid,text) from public,anon;
grant execute on function public.get_mailbox(),public.change_mail(uuid,text) to authenticated;
-- Trusted issuance boundary for future company/event services. No player may mint rewards.
create function public.issue_mail(p_owner uuid,p_key text,p_sender text,p_subject text,p_body text,p_kind text,p_expiry timestamptz default null,p_attachments jsonb default '[]') returns uuid language plpgsql security invoker set search_path='' as $$
declare l uuid;a jsonb;begin
 insert into mail_private.letters(owner_id,source_key,sender,subject,body,kind,expires_at) values(p_owner,p_key,p_sender,p_subject,p_body,p_kind,p_expiry) on conflict(owner_id,source_key) do nothing returning id into l;
 if l is null then select id into l from mail_private.letters where owner_id=p_owner and source_key=p_key;return l;end if;
 for a in select value from jsonb_array_elements(p_attachments) loop insert into mail_private.attachments(letter_id,kind,label,amount) values(l,a->>'kind',a->>'label',coalesce((a->>'amount')::bigint,1));end loop;return l;end;$$;
revoke all on function public.issue_mail(uuid,text,text,text,text,text,timestamptz,jsonb) from public,anon,authenticated;
grant usage on schema mail_private to service_role;
grant all on all tables in schema mail_private to service_role;
grant execute on function public.issue_mail(uuid,text,text,text,text,text,timestamptz,jsonb) to service_role;
-- Future in-game home interaction only. The web client has no execution permission.
create function mail_private.collect_order(p_owner uuid,p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.purchase_orders;begin
 perform 1 from public.profiles where id=p_owner for update;
 if exists(select 1 from public.mission_runs where account_id=p_owner and status='active') then raise exception 'Return from deployment first.';end if;
 select * into o from public.purchase_orders where id=p_order and account_id=p_owner;
 if not found then raise exception 'Package unavailable.';end if;
 if exists(select 1 from public.item_instances where id=o.item_id and location='stash') then return;end if;
 if not exists(select 1 from public.item_instances i join inventory_private.specs s on s.definition_id=i.definition_id where i.owner_id=p_owner and i.location='stash' and i.inventory_position='home' and i.definition_id=o.definition_id and i.condition=o.condition and s.stackable group by i.definition_id,i.condition having count(*)%100>0) and inventory_private.used_slots(p_owner,'home')>=coalesce((select home_slots from inventory_private.settings where owner_id=p_owner),25) then raise exception 'Home storage is full. Your package is safe.';end if;
 update public.item_instances set location='stash',inventory_position='home' where id=o.item_id and owner_id=p_owner and location='delivery';
 if not found then raise exception 'Package has not arrived.';end if;
 insert into inventory_private.settings(owner_id,revision) values(p_owner,1) on conflict(owner_id) do update set revision=inventory_private.settings.revision+1;
end;$$;
revoke all on function mail_private.collect_order(uuid,uuid) from public,anon,authenticated;
grant execute on function mail_private.collect_order(uuid,uuid) to service_role;
notify pgrst,'reload schema';

create function public.collect_mail_order(p_owner uuid,p_order uuid) returns void language sql security invoker set search_path='' as $$select mail_private.collect_order(p_owner,p_order);$$;
revoke all on function public.collect_mail_order(uuid,uuid) from public,anon,authenticated;grant execute on function public.collect_mail_order(uuid,uuid) to service_role;

revoke all on function public.complete_order_delivery(uuid) from public,anon,authenticated;grant execute on function public.complete_order_delivery(uuid) to service_role;
