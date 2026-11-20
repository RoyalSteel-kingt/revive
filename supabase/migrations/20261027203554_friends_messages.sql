create schema social_private;
revoke all on schema social_private from public,anon;
grant usage on schema social_private to authenticated;
create table social_private.settings(owner_id uuid primary key references public.profiles(id),share_presence boolean not null default false,mode text not null default 'offline' check(mode in ('available','away','busy','offline')),heartbeat timestamptz);
create table social_private.friends(a uuid references public.profiles(id),b uuid references public.profiles(id),requester uuid not null references public.profiles(id),status text not null check(status in ('pending','accepted')),created_at timestamptz not null default now(),primary key(a,b),check(a<b),check(requester in (a,b)));
create table social_private.blocks(owner_id uuid references public.profiles(id),peer_id uuid references public.profiles(id),primary key(owner_id,peer_id),check(owner_id<>peer_id));
create table social_private.threads(id uuid primary key default gen_random_uuid(),a uuid not null references public.profiles(id),b uuid references public.profiles(id),shop_id text references public.shops(shop_id),business_allowed boolean not null default false,check((b is not null and shop_id is null and a<b) or (b is null and shop_id is not null)));
create unique index social_player_thread on social_private.threads(a,b) where b is not null;
create unique index social_business_thread on social_private.threads(a,shop_id) where shop_id is not null;
create table social_private.messages(seq bigint generated always as identity primary key,thread_id uuid not null references social_private.threads(id),sender_id uuid references public.profiles(id),body text not null check(length(trim(body)) between 1 and 4000),created_at timestamptz not null default now(),request_id uuid not null,unique(thread_id,request_id));
create index on social_private.messages(thread_id,seq desc);
create table social_private.cursors(owner_id uuid references public.profiles(id),thread_id uuid references social_private.threads(id),through_seq bigint not null default 0,muted boolean not null default false,primary key(owner_id,thread_id));
create table social_private.requests(owner_id uuid references public.profiles(id),request_id uuid,payload jsonb not null,created_at timestamptz not null default now(),primary key(owner_id,request_id));
create index on social_private.requests(owner_id,created_at);
do $$declare t text;begin for t in select tablename from pg_tables where schemaname='social_private' loop execute format('alter table social_private.%I enable row level security',t);end loop;end$$;
revoke all on all tables in schema social_private from public,anon,authenticated;
create function social_private.blocked(u uuid,v uuid) returns boolean language sql stable set search_path='' as $$select exists(select 1 from social_private.blocks where (owner_id=u and peer_id=v) or (owner_id=v and peer_id=u))$$;
create function social_private.friendly(u uuid,v uuid) returns boolean language sql stable set search_path='' as $$select not social_private.blocked(u,v) and exists(select 1 from social_private.friends where a=least(u,v) and b=greatest(u,v) and status='accepted')$$;
create function social_private.owner() returns uuid language plpgsql stable set search_path='' as $$declare u uuid:=auth.uid();begin if u is null or not exists(select 1 from public.profiles where id=u) then raise exception 'Sign in with your contractor account.' using errcode='28000';end if;return u;end$$;
revoke all on function social_private.blocked(uuid,uuid),social_private.friendly(uuid,uuid),social_private.owner() from public,anon,authenticated;
create function social_private.snapshot() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=social_private.owner();begin return jsonb_build_object(
 'settings',coalesce((select jsonb_build_object('share_presence',share_presence,'mode',mode) from social_private.settings where owner_id=u),'{"share_presence":false,"mode":"offline"}'::jsonb),
 'friends',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator,'presence',case when s.share_presence and s.mode<>'offline' and s.heartbeat>now()-interval '90 seconds' then s.mode else 'offline' end) order by p.username) from social_private.friends f join public.profiles p on p.id=case when f.a=u then f.b else f.a end left join social_private.settings s on s.owner_id=p.id where u in(f.a,f.b) and f.status='accepted' and not social_private.blocked(u,p.id)),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator,'incoming',f.requester<>u)) from social_private.friends f join public.profiles p on p.id=case when f.a=u then f.b else f.a end where u in(f.a,f.b) and f.status='pending' and not social_private.blocked(u,p.id)),'[]'::jsonb),
 'blocked',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'handle',p.username||'#'||p.discriminator)) from social_private.blocks b join public.profiles p on p.id=b.peer_id where b.owner_id=u),'[]'::jsonb),
 'businesses',coalesce((select jsonb_agg(jsonb_build_object('id',s.shop_id,'name',s.name)) from public.shop_visits v join public.shops s using(shop_id) where v.account_id=u),'[]'::jsonb),
 'threads',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'peer',case when t.a=u then t.b else t.a end,'shop_id',t.shop_id,'name',coalesce(s.name,p.username||'#'||p.discriminator),'can_send',case when t.b is null then t.business_allowed else social_private.friendly(u,p.id) end,'muted',coalesce(c.muted,false),'unread',(select count(*) from social_private.messages m where m.thread_id=t.id and m.seq>coalesce(c.through_seq,0) and m.sender_id is distinct from u),'preview',(select left(m.body,100) from social_private.messages m where m.thread_id=t.id order by seq desc limit 1)) order by (select max(seq) from social_private.messages where thread_id=t.id) desc nulls last) from social_private.threads t left join public.profiles p on p.id=case when t.a=u then t.b else t.a end left join public.shops s on s.shop_id=t.shop_id left join social_private.cursors c on c.thread_id=t.id and c.owner_id=u where u=t.a or u=t.b),'[]'::jsonb));end$$;
