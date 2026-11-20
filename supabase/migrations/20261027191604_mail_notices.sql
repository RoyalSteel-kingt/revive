create schema notice_private;
revoke all on schema notice_private from public,anon;
grant usage on schema notice_private to authenticated;
create table notice_private.staff(owner_id uuid primary key references public.profiles(id),role text not null check(role in ('owner','editor','maintenance')));
create table notice_private.audience_members(owner_id uuid references public.profiles(id),segment text,primary key(owner_id,segment));
create table notice_private.notices(id uuid primary key, sender text not null, title text not null check(length(title) between 1 and 160),body text not null check(length(body) between 1 and 12000),category text not null check(category in ('maintenance','rules','update','account','company')),priority text not null check(priority in ('normal','critical')),platform text not null check(platform in ('all','website','desktop','vr')),segment text,starts_at timestamptz not null,ends_at timestamptz,status text not null check(status in ('draft','published')),revision integer not null default 1,updated_at timestamptz not null default now(),check(ends_at is null or ends_at>starts_at));
create table notice_private.reads(owner_id uuid references public.profiles(id),notice_id uuid references notice_private.notices(id),read_at timestamptz not null default now(),primary key(owner_id,notice_id));
create table notice_private.activity(owner_id uuid primary key references public.profiles(id),last_seen timestamptz not null default now(),return_since timestamptz);
create index on notice_private.notices(status,starts_at);
create table notice_private.revisions(notice_id uuid references notice_private.notices(id),revision integer,editor_id uuid,changed_at timestamptz not null default now(),record jsonb not null,primary key(notice_id,revision));
do $$declare t text;begin for t in select tablename from pg_tables where schemaname='notice_private' loop execute format('alter table notice_private.%I enable row level security',t);end loop;end$$;
revoke all on all tables in schema notice_private from public,anon,authenticated;
create function notice_private.visible(n notice_private.notices,u uuid) returns boolean language sql stable set search_path='' as $$select n.status='published' and n.starts_at<=now() and n.platform in ('all','website') and (n.segment is null or exists(select 1 from notice_private.audience_members where owner_id=u and segment=n.segment))$$;
revoke all on function notice_private.visible(notice_private.notices,uuid) from public,anon,authenticated;
create function notice_private.feed() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=auth.uid();role_name text;begin
 if u is null then raise exception 'Sign in to read Notices.' using errcode='28000';end if;
 perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
 select role into role_name from notice_private.staff where owner_id=u;
 insert into notice_private.activity values(u,now(),null) on conflict(owner_id) do update set return_since=case when notice_private.activity.last_seen<now()-interval '7 days' then notice_private.activity.last_seen when notice_private.activity.last_seen<now()-interval '30 minutes' then null else notice_private.activity.return_since end,last_seen=now();
 return jsonb_build_object('role',role_name,'return_since',(select return_since from notice_private.activity where owner_id=u),
 'notices',coalesce((select jsonb_agg(to_jsonb(n)||jsonb_build_object('read_at',r.read_at,'active',n.ends_at is null or n.ends_at>now()) order by n.starts_at desc) from notice_private.notices n left join notice_private.reads r on r.notice_id=n.id and r.owner_id=u where notice_private.visible(n,u)),'[]'::jsonb),
 'drafts',case when role_name is not null then coalesce((select jsonb_agg(to_jsonb(n) order by n.updated_at desc) from notice_private.notices n where (n.status='draft' or n.starts_at>now()) and (role_name<>'maintenance' or n.category='maintenance')),'[]'::jsonb) else '[]'::jsonb end);
end$$;
revoke all on function notice_private.feed() from public,anon;
grant execute on function notice_private.feed() to authenticated;
create function public.get_notice_feed() returns jsonb language sql security invoker set search_path='' as $$select notice_private.feed()$$;
revoke all on function public.get_notice_feed() from public,anon;
grant execute on function public.get_notice_feed() to authenticated;
create function notice_private.mark_read(p_id uuid) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=auth.uid();begin
 if u is null then raise exception 'Sign in first.' using errcode='28000';end if;
 perform 1 from public.profiles where id=u for update;
 if not exists(select 1 from notice_private.notices n where n.id=p_id and notice_private.visible(n,u)) then raise exception 'Notice unavailable.';end if;
 insert into notice_private.reads values(u,p_id,now()) on conflict do nothing;
