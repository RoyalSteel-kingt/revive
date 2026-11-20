-- Applied live as message_images. Do not replay on the existing project.
create table social_private.images(id uuid primary key,owner_id uuid not null references public.profiles(id),thread_id uuid not null references social_private.threads(id),bytes integer not null check(bytes between 1 and 2000000),thumb_bytes integer not null check(thumb_bytes between 1 and 80000),width integer not null check(width between 1 and 2048),height integer not null check(height between 1 and 2048),mime text not null check(mime in('image/jpeg','image/png','image/webp')),thumb_mime text not null check(thumb_mime in('image/jpeg','image/png','image/webp')),fingerprint text not null,status text not null default 'pending' check(status in('pending','ready','attached','expired','deleted')),created_at timestamptz not null default now());
create index social_images_owner on social_private.images(owner_id,created_at);alter table social_private.images enable row level security;revoke all on social_private.images from public,anon,authenticated;
alter table social_private.messages add column image_id uuid unique references social_private.images(id);alter table social_private.messages drop constraint messages_body_check;alter table social_private.messages add constraint messages_body_check check(length(body)<=4000 and(length(trim(body))>0 or image_id is not null));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('message-images','message-images',false,2000000,array['image/jpeg','image/png','image/webp']);
CREATE OR REPLACE FUNCTION social_private.image_path(p_id uuid, p_thumb boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select owner_id::text||'/'||id::text||case when p_thumb then '/thumb' else '/full' end from social_private.images where id=p_id$function$;

CREATE OR REPLACE FUNCTION public.cleanup_message_images(p_deleted uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$begin
 update social_private.images set status='deleted' where id=any(p_deleted) and status='expired';
 update social_private.images set status='expired' where status in('pending','ready') and created_at<now()-interval '24 hours';
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'full',social_private.image_path(id,false),'thumb',social_private.image_path(id,true))) from (select id from social_private.images where status='expired' limit 20)i),'[]'::jsonb);end$function$;

