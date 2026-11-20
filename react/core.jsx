import React, {createContext, useContext, useEffect, useId, useRef, useState} from 'react';
import {ReviveBackend} from '../src/backend.js';
import {requestID} from '../src/real-rewards-model.js';

export const api = new ReviveBackend();
export const rpc = (name, body = {}) => api.request('/rest/v1/rpc/' + name, {method:'POST', body});
export const money = n => Number(n || 0).toLocaleString() + ' Chroma';
export const date = value => value ? new Date(value).toLocaleString() : '—';
export const AppContext = createContext(null);
export const useApp = () => useContext(AppContext);
export function readLocal(key, seed) {
  try { return JSON.parse(localStorage.getItem(key)) ?? seed(); }
  catch { return seed(); }
}
export function saveLocal(key, data) { localStorage.setItem(key, JSON.stringify(data)); }

export function Button({variant='secondary', children, className='', busy=false, disabled=false, ...props}) {
  return <button type="button" className={'button '+variant+' '+className} {...props}
    disabled={busy||disabled} data-busy={busy||undefined} aria-busy={busy||undefined}>
    {busy&&<Throbber/>}{children}
  </button>;
}
function Throbber() {
  return <span className="throbber" aria-hidden="true"/>;
}
export function LoadingState({children='Loading your information…'}) {
  return <Panel><div className="loading-state" role="status"><Throbber/>{children}</div></Panel>;
}
export function Panel({title, action, children, className=''}) {
  return <section className={'panel '+className}>
    {(title || action) && <div className="panel-head"><h2>{title}</h2>{action}</div>}
    <div className="panel-body">{children}</div>
  </section>;
}
export function Empty({title, children}) {
  return <div className="empty"><h3>{title}</h3>{children && <p>{children}</p>}</div>;
}
export function Notice({children, error=false}) {
  return children ? <div className={'notice '+(error?'error':'')} role={error?'alert':'status'}>{children}</div> : null;
}
export function Badge({children}) { return <span className="badge">{children}</span>; }
export function Field({label, children, ...props}) {
  const id=useId();
  return <label className="field" htmlFor={id}><span>{label}</span>{children ? React.cloneElement(children, {id}) : <input id={id} {...props}/>}</label>;
}
export function Tabs({items, value, onChange, label='View'}) {
  return <div className="tabs" aria-label={label}>{items.map(([id,name])=><Button key={id} aria-pressed={value===id} onClick={()=>onChange(id)}>{name}</Button>)}</div>;
}
export function Row({title, detail, end, children, selected=false, onClick}) {
  const content=<><span className="row-copy"><strong>{title}</strong>{detail&&<small>{detail}</small>}</span>{end&&<span className="row-end">{end}</span>}</>;
  return <div className={'row-wrap '+(selected?'selected':'')}>{onClick?<button type="button" className="row" aria-pressed={selected} onClick={onClick}>{content}</button>:<div className="row">{content}</div>}{children&&<div className="row-extra">{children}</div>}</div>;
}
export function DefinitionList({rows}) {
  return <dl className="data">{rows.filter(([,v])=>v!==undefined&&v!==null).map(([k,v])=><div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}</dl>;
}
export function Modal({title, children, onClose}) {
  const ref=useRef(null), heading=useId();
  useEffect(()=>{
    const dialog=ref.current;
    const focus=document.activeElement;
    dialog.showModal();
    return ()=>{ dialog.close(); if(focus?.isConnected) focus.focus(); };
  },[]);
  return <dialog ref={ref} aria-labelledby={heading} onCancel={e=>{e.preventDefault();onClose();}} onClick={e=>{if(e.target===e.currentTarget)onClose();}}>
    <div className="dialog-head"><h2 id={heading}>{title}</h2><Button aria-label="Close dialog" onClick={onClose}>×</Button></div>
    <div className="dialog-body">{children}</div>
  </dialog>;
}
export function useController(Controller) {
  const [,render]=useState(0);
  const [controller]=useState(()=>new Controller(api,()=>render(n=>n+1)));
  useEffect(()=>{controller.load();return ()=>{controller.epoch++;};},[controller]);
  return [controller.state,controller];
}

/* Each resource keeps the original request until its outcome is known. */
export function useResource({name,seed,load,change,reduce,persistAction=a=>a}) {
  const {sample,sessionVersion,notify}=useApp();
  const [state,setState]=useState({phase:'loading',data:null,error:'',busy:false,pending:null});
  const ref=useRef(state), generation=useRef(0), lock=useRef(false), owner=useRef(null);
  const storageKey='firstlight-react-sample/'+name;
  const pendingKey=()=> 'firstlight-request/'+owner.current+'/'+name;
  function update(values) {ref.current={...ref.current,...values};setState(ref.current);}
  async function reload(quiet=false) {
    if(lock.current)return;
    const epoch=++generation.current;
    if(!quiet)update({phase:'loading',error:'',data:null});
    try {
      let data, pending=null;
      if(sample) { owner.current='sample'; data=readLocal(storageKey,seed); }
      else {
        if(!api.session){update({phase:'signed_out',data:null,pending:null});return;}
        owner.current=(await api.user()).id;
        pending=readLocal(pendingKey(),()=>null);
        data=await load(owner.current);
      }
      if(epoch===generation.current)update({phase:'ready',data,pending,error:''});
    } catch(error) {
      if(epoch!==generation.current)return;
      if([401,403].includes(error.status))api.clearSession();
      update({phase:api.session||sample?'error':'signed_out',data:null,error:error.message});
    }
  }
  async function mutate(action, retry=false) {
    if(lock.current)return false;
    if(!ref.current.data)return false;
    if(ref.current.pending&&!retry){update({error:'Check the previous request before making another change.'});return false;}
    lock.current=true;
    const epoch=generation.current;
    update({busy:true,error:''});
    let pending=ref.current.pending;
    try {
      let next;
      if(sample) {
        next=await reduce(structuredClone(ref.current.data),action);
        saveLocal(storageKey,next);
      } else {
        if(!retry){
          pending={request:requestID(),action:persistAction(action,ref.current.data)};
          saveLocal(pendingKey(),pending);
          if(JSON.stringify(readLocal(pendingKey(),()=>null))!==JSON.stringify(pending))throw Error('Enable browser storage to recover interrupted changes.');
          update({pending});
        }
        next=await change(retry?pending.action:action,pending.request,ref.current.data);
        localStorage.removeItem(pendingKey());
        update({pending:null});
        if(next===undefined)next=await load(owner.current);
      }
      if(epoch===generation.current)update({data:next,phase:'ready',pending:null,error:''});
      window.dispatchEvent(new CustomEvent('firstlight-resource',{detail:name}));
      notify(sample?'Example updated.':'Saved.');
      return next;
    } catch(error) {
      if([400,401,403,404,409,422].includes(error.status)){
        localStorage.removeItem(pendingKey()); update({pending:null});
      }
      if([401,403].includes(error.status)){
        api.clearSession();update({phase:'signed_out',data:null});
      }
      if(epoch===generation.current)update({error:error.message+(ref.current.pending&&!sample?' Check the saved request before retrying.':'')});
      return false;
    } finally {lock.current=false;if(epoch===generation.current)update({busy:false});else reload();}
  }
  useEffect(()=>{
    update({phase:'loading',data:null,pending:null,error:''});
    reload();
    const visible=()=>{if(!document.hidden)reload(true);};
    const interval=setInterval(()=>{if(!document.hidden)reload(true);},30000);
    const changed=e=>{if(e.detail===name)reload(true);};
    document.addEventListener('visibilitychange',visible);
    window.addEventListener('firstlight-resource',changed);
    return ()=>{generation.current++;clearInterval(interval);document.removeEventListener('visibilitychange',visible);window.removeEventListener('firstlight-resource',changed);};
  },[sample,sessionVersion]);
  return {...state, reload, mutate, updateData:fn=>update({data:fn(ref.current.data)})};
}
export function ResourceState({resource, children}) {
  const {go}=useApp();
  if(resource.phase==='signed_out')return <Panel title="Connect your account"><p>Sign in to access your saved information.</p><div className="actions"><Button variant="primary" onClick={()=>go('account')}>Sign in</Button><Button onClick={()=>go(null,true)}>Explore example</Button></div><Notice error>{resource.error}</Notice></Panel>;
  if(resource.phase==='loading')return <LoadingState/>;
  if(resource.phase==='error')return <Panel title="Unable to load this service"><Notice error>{resource.error}</Notice><Button onClick={()=>resource.reload()}>Try again</Button></Panel>;
  return <><Notice error>{resource.error}</Notice>{resource.pending&&!resource.busy&&<Notice>A previous change needs checking. <Button onClick={()=>resource.mutate(null,true)}>Check saved request</Button></Notice>}<span className="visually-hidden" role="status">{resource.busy?'Saving change…':''}</span><fieldset className="workspace-lock" disabled={resource.busy||!!resource.pending} aria-busy={resource.busy||undefined}>{children}</fieldset></>;
}