end$$;
revoke all on function notice_private.mark_read(uuid) from public,anon;
grant execute on function notice_private.mark_read(uuid) to authenticated;
create function public.read_notice(p_id uuid) returns void language sql security invoker set search_path='' as $$select notice_private.mark_read(p_id)$$;
revoke all on function public.read_notice(uuid) from public,anon;
grant execute on function public.read_notice(uuid) to authenticated;
create function notice_private.publish(p_id uuid,p_expected integer,p_record jsonb,p_trusted boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();role_name text;old notice_private.notices;n notice_private.notices;begin
 if not p_trusted then select role into role_name from notice_private.staff where owner_id=u;if role_name is null then raise exception 'Notice publishing permission required.' using errcode='42501';end if;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,27191604));
 select * into old from notice_private.notices where id=p_id for update;
 n:=jsonb_populate_record(null::notice_private.notices,p_record);
 if role_name='maintenance' and (n.category is distinct from 'maintenance' or (old.id is not null and old.category<>'maintenance')) then raise exception 'Maintenance publishers can edit maintenance notices only.';end if;
 if old.id is not null and old.revision is distinct from p_expected then raise exception 'Notice changed. Reload before editing.' using errcode='40001';end if;
 if old.id is null and p_expected is distinct from 0 then raise exception 'Notice not found.';end if;
 if n.sender is null or length(trim(n.sender)) not between 1 and 100 then raise exception 'Sender is required.';end if;
 if old.id is not null and old.status='published' and (n.status<>'published' or n.starts_at<>old.starts_at) then raise exception 'Published notices retain their original publication time and history.';end if;
 if old.id is not null then insert into notice_private.revisions values(old.id,old.revision,u,now(),to_jsonb(old));end if;
 insert into notice_private.notices values(p_id,n.sender,n.title,n.body,n.category,n.priority,n.platform,nullif(n.segment,''),n.starts_at,n.ends_at,n.status,coalesce(old.revision,0)+1,now()) on conflict(id) do update set sender=excluded.sender,title=excluded.title,body=excluded.body,category=excluded.category,priority=excluded.priority,platform=excluded.platform,segment=excluded.segment,ends_at=excluded.ends_at,status=excluded.status,starts_at=excluded.starts_at,revision=excluded.revision,updated_at=now() returning * into n;
 -- A revision never clears acknowledgement or creates a second popup.
 return to_jsonb(n);
end$$;
revoke all on function notice_private.publish(uuid,integer,jsonb,boolean) from public,anon,authenticated;
create function notice_private.edit(p_id uuid,p_expected integer,p_record jsonb) returns jsonb language sql security definer set search_path='' as $$select notice_private.publish(p_id,p_expected,p_record,false)$$;
revoke all on function notice_private.edit(uuid,integer,jsonb) from public,anon;
grant execute on function notice_private.edit(uuid,integer,jsonb) to authenticated;
create function public.edit_notice(p_id uuid,p_expected integer,p_record jsonb) returns jsonb language sql security invoker set search_path='' as $$select notice_private.edit(p_id,p_expected,p_record)$$;
revoke all on function public.edit_notice(uuid,integer,jsonb) from public,anon;
grant execute on function public.edit_notice(uuid,integer,jsonb) to authenticated;
create function public.issue_notice(p_id uuid,p_expected integer,p_record jsonb) returns jsonb language sql security definer set search_path='' as $$select notice_private.publish(p_id,p_expected,p_record,true)$$;
revoke all on function public.issue_notice(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.issue_notice(uuid,integer,jsonb) to service_role;
notify pgrst,'reload schema';