CREATE OR REPLACE FUNCTION social_private.conversation(p_thread uuid, p_before bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare u uuid:=social_private.owner();begin
 if not exists(select 1 from social_private.threads where id=p_thread and u in(a,b)) then raise exception 'Conversation unavailable.';end if;
 return jsonb_build_object('messages',coalesce((select jsonb_agg(jsonb_build_object('seq',m.seq,'mine',m.sender_id=u,'body',m.body,'created_at',m.created_at,'image',(select jsonb_build_object('id',i.id,'width',i.width,'height',i.height,'bytes',i.bytes,'mime',i.mime,'full',social_private.image_path(i.id,false),'thumb',social_private.image_path(i.id,true)) from social_private.images i where i.id=m.image_id and i.status='attached')) order by m.seq) from (select * from social_private.messages where thread_id=p_thread and (p_before is null or seq<p_before) order by seq desc limit 50)m),'[]'::jsonb));end$function$;

CREATE OR REPLACE FUNCTION social_private.image_readable(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from social_private.images i join social_private.threads t on t.id=i.thread_id where auth.uid() in(t.a,t.b) and i.status='attached' and p_name in(social_private.image_path(i.id,false),social_private.image_path(i.id,true)))$function$;

CREATE OR REPLACE FUNCTION public.reserve_message_image(p_owner uuid, p_id uuid, p_thread uuid, p_bytes integer, p_thumb_bytes integer, p_width integer, p_height integer, p_mime text, p_thumb_mime text, p_fingerprint text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
 declare old social_private.images;t social_private.threads;begin
 perform pg_advisory_xact_lock(27203554);
 select * into t from social_private.threads where id=p_thread and p_owner in(a,b);
 if not found or (t.b is null and not t.business_allowed) or (t.b is not null and not social_private.friendly(p_owner,case when t.a=p_owner then t.b else t.a end)) then raise exception 'Messaging unavailable.';end if;
 select * into old from social_private.images where id=p_id;
 if found then
 if old.owner_id<>p_owner or old.thread_id<>p_thread or old.fingerprint<>p_fingerprint or old.status in('expired','deleted') then raise exception 'Image request does not match.';end if;
 return jsonb_build_object('id',old.id,'status',old.status,'full',social_private.image_path(old.id,false),'thumb',social_private.image_path(old.id,true));end if;
 if (select count(*) from social_private.images where owner_id=p_owner and created_at>now()-interval '1 day')>=20 then raise exception 'Daily image allowance reached. Try again tomorrow.';end if;
 if (select coalesce(sum(bytes+thumb_bytes),0) from social_private.images where owner_id=p_owner and status<>'deleted')+p_bytes+p_thumb_bytes>100000000 then raise exception 'Your image storage allowance is full.';end if;
 if (select coalesce(sum(bytes+thumb_bytes),0) from social_private.images where status<>'deleted')+p_bytes+p_thumb_bytes>400000000 then raise exception 'Image storage is currently full. Text and emoji are still available.';end if;
 insert into social_private.images(id,owner_id,thread_id,bytes,thumb_bytes,width,height,mime,thumb_mime,fingerprint) values(p_id,p_owner,p_thread,p_bytes,p_thumb_bytes,p_width,p_height,p_mime,p_thumb_mime,p_fingerprint);
 return jsonb_build_object('id',p_id,'status','pending','full',social_private.image_path(p_id,false),'thumb',social_private.image_path(p_id,true));end$function$;

CREATE OR REPLACE FUNCTION public.finish_message_image(p_id uuid, p_owner uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$update social_private.images set status='ready' where id=p_id and owner_id=p_owner and status='pending'$function$;

CREATE OR REPLACE FUNCTION social_private.messaging(u uuid, p_request uuid, p_action jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v uuid;op text:=p_action->>'type';t social_private.threads;f social_private.friends;cutoff bigint;begin
 if op='business' then
  if not exists(select 1 from public.shop_visits where account_id=u and shop_id=p_action->>'shop') then raise exception 'Discover this business first.';end if;
  insert into social_private.threads(a,shop_id,business_allowed) values(u,p_action->>'shop',true) on conflict(a,shop_id) where shop_id is not null do update set business_allowed=true;
 elsif op in('send','read','mute','business_stop') then
  select * into t from social_private.threads where id=(p_action->>'thread')::uuid and u in(a,b) for update;
  if not found then raise exception 'Conversation unavailable.';end if;
  if op='send' then
   if (t.b is null and not t.business_allowed) or (t.b is not null and not social_private.friendly(u,case when t.a=u then t.b else t.a end)) then raise exception 'Messaging is unavailable for this conversation.';end if;
   if (select count(*) from social_private.messages where sender_id=u and created_at>now()-interval '1 minute')>=30 then raise exception 'Please slow down before sending another message.';end if;
   if nullif(p_action->>'image','') is not null then
 perform 1 from social_private.images where id=(p_action->>'image')::uuid and owner_id=u and thread_id=t.id and status='ready' for update;
 if not found then raise exception 'Image is not ready for this conversation.';end if;end if;
 insert into social_private.messages(thread_id,sender_id,body,request_id,image_id) values(t.id,u,trim(coalesce(p_action->>'body','')),p_request,nullif(p_action->>'image','')::uuid);
 update social_private.images set status='attached' where id=nullif(p_action->>'image','')::uuid;
  elsif op='read' then
   cutoff:=(p_action->>'through')::bigint;
   if cutoff is null or cutoff<0 or cutoff>coalesce((select max(seq) from social_private.messages where thread_id=t.id),0) then raise exception 'Invalid unread cursor.';end if;
   insert into social_private.cursors(owner_id,thread_id,through_seq) values(u,t.id,cutoff) on conflict(owner_id,thread_id) do update set through_seq=greatest(social_private.cursors.through_seq,excluded.through_seq);
  elsif op='mute' then
   insert into social_private.cursors(owner_id,thread_id,muted) values(u,t.id,(p_action->>'value')::boolean) on conflict(owner_id,thread_id) do update set muted=excluded.muted;
  else if t.b is not null then raise exception 'Not a business conversation.';end if;update social_private.threads set business_allowed=false where id=t.id;end if;
 else raise exception 'Unsupported social action.';end if;
end$function$;

CREATE OR REPLACE FUNCTION social_private.snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare u uuid:=social_private.owner();begin return jsonb_build_object(
 'settings',coalesce((select jsonb_build_object('share_presence',share_presence,'mode',mode) from social_private.settings where owner_id=u),'{"share_presence":false,"mode":"offline"}'::jsonb),
 'friends',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator,'presence',case when s.share_presence and s.mode<>'offline' and s.heartbeat>now()-interval '90 seconds' then s.mode else 'offline' end) order by p.username) from social_private.friends f join public.profiles p on p.id=case when f.a=u then f.b else f.a end left join social_private.settings s on s.owner_id=p.id where u in(f.a,f.b) and f.status='accepted' and not social_private.blocked(u,p.id)),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator,'incoming',f.requester<>u)) from social_private.friends f join public.profiles p on p.id=case when f.a=u then f.b else f.a end where u in(f.a,f.b) and f.status='pending' and not social_private.blocked(u,p.id)),'[]'::jsonb),
 'blocked',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator)) from social_private.blocks b join public.profiles p on p.id=b.peer_id where b.owner_id=u),'[]'::jsonb),
 'businesses',coalesce((select jsonb_agg(jsonb_build_object('id',s.shop_id,'name',s.name)) from public.shop_visits v join public.shops s using(shop_id) where v.account_id=u),'[]'::jsonb),
 'threads',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'peer',case when t.a=u then t.b else t.a end,'shop_id',t.shop_id,'name',coalesce(s.name,p.username||'#'||p.discriminator),'can_send',case when t.b is null then t.business_allowed else social_private.friendly(u,p.id) end,'muted',coalesce(c.muted,false),'unread',(select count(*) from social_private.messages m where m.thread_id=t.id and m.seq>coalesce(c.through_seq,0) and m.sender_id is distinct from u),'preview',(select case when m.image_id is not null then '📷 '||coalesce(nullif(left(m.body,95),''),'Image') else left(m.body,100) end from social_private.messages m where m.thread_id=t.id order by seq desc limit 1)) order by (select max(seq) from social_private.messages where thread_id=t.id) desc nulls last) from social_private.threads t left join public.profiles p on p.id=case when t.a=u then t.b else t.a end left join public.shops s on s.shop_id=t.shop_id left join social_private.cursors c on c.thread_id=t.id and c.owner_id=u where u=t.a or u=t.b),'[]'::jsonb));end$function$;

revoke all on function social_private.image_path(uuid,boolean) from public,anon,authenticated;
revoke all on function social_private.image_readable(text) from public,anon;grant execute on function social_private.image_readable(text) to authenticated;
create policy message_images_read on storage.objects for select to authenticated using(bucket_id='message-images' and social_private.image_readable(name));
revoke all on function public.reserve_message_image(uuid,uuid,uuid,integer,integer,integer,integer,text,text,text),public.finish_message_image(uuid,uuid),public.cleanup_message_images(uuid[]) from public,anon,authenticated;
grant execute on function public.reserve_message_image(uuid,uuid,uuid,integer,integer,integer,integer,text,text,text),public.finish_message_image(uuid,uuid),public.cleanup_message_images(uuid[]) to service_role;
grant usage on schema social_private to service_role;grant all on social_private.images to service_role;grant select on social_private.threads,social_private.friends,social_private.blocks to service_role;grant execute on function social_private.image_path(uuid,boolean),social_private.friendly(uuid,uuid),social_private.blocked(uuid,uuid) to service_role;