revoke all on function social_private.snapshot() from public,anon;
grant execute on function social_private.snapshot() to authenticated;
create function public.get_social_workspace() returns jsonb language sql security invoker set search_path='' as $$select social_private.snapshot()$$;
revoke all on function public.get_social_workspace() from public,anon;
grant execute on function public.get_social_workspace() to authenticated;
create function social_private.conversation(p_thread uuid,p_before bigint) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=social_private.owner();begin
 if not exists(select 1 from social_private.threads where id=p_thread and u in(a,b)) then raise exception 'Conversation unavailable.';end if;
 return jsonb_build_object('messages',coalesce((select jsonb_agg(jsonb_build_object('seq',m.seq,'mine',m.sender_id=u,'body',m.body,'created_at',m.created_at) order by m.seq) from (select * from social_private.messages where thread_id=p_thread and (p_before is null or seq<p_before) order by seq desc limit 50)m),'[]'::jsonb));end$$;
revoke all on function social_private.conversation(uuid,bigint) from public,anon;
grant execute on function social_private.conversation(uuid,bigint) to authenticated;
create function public.get_social_conversation(p_thread uuid,p_before bigint default null) returns jsonb language sql security invoker set search_path='' as $$select social_private.conversation(p_thread,p_before)$$;
revoke all on function public.get_social_conversation(uuid,bigint) from public,anon;
grant execute on function public.get_social_conversation(uuid,bigint) to authenticated;
create function social_private.relationship(u uuid,p_request uuid,p_action jsonb) returns void language plpgsql set search_path='' as $$
declare v uuid;op text:=p_action->>'type';t social_private.threads;f social_private.friends;cutoff bigint;begin
 if op='settings' then
  insert into social_private.settings(owner_id,share_presence,mode,heartbeat) values(u,(p_action->>'share_presence')::boolean,p_action->>'mode',now()) on conflict(owner_id) do update set share_presence=excluded.share_presence,mode=excluded.mode,heartbeat=excluded.heartbeat;
 elsif op='request' then
  select id into v from public.profiles where username=split_part(p_action->>'handle','#',1) and discriminator=split_part(p_action->>'handle','#',2);
  if v is null or v=u or social_private.blocked(u,v) then raise exception 'This contractor is unavailable for a friend request.';end if;
  if (select count(*) from social_private.requests where owner_id=u and payload->>'type'='request' and created_at>now()-interval '1 hour')>=10 then raise exception 'Please wait before sending more friend requests.';end if;
  if exists(select 1 from social_private.friends where a=least(u,v) and b=greatest(u,v)) then raise exception 'A friendship or request already exists. Check your requests.';end if;
  insert into social_private.friends values(least(u,v),greatest(u,v),u,'pending',now());
 elsif op in ('accept','decline','cancel','remove','block','unblock','open') then
  v:=(p_action->>'peer')::uuid;if v is null or v=u or not exists(select 1 from public.profiles where id=v) then raise exception 'Contractor unavailable.';end if;
  select * into f from social_private.friends where a=least(u,v) and b=greatest(u,v);
  if op='block' then
   insert into social_private.blocks values(u,v) on conflict do nothing;
   delete from social_private.friends where a=least(u,v) and b=greatest(u,v);
   delete from housing_private.invites where (owner_id=u and guest_id=v) or (owner_id=v and guest_id=u);
  elsif op='unblock' then delete from social_private.blocks where owner_id=u and peer_id=v;
  elsif op='open' then
   if not social_private.friendly(u,v) then raise exception 'Only friends can start a conversation.';end if;
   insert into social_private.threads(a,b) values(least(u,v),greatest(u,v)) on conflict(a,b) where b is not null do nothing;
  elsif op='accept' then
   if f.status is distinct from 'pending' or f.requester=u or social_private.blocked(u,v) then raise exception 'Incoming request unavailable.';end if;
   update social_private.friends set status='accepted' where a=f.a and b=f.b;
  else
   if (op='remove' and f.status is distinct from 'accepted') or (op in('decline','cancel') and f.status is distinct from 'pending') or (op='decline' and f.requester=u) or (op='cancel' and f.requester<>u) then raise exception 'Request unavailable.';end if;
   delete from social_private.friends where a=f.a and b=f.b;
  end if;
 else raise exception 'Unsupported relationship action.';end if;
