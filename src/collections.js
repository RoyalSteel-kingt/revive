import {escapeHTML as esc} from './model.js';
export const deploymentFee=(amount,deployed,crossesServing)=>deployed&&crossesServing&&amount>0?Math.ceil(amount/100):0;
const requestID=()=>{if(crypto.randomUUID)return crypto.randomUUID();const b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=[...b].map(v=>v.toString(16).padStart(2,'0')).join('');return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20)};
const money=n=>Number(n).toLocaleString()+' Chroma';
let generation=0;
export async function mountCollections(root,api,owner,onChange){
 const epoch=++generation,key='revive-banking-pending-'+owner;let state,busy=false;
 const rpc=(name,body={})=>api.request('/rest/v1/rpc/'+name,{method:'POST',body});
 root.innerHTML='<p role="status">Loading Collections…</p>';
 const pending=()=>{try{return JSON.parse(localStorage.getItem(key)||'null')}catch{return null}};
 function notice(message){root.querySelector('#bank-status').textContent=message;}
 async function submit(action,recovery=null){
  if(busy)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
  let saved=false;
  try{
   const request=recovery||{p_request:requestID(),p_action:action};
   localStorage.setItem(key,JSON.stringify(request));saved=true;
   await rpc('change_banking_workspace',request);localStorage.removeItem(key);await onChange();
  }catch(e){
   if(e.status>=400&&e.status<500){localStorage.removeItem(key);saved=false;}
   busy=false;draw();notice((e.message||'Banking could not be updated.')+(saved?' Your request is saved. Recover it before making another change.':''));
  }
 }
 function options(){return [['serving','Serving'],...state.pockets.map(p=>[p.id,p.name])].map(([v,n])=>`<option value="${esc(v)}">${esc(n)}</option>`).join('');}
 function draw(){
  if(epoch!==generation||!root.isConnected)return;
  const total=state.pockets.reduce((n,p)=>n+p.balance,0),general=state.pockets.find(p=>p.general),goals=state.pockets.filter(p=>!p.general),locked=!!pending();
  root.innerHTML=`<section class="panel collections-panel"><div class="history-heading"><div><span class="eyebrow">SET ASIDE FOR WHAT MATTERS</span><h2>Collections</h2></div><strong>${money(total)}</strong></div><p>Savings stay here until you move them. Purchases use Serving only.</p><p class="notice">${state.deployed?'Deployed · Moving Chroma between Serving and Collections costs 1%, rounded up. Moving between savings goals is free.':'Back home · Transfers between your balances are free.'}</p><p id="bank-status" role="status" aria-live="polite"></p>${locked?'<p class="notice">An earlier banking request needs recovery.</p><button id="bank-recover">Recover saved request</button>':''}<div class="savings-grid"><article class="saving-card general"><span class="eyebrow">GENERAL COLLECTIONS</span><h3>${money(general.balance)}</h3><p>Savings without a specific goal.</p></article>${goals.map(p=>`<article class="saving-card"><span class="eyebrow">${p.target&&p.balance>=p.target?'GOAL REACHED':'SAVINGS GOAL'}</span><h3>${esc(p.name)}</h3><strong>${money(p.balance)}</strong>${p.target?`<progress aria-label="${esc(p.name)} savings progress" value="${Math.min(p.balance,p.target)}" max="${p.target}"></progress><p class="hint">of ${money(p.target)}</p>`:'<p class="hint">Save at your own pace.</p>'}<div class="actions"><button class="secondary" data-edit="${p.id}" ${locked?'disabled':''}>Edit</button><button class="secondary" data-close="${p.id}" ${locked?'disabled':''}>Close goal</button></div></article>`).join('')}</div><div class="actions"><button id="bank-move" ${locked?'disabled':''}>Move Chroma</button><button id="bank-create" class="secondary" ${locked?'disabled':''}>New savings goal</button></div><details><summary>Savings activity · latest 100</summary>${state.activity.map(a=>`<article class="saving-activity"><strong>${esc(a.description)}</strong><p>${a.amount?money(a.amount):'Goal update'}${a.fee?' · Fee '+money(a.fee):''}</p><time>${esc(new Date(a.created_at).toLocaleString())}</time></article>`).join('')||'<p>No savings activity yet.</p>'}</details></section>`;
  root.querySelector('#bank-recover')?.addEventListener('click',()=>submit(null,pending()));
  root.querySelector('#bank-create')?.addEventListener('click',()=>goalForm());
  root.querySelector('#bank-move')?.addEventListener('click',()=>moveForm());
  root.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>goalForm(state.pockets.find(p=>p.id===b.dataset.edit)));
  root.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>moveForm(state.pockets.find(p=>p.id===b.dataset.close)));
 }
 function open(title,html,callback){
  document.querySelector('#bank-dialog')?.remove();const dialog=document.createElement('dialog');dialog.id='bank-dialog';dialog.setAttribute('aria-labelledby','bank-dialog-title');
  dialog.innerHTML=`<form><span class="eyebrow">CHROMA / COLLECTIONS</span><h2 id="bank-dialog-title">${title}</h2>${html}<p id="bank-form-error" role="alert"></p><div class="actions"><button type="submit">Review</button><button type="button" id="bank-cancel" class="secondary">Cancel</button></div></form>`;document.body.append(dialog);dialog.querySelector('#bank-cancel').onclick=()=>dialog.close();dialog.querySelector('form').onsubmit=e=>{e.preventDefault();try{callback(new FormData(e.target),dialog)}catch(err){dialog.querySelector('#bank-form-error').textContent=err.message}};dialog.showModal();
 }
 function confirmAction(action,html){open('Confirm banking change',html,(_,d)=>{d.close();submit(action)});document.querySelector('#bank-dialog button[type=submit]').textContent='Confirm';}
 function goalForm(p){open(p?'Edit savings goal':'Make room for a goal',`<label>Goal name<input name="name" maxlength="60" required value="${esc(p?.name||'')}"></label><label>Target Chroma (optional)<input name="target" type="number" min="1" max="1000000000000" step="1" value="${p?.target||''}"></label>`,(data,d)=>{const action={type:p?'edit':'create',...(p?{id:p.id}:{}),name:String(data.get('name')).trim(),target:data.get('target')||null};d.close();confirmAction(action,`<p>${p?'Update':'Create'} <strong>${esc(action.name)}</strong>${action.target?' with a target of '+money(action.target):' without a target'}?</p><p>Your balances will stay unchanged.</p>`)});}
 function moveForm(closing){
  open(closing?'Close '+esc(closing.name):'Move your Chroma',`${closing?'<p>Move the whole goal balance before closing it. You can close a goal at any time.</p>':'<label>From<select name="from">'+options()+'</select></label>'}<label>To<select name="to">${options()}</select></label>${closing?'':'<label>Amount to move<input name="amount" type="number" required min="1" max="1000000000000" step="1"></label>'}`,(data,d)=>{
   const from=closing?.id||data.get('from'),to=data.get('to'),amount=closing?.balance??Number(data.get('amount'));
   if(from===to)throw Error('Choose different source and destination balances.');if(!Number.isSafeInteger(amount)||amount<0)throw Error('Enter a whole-Chroma amount.');
   const crosses=from==='serving'||to==='serving',fee=deploymentFee(amount,state.deployed,crosses),source=from==='serving'?state.serving:state.pockets.find(p=>p.id===from).balance;
   const debit=amount+(from==='serving'?fee:0),credit=amount-(to==='serving'?fee:0);
   if(source<debit)throw Error('Not enough Chroma in the selected source, including any fee.');if(to==='serving'&&amount>0&&credit<=0)throw Error('Amount must exceed its deployment fee.');
   const name=id=>id==='serving'?'Serving':state.pockets.find(p=>p.id===id).name;
   const action={type:closing?'close':'transfer',...(closing?{id:closing.id}:{}),from,to,amount,fee,deployed:state.deployed};
   d.close();confirmAction(action,`<dl><dt>From ${esc(name(from))}</dt><dd>${money(debit)}</dd><dt>Into ${esc(name(to))}</dt><dd>${money(credit)}</dd><dt>Deployment transfer fee</dt><dd>${money(fee)}</dd></dl>${closing?'<p>This will close the goal. Its history stays in your savings activity.</p>':''}<p>This moves your own savings; it is not new earnings.</p>`);
  });if(closing)document.querySelector('#bank-dialog [name=to]').value=state.pockets.find(p=>p.general).id;else document.querySelector('#bank-dialog [name=to]').value=state.pockets.find(p=>p.general).id;
 }
 try{state=await rpc('get_banking_workspace');if(epoch===generation)draw()}catch(e){if(epoch===generation)root.innerHTML=`<p class="notice error" role="alert">Collections unavailable: ${esc(e.message||'Please refresh banking.')}</p>`;}
}
