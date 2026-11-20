import React from 'react';
import {Button,useApp,useResource,rpc} from './core.jsx';
import {sampleNotices,liveNotices} from '../src/notice-model.js';

export function ColonyNotices(){
  const {go}=useApp();
  const r=useResource({name:'notices',seed:sampleNotices,load:()=>rpc('get_notice_feed'),change:async a=>{await rpc('read_notice',{p_id:a.id});return rpc('get_notice_feed');},reduce:(s,a)=>{const n=s.notices.find(n=>n.id===a.id);if(n)n.read_at=new Date().toISOString();return s;}});
  const notices=liveNotices(r.data),first=notices.find(n=>n.priority==='critical')||notices[0];
  if(r.phase!=='ready'||!first)return null;
  return <aside className="colony-notices" aria-label="Unread colony notices"><div><small>COLONY NOTICES · {notices.length} UNREAD</small><strong>{first.title}</strong></div><div className="actions"><Button onClick={()=>go('mail',null,{folder:'notices',notice:first.id})}>Read notice</Button><Button disabled={r.busy||!!r.pending} aria-label={'Dismiss and mark read: '+first.title} onClick={()=>r.mutate({type:'read',id:first.id})}>×</Button></div></aside>;
}
