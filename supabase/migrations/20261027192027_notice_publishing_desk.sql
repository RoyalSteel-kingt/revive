-- Publishers retain access to their permitted notices regardless of audience or schedule.
create or replace function notice_private.feed() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=auth.uid();role_name text;begin
 if u is null then raise exception 'Sign in to read Notices.' using errcode='28000';end if;
 perform 1 from public.profiles where id=u for update;if not found then raise exception 'Create your contractor profile first.';end if;
 select role into role_name from notice_private.staff where owner_id=u;
 insert into notice_private.activity values(u,now(),null) on conflict(owner_id) do update set return_since=case when notice_private.activity.last_seen<now()-interval '7 days' then notice_private.activity.last_seen when notice_private.activity.last_seen<now()-interval '30 minutes' then null else notice_private.activity.return_since end,last_seen=now();
 return jsonb_build_object('role',role_name,'return_since',(select return_since from notice_private.activity where owner_id=u),
 'notices',coalesce((select jsonb_agg(to_jsonb(n)||jsonb_build_object('read_at',r.read_at,'active',n.ends_at is null or n.ends_at>now()) order by n.starts_at desc) from notice_private.notices n left join notice_private.reads r on r.notice_id=n.id and r.owner_id=u where notice_private.visible(n,u)),'[]'::jsonb),
 'drafts',case when role_name is not null then coalesce((select jsonb_agg(to_jsonb(n) order by n.updated_at desc) from notice_private.notices n where (role_name<>'maintenance' or n.category='maintenance')),'[]'::jsonb) else '[]'::jsonb end);
end$$;
