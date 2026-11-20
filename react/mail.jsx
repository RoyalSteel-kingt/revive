import React,{useState,useEffect} from 'react';
import {useResource,useApp,rpc,Panel,Button,Field,Row,Empty,Tabs,Badge,ResourceState,Notice,date} from './core.jsx';
import {sampleMail,partitions,expired,outstanding,mailCategory} from '../src/mail-model.js';
import {sampleNotices,noticeCategories} from '../src/notice-model.js';

export function Mail() {
  const {go,journey}=useApp();
  const requested=new URLSearchParams(location.search);
  const [folder,setFolder]=useState(requested.get('notice')?'notices':requested.get('folder')||'inbox');
  const [selected,setSelected]=useState(null),[query,setQuery]=useState(''),[filter,setFilter]=useState('all'),[category,setCategory]=useState('all');
  const r=useResource({name:'mail',seed:sampleMail,load:()=>rpc('get_mailbox'),change:(a)=>rpc('change_mail',{p_id:a.id,p_action:a.type}),reduce:(s,a)=>{
    const m=s.letters.find(x=>x.id===a.id);if(!m)throw Error('Letter unavailable.');
    if(a.type==='read')m.read_at=m.read_at||new Date().toISOString();
    if(a.type==='archive'){if(outstanding(m))throw Error('Collect outstanding contents first.');m.archived_at=new Date().toISOString();}
    if(a.type==='restore')m.archived_at=null;
    if(a.type==='claim'){if(expired(m))throw Error('Reward expired.');for(const x of m.attachments.filter(x=>!x.claimed_at)){x.claimed_at=new Date().toISOString();if(x.kind==='coupon')s.coupons.push({label:x.label,quantity:x.amount});}}
    return s;
  }});
  const d=r.data;
  const p=d?partitions(d.letters):null;
  const rows=(p?(folder==='archive'?p.archive:folder==='deliveries'?p.inbox.filter(x=>x.delivery):p.inbox):[]).filter(m=>(m.sender+' '+m.subject).toLowerCase().includes(query.toLowerCase())&&(category==='all'||mailCategory(m)===category)&&(filter==='all'||filter==='unread'&&!m.read_at||filter==='unclaimed'&&outstanding(m)||filter==='expiring'&&m.expires_at&&!expired(m)));
  const m=d?.letters.find(x=>x.id===selected);
  useEffect(()=>{const order=requested.get('order');if(order&&d){const letter=d.letters.find(x=>x.order_id===order);if(letter){setFolder('deliveries');setSelected(letter.id);}}},[!!d]);
  return <>
    {journey&&<aside className="journey-step" aria-label="Example delivery">
      <div>
        <strong>Example delivery · 2 of 2</strong>
        <p>{m?.delivery?'Your delivery notice is open below.':'Find your example order in Deliveries.'}</p>
      </div>
      <Button onClick={()=>go('presentation',true,{chapter:'shops'})}>Return to presentation</Button>
    </aside>}
    <div className="service-tabs"><Tabs value={folder} onChange={v=>{setFolder(v);setSelected(null);}} items={[['inbox','Inbox'],['deliveries','Deliveries'],['notices','Notices'],['archive','Archive']]}/><Button onClick={()=>go('gifts')}>Gifts</Button></div>
    {folder==='notices'?<Notices/>:<ResourceState resource={r}>{d&&<>
      <div className="toolbar"><Field label="Search mail" type="search" value={query} onChange={e=>setQuery(e.target.value)}/><Field label="Category"><select value={category} onChange={e=>setCategory(e.target.value)}>{[['all','All categories'],['account','Account & system'],['orders','Orders & services'],['rewards','Gifts & rewards'],['company','Company letters']].map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></Field><Field label="Show"><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All mail</option><option value="unread">Unread</option><option value="unclaimed">Outstanding contents</option><option value="expiring">Expiring rewards</option></select></Field><Button onClick={()=>r.reload()}>Refresh</Button><Badge>{p.inbox.filter(x=>!x.read_at).length} unread · {p.inbox.length} / 50</Badge></div>
      <div className="split-view"><Panel title={folder==='deliveries'?'Deliveries':folder==='archive'?'Archive':'Your mailbox'}>
        {rows.map(x=><Row key={x.id} title={x.subject} detail={x.sender} end={<Badge>{!x.read_at?'Unread':x.delivery?.status||'Read'}</Badge>} selected={selected===x.id} onClick={async()=>{setSelected(x.id);if(!x.read_at)await r.mutate({type:'read',id:x.id});}}/>)}
        {!rows.length&&<Empty title="No mail here">New letters and delivery notices will appear here.</Empty>}
      </Panel><Panel title={m?m.subject:'Letter details'}>
        {m?<><p className="muted">{m.sender} · {date(m.created_at)}</p><p className="letter-body">{m.body}</p>
          {m.delivery&&<div className="inset"><Badge>{m.delivery.status.replaceAll('_',' ')}</Badge><h3>Physical package</h3><p>{m.delivery.address||'Your current home'}</p><p className="muted">{m.delivery.status==='delivered'?'Waiting for collection at home.':m.delivery.eta?'Expected '+date(m.delivery.eta):'Follow its progress here.'}</p></div>}
          {m.attachments.map((a,i)=><Row key={i} title={a.label} detail={a.amount+' '+(a.kind==='chroma'?'Chroma':'coupon(s)')} end={a.claimed_at?'Claimed':expired(m)?'Expired':'Unclaimed'}/>)}
          {m.gift_id&&<Button onClick={()=>go('gifts')}>Open gift</Button>}
          {m.reward_order_id&&<Button onClick={()=>go('rewards')}>Open order help</Button>}
          <div className="actions">{m.attachments.some(a=>!a.claimed_at)&&!expired(m)&&<Button variant="primary" onClick={()=>r.mutate({type:'claim',id:m.id})}>Claim digital attachments</Button>}<Button disabled={!m.archived_at&&outstanding(m)} onClick={async()=>{if(await r.mutate({type:m.archived_at?'restore':'archive',id:m.id}))setSelected(null);}}>{m.archived_at?'Restore to inbox':'Archive letter'}</Button></div>
          {outstanding(m)&&<p className="muted">Collect outstanding contents before archiving.</p>}
        </>:<Empty title="Choose a letter">Read its contents and review attachments or delivery.</Empty>}
      </Panel></div>
      <details className="disclosure"><summary>Claimed coupons</summary>{d.coupons.length?d.coupons.map((c,i)=><Row key={i} title={c.label} end={'×'+c.quantity}/>):<p>No coupons claimed.</p>}</details>
    </>}</ResourceState>}
  </>;
}

export function Notices() {
  const [selected,setSelected]=useState(new URLSearchParams(location.search).get('notice')),[query,setQuery]=useState('');
  const [editing,setEditing]=useState(null);
  const r=useResource({name:'notices',seed:sampleNotices,load:()=>rpc('get_notice_feed'),change:async(a,id)=>{
    if(a.type==='read')await rpc('read_notice',{p_id:a.id});
    else await rpc('edit_notice',{p_id:a.record.id||id,p_expected:a.record.revision||0,p_record:a.record});
    return rpc('get_notice_feed');
  },reduce:(s,a)=>{if(a.type==='read')s.notices.find(x=>x.id===a.id).read_at=new Date().toISOString();return s;}});
  const n=r.data?.notices.find(n=>n.id===selected);
  return <ResourceState resource={r}>{r.data&&<>
    <div className="toolbar"><Field label="Search notices" type="search" value={query} onChange={e=>setQuery(e.target.value)}/><Button onClick={()=>r.reload()}>Refresh</Button>{r.data.role&&<Button onClick={()=>setEditing({sender:'Firstlight Operations',title:'',body:'',category:'update',priority:'normal',platform:'all',segment:'',status:'draft',starts_at:new Date().toISOString(),ends_at:null})}>New notice</Button>}</div>
    <div className="split-view"><Panel title="Colony notices">{r.data.notices.filter(n=>(n.title+' '+n.body).toLowerCase().includes(query.toLowerCase())).map(n=><Row key={n.id} title={n.title} detail={n.sender} end={n.read_at?'Read':'Unread'} selected={n.id===selected} onClick={()=>{setSelected(n.id);if(!n.read_at)r.mutate({type:'read',id:n.id});}}/>)}</Panel>
    <Panel title={n?.title||'Notice details'}>{n?<><Badge>{noticeCategories[n.category]||n.category}</Badge><p className="muted">{n.sender} · {date(n.starts_at)}</p><p className="letter-body">{n.body}</p>{r.data.role&&<Button onClick={()=>setEditing(n)}>Edit notice</Button>}</>:<Empty title="Choose a notice"/>}</Panel></div>
    {r.data.role&&r.data.drafts?.length>0&&<Panel title="Drafts & scheduled notices">{r.data.drafts.map(n=><Row key={n.id} title={n.title} detail={n.status} onClick={()=>setEditing(n)}/>)}</Panel>}
    {editing&&<NoticeEditor record={editing} onClose={()=>setEditing(null)} onSave={async record=>{if(await r.mutate({type:'edit',record}))setEditing(null);}}/>}
  </>}</ResourceState>;
}

import {Modal} from './core.jsx';
function NoticeEditor({record,onSave,onClose}) {
  return <Modal title="Colony notice" onClose={onClose}><form onSubmit={e=>{e.preventDefault();const f=Object.fromEntries(new FormData(e.currentTarget));onSave({...record,...f,ends_at:f.ends_at?new Date(f.ends_at).toISOString():null,starts_at:new Date(f.starts_at).toISOString()});}}>
    <Field label="Sender" name="sender" defaultValue={record.sender} required/><Field label="Title" name="title" defaultValue={record.title} required maxLength={160}/>
    <Field label="Body"><textarea name="body" defaultValue={record.body} required rows={6}/></Field>
    <div className="two-columns"><Field label="Category"><select name="category" defaultValue={record.category}>{Object.entries(noticeCategories).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field><Field label="Priority"><select name="priority" defaultValue={record.priority}><option>normal</option><option>critical</option></select></Field></div>
    <div className="two-columns"><Field label="Platform"><select name="platform" defaultValue={record.platform||'all'}><option>all</option><option>website</option><option>desktop</option><option>vr</option></select></Field><Field label="Audience segment (optional)" name="segment" defaultValue={record.segment||''}/></div>
    <Field label="Status"><select name="status" defaultValue={record.status} disabled={record.status==='published'}><option>draft</option><option>published</option></select></Field>
    <Field label="Starts" name="starts_at" type="datetime-local" defaultValue={localDateTime(record.starts_at)} required/><Field label="Ends (optional)" name="ends_at" type="datetime-local" defaultValue={localDateTime(record.ends_at)}/>
    <Button variant="primary" type="submit">Save notice</Button>
  </form></Modal>;
}

function localDateTime(value){if(!value)return '';const d=new Date(value);return new Date(d-d.getTimezoneOffset()*60000).toISOString().slice(0,16);}