end$$;
revoke all on function social_private.relationship(uuid,uuid,jsonb) from public,anon,authenticated;
create function social_private.messaging(u uuid,p_request uuid,p_action jsonb) returns void language plpgsql set search_path='' as $$
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
   insert into social_private.messages(thread_id,sender_id,body,request_id) values(t.id,u,trim(p_action->>'body'),p_request);
  elsif op='read' then
   cutoff:=(p_action->>'through')::bigint;
   if cutoff is null or cutoff<0 or cutoff>coalesce((select max(seq) from social_private.messages where thread_id=t.id),0) then raise exception 'Invalid unread cursor.';end if;
   insert into social_private.cursors(owner_id,thread_id,through_seq) values(u,t.id,cutoff) on conflict(owner_id,thread_id) do update set through_seq=greatest(social_private.cursors.through_seq,excluded.through_seq);
  elsif op='mute' then
   insert into social_private.cursors(owner_id,thread_id,muted) values(u,t.id,(p_action->>'value')::boolean) on conflict(owner_id,thread_id) do update set muted=excluded.muted;
  else if t.b is not null then raise exception 'Not a business conversation.';end if;update social_private.threads set business_allowed=false where id=t.id;end if;
 else raise exception 'Unsupported social action.';end if;
end$$;
revoke all on function social_private.messaging(uuid,uuid,jsonb) from public,anon,authenticated;
create function social_private.change(p_request uuid,p_action jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=social_private.owner();v uuid;op text:=p_action->>'type';prior jsonb;t social_private.threads;f social_private.friends;cutoff bigint;
begin
 if p_request is null or p_action is null then raise exception 'Missing request.';end if;
 -- Pair actions, blocks and sends share an ordering lock so neither side can race a block.
 perform pg_advisory_xact_lock(27203554);
 select payload into prior from social_private.requests where owner_id=u and request_id=p_request;
 if found then if prior<>p_action then raise exception 'Request already used for another action.';end if;return social_private.snapshot();end if;
 if op in ('settings','request','accept','decline','cancel','remove','block','unblock','open') then perform social_private.relationship(u,p_request,p_action);else perform social_private.messaging(u,p_request,p_action);end if;
 insert into social_private.requests values(u,p_request,p_action,now());return social_private.snapshot();
end$$;
revoke all on function social_private.change(uuid,jsonb) from public,anon;
grant execute on function social_private.change(uuid,jsonb) to authenticated;
create function public.change_social_workspace(p_request uuid,p_action jsonb) returns jsonb language sql security invoker set search_path='' as $$select social_private.change(p_request,p_action)$$;
revoke all on function public.change_social_workspace(uuid,jsonb) from public,anon;
grant execute on function public.change_social_workspace(uuid,jsonb) to authenticated;
create function social_private.summary() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=social_private.owner();begin
 update social_private.settings set heartbeat=now() where owner_id=u and share_presence and mode<>'offline';
 return jsonb_build_object('unread',coalesce((select count(*) from social_private.messages m join social_private.threads t on t.id=m.thread_id left join social_private.cursors c on c.thread_id=t.id and c.owner_id=u where u in(t.a,t.b) and m.sender_id is distinct from u and m.seq>coalesce(c.through_seq,0) and not coalesce(c.muted,false) and (t.b is null or not social_private.blocked(u,case when t.a=u then t.b else t.a end))),0));end$$;
revoke all on function social_private.summary() from public,anon;
grant execute on function social_private.summary() to authenticated;
create function public.get_social_summary() returns jsonb language sql security invoker set search_path='' as $$select social_private.summary()$$;
revoke all on function public.get_social_summary() from public,anon;
grant execute on function public.get_social_summary() to authenticated;
-- Service bridge may answer only a conversation the player explicitly opened.
create function public.send_business_message(p_thread uuid,p_request uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$declare t social_private.threads;begin
 perform pg_advisory_xact_lock(27203554);select * into t from social_private.threads where id=p_thread and b is null for update;
 if not found or not t.business_allowed then raise exception 'Business contact permission required.';end if;
 if exists(select 1 from social_private.messages where thread_id=t.id and request_id=p_request and sender_id is null and body=p_body) then return;end if;
 insert into social_private.messages(thread_id,sender_id,body,request_id) values(t.id,null,p_body,p_request);end$$;
revoke all on function public.send_business_message(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.send_business_message(uuid,uuid,text) to service_role;
-- A block revokes housing invitations and prevents bypass through Housing's existing API.
create function social_private.guard_invite() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(27203554);if social_private.blocked(new.owner_id,new.guest_id) then raise exception 'This contractor is unavailable for an invitation.';end if;return new;end$$;
revoke all on function social_private.guard_invite() from public,anon,authenticated;
create trigger social_housing_invite before insert or update on housing_private.invites for each row execute function social_private.guard_invite();
notify pgrst,'reload schema';
