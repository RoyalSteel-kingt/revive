import React,{useState} from 'react';
import {Panel,Button,Field,Notice,Empty,Badge,DefinitionList,Modal,Row,ResourceState,useResource,useApp,api,rpc,money,date} from './core.jsx';
import {readWallet,readTransactionPage,filterTransactions} from '../src/chroma.js';
import {sampleHousing,changeSample,collateralRequired,storageDue} from '../src/housing-model.js';

const bankingExample=()=>({serving:220,deployed:false,pockets:[{id:'general',name:'General Collections',balance:600,general:true},{id:'goal',name:'A bigger home',balance:120,target:500,general:false}],activity:[],transactions:[{id:'example-ledger',delta:220,balance_before:0,balance_after:220,description:'Recovery payout',source:'expedition',kind:'movement',created_at:new Date().toISOString()}],walletError:'',historyError:'',cursor:null});
export function Chroma() {
  const [query,setQuery]=useState(''),[filter,setFilter]=useState('all'),[dialog,setDialog]=useState(null),[selected,setSelected]=useState(null);
  const r=useResource({name:'banking',seed:bankingExample,load:async owner=>{
    const [wallet,history,banking]=await Promise.allSettled([readWallet(api,owner),readTransactionPage(api,owner),rpc('get_banking_workspace')]);
    const denied=[wallet,history,banking].find(x=>x.status==='rejected'&&[401,403].includes(x.reason.status));if(denied)throw denied.reason;
    return {serving:wallet.status==='fulfilled'?wallet.value?.balance:null,walletError:wallet.status==='rejected'?wallet.reason.message:'',...history.status==='fulfilled'?history.value:{transactions:[],historyError:history.reason.message},...banking.status==='fulfilled'?banking.value:{pockets:[],activity:[],bankError:banking.reason.message}};
  },change:async(a,id)=>{
    await rpc('change_banking_workspace',{p_request:id,p_action:a});
  },reduce:(s,a)=>{
    if(a.type==='create')s.pockets.push({id:crypto.randomUUID(),name:a.name,target:a.target?Number(a.target):null,balance:0,general:false});
    else if(a.type==='edit')Object.assign(s.pockets.find(p=>p.id===a.id),{name:a.name,target:a.target?Number(a.target):null});
    else {
      const source=a.from==='serving'?{balance:s.serving}:s.pockets.find(p=>p.id===a.from);
      const dest=a.to==='serving'?{balance:s.serving}:s.pockets.find(p=>p.id===a.to);
      if(!source||!dest||a.from===a.to)throw Error('Choose different balances.');
      const amount=Number(a.amount);
      if(!Number.isSafeInteger(amount)||amount<0||source.balance<amount)throw Error('Not enough Chroma.');
      const fee=Number(a.fee||0);if(source.balance<amount+(a.from==='serving'?fee:0))throw Error('Not enough Chroma including the transfer fee.');source.balance-=amount+(a.from==='serving'?fee:0);dest.balance+=amount-(a.to==='serving'?fee:0);
      if(a.from==='serving')s.serving=source.balance;
      if(a.to==='serving')s.serving=dest.balance;
      if(a.type==='close')s.pockets=s.pockets.filter(p=>p.id!==a.id);
      s.activity.unshift({description:'Moved savings',amount,created_at:new Date().toISOString()});
    }
    return s;
  }});
  const s=r.data;
  return <ResourceState resource={r}>{s&&<>
    <div className="balance-summary"><Panel title="Serving" className="balance-panel"><div className="balance">{s.serving===null?'Unavailable':Number(s.serving).toLocaleString()} <small>Chroma</small></div><p>Your available spending balance.</p><Notice error>{s.walletError}</Notice></Panel><Panel title="Collections"><div className="balance">{s.pockets.reduce((n,p)=>n+p.balance,0).toLocaleString()} <small>Chroma</small></div><p>Set aside for another day.</p><Notice error>{s.bankError}</Notice><div className="actions"><Button disabled={!s.pockets.length} onClick={()=>setDialog({type:'transfer'})}>Move Chroma</Button><Button disabled={!!s.bankError} onClick={()=>setDialog({type:'create'})}>New savings goal</Button></div></Panel></div>
    <Panel title="Savings goals">{s.pockets.map(p=><Row key={p.id} title={p.name} detail={p.target?'Target '+money(p.target):null} end={money(p.balance)}>{p.target&&<progress aria-label={p.name} value={Math.min(p.balance,p.target)} max={p.target}/>}{!p.general&&<div className="actions"><Button onClick={()=>setDialog({type:'edit',...p})}>Edit</Button><Button onClick={()=>setDialog({type:'close',...p})}>Close goal</Button></div>}</Row>)}{!s.pockets.length&&<Empty title="No savings goals"/>}</Panel>
    <Panel title="Activity" action={<Button onClick={()=>r.reload()}>Refresh</Button>}><div className="toolbar"><Field label="Find a transaction" type="search" value={query} onChange={e=>setQuery(e.target.value)}/><Field label="Type"><select value={filter} onChange={e=>setFilter(e.target.value)}>{[['all','All activity'],['credit','Credits'],['debit','Debits'],['savings','Savings']].map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field></div>
      <Notice error>{s.historyError}</Notice>
      {filterTransactions(s.transactions,{search:query,type:filter}).map(t=><Row key={t.id} title={t.description} detail={date(t.created_at)} end={(t.delta>0?'+':'')+money(t.delta)} onClick={()=>setSelected(t)}/>)}
      {!s.transactions.length&&<Empty title="No transactions to show"/>}
      {s.cursor&&<LoadMoreTransactions data={s} onUpdate={items=>{r.updateData(old=>({...old,transactions:[...old.transactions,...items.transactions],cursor:items.cursor}));}}/>}
    </Panel>
    {!!s.activity?.length&&<details className="disclosure"><summary>Savings activity</summary>{s.activity.map((a,i)=><Row key={i} title={a.description} detail={date(a.created_at)} end={money(a.amount)}/>)}</details>}
    {selected&&<Modal title="Transaction record" onClose={()=>setSelected(null)}><DefinitionList rows={[['Description',selected.description],['Change',money(selected.delta)],['Balance before',money(selected.balance_before)],['Balance after',money(selected.balance_after)],['Source',selected.source],['Date',date(selected.created_at)]]}/></Modal>}
    {dialog&&<BankingDialog state={s} action={dialog} resource={r} onClose={()=>setDialog(null)}/>}
  </>}</ResourceState>;
}
function LoadMoreTransactions({data,onUpdate}) {
  const [busy,setBusy]=useState(false),[error,setError]=useState(''),[,render]=useState(0);
  const load=async()=>{setBusy(true);try{const {api}=await import('./core.jsx');const user=await api.user();onUpdate(await readTransactionPage(api,user.id,data.cursor));render(n=>n+1);}catch(e){setError(e.message);}finally{setBusy(false);}};
  return <><Button onClick={load} busy={busy}>Load earlier transactions</Button><Notice error>{error}</Notice></>;
}
function BankingDialog({state,action,resource,onClose}) {
  const [review,setReview]=useState(null);
  const names=[['serving','Serving'],...state.pockets.map(p=>[p.id,p.name])];
  return <Modal title={action.type==='create'?'New savings goal':action.type==='edit'?'Edit savings goal':action.type==='close'?'Close savings goal':'Move Chroma'} onClose={onClose}>
    {review?<><DefinitionList rows={Object.entries(review).filter(([k])=>!['id','type','deployed'].includes(k)).map(([k,v])=>[({from:'From',to:'To',amount:'Amount',fee:'Fee',name:'Goal name',target:'Target'})[k]||k,['from','to'].includes(k)?names.find(([id])=>id===v)?.[1]||v:['amount','fee','target'].includes(k)&&v?money(v):String(v??'—')])}/><Button variant="primary" onClick={async()=>{if(await resource.mutate(review))onClose();}} busy={resource.busy}>Confirm</Button><Notice error>{resource.error}</Notice></>:<form onSubmit={e=>{
      e.preventDefault();const f=Object.fromEntries(new FormData(e.currentTarget));
      if(['create','edit'].includes(action.type)){setReview({type:action.type,...(action.id?{id:action.id}:{}),name:f.name.trim(),target:f.target||null});return;}
      const amount=action.type==='close'?action.balance:Number(f.amount),from=action.type==='close'?action.id:f.from;
      if(from===f.to)return;
      const fee=state.deployed&&(from==='serving'||f.to==='serving')?Math.ceil(amount/100):0;
      setReview({type:action.type,...(action.type==='close'?{id:action.id}:{}),from,to:f.to,amount,fee,deployed:state.deployed});
    }}>
      {['create','edit'].includes(action.type)?<><Field label="Goal name" name="name" maxLength={60} defaultValue={action.name||''} required/><Field label="Target Chroma (optional)" name="target" type="number" min="1" max="1000000000000" defaultValue={action.target||''}/></>:<>
        {action.type!=='close'&&<Field label="From"><select name="from">{names.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></Field>}
        <Field label="To"><select name="to" defaultValue={state.pockets.find(p=>p.general)?.id}>{names.filter(([id])=>id!==action.id).map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></Field>
        {action.type!=='close'?<Field label="Amount" type="number" name="amount" min="1" max="1000000000000" required/>:<p>{money(action.balance)} will move before the goal closes.</p>}
        {state.deployed&&<Notice>Transfers involving Serving cost 1% during deployment, rounded up.</Notice>}
      </>}
      <Button variant="primary" type="submit">Review change</Button>
    </form>}
  </Modal>;
}

export function Housing() {
  const [review,setReview]=useState(null),[payment,setPayment]=useState('chroma'),[pledges,setPledges]=useState([]),[handle,setHandle]=useState('');
  const r=useResource({name:'housing',seed:sampleHousing,load:()=>rpc('get_housing_workspace'),change:(action,id)=>rpc('change_housing_workspace',{p_request:id,p_action:action}),reduce:changeSample});
  const s=r.data;
  function begin(a){const home=[...r.data.offers,...r.data.reclaim].find(h=>h.unit_id===a.unit);setPayment('chroma');setPledges([]);setReview({...a,revision:r.data.revision,...home?{price:home.price,storage_fee:r.data.storage_fee}:{},...a.type==='settle'?{price:r.data.home.debt}:{},...a.type==='pay_storage'?{price:r.data.storage.due}:{},...['store','withdraw'].includes(a.type)?{storage_fee:r.data.storage_fee}:{}});}
  const offered=s&&review?.unit?[...s.offers,...s.reclaim].find(h=>h.unit_id===review.unit):null;
  return <ResourceState resource={r}>{s&&<>
    <Panel title="Your home" className="housing-address" action={<Button onClick={()=>r.reload()}>Refresh</Button>}>{s.home?<><h3>{s.home.title}</h3><p className="home-address">{s.home.address}</p><p className="muted">{s.home.description}</p><DefinitionList rows={[['Storage',s.home.slots+' slots'],['Outstanding collateral',money(s.home.debt)]]}/>{s.home.debt>0&&<Button onClick={()=>begin({type:'settle'})}>Settle collateral</Button>}</>:<Empty title="No home assigned">Available homes appear in your directory.</Empty>}</Panel>
    <Panel title="Storage unit"><strong>{s.storage?(s.storage.locked?'Payment overdue':'Accessible'):'Not rented'}</strong><p>{money(s.storage?.fee||s.storage_fee)} every two weeks.</p>{s.storage?<><p>Next billing boundary {date(s.storage.due_at)}</p>{s.storage.locked&&<Button onClick={()=>begin({type:'pay_storage'})}>Review payment</Button>}</>:<p className="muted">Store an eligible item below to open a unit. First payment is due after 14 days.</p>}<Badge>{money(s.balance)} available</Badge></Panel>
    <Panel title="Your belongings">{s.items.map(i=><Row key={i.id} title={i.name} detail={i.condition+'% condition · '+(i.rental?'Rental':i.kind==='storage'?'Storage unit':i.kind)} end={i.value?money(i.value):null}>{i.kind==='storage'?<Button disabled={s.storage?.locked} onClick={()=>begin({type:'withdraw',id:i.id})}>Withdraw</Button>:i.kind==='available'&&i.position==='home'?<Button disabled={s.storage?.locked} onClick={()=>begin({type:'store',id:i.id})}>Store</Button>:null}</Row>)}{!s.items.length&&<Empty title="No stored belongings"/>}</Panel>
    <Panel title="Invitations"><form className="inline-form" onSubmit={e=>{e.preventDefault();begin({type:'invite',handle});}}><Field label="Contractor name and tag" placeholder="Name#123456" value={handle} pattern="[A-Za-z][A-Za-z0-9_]{2,23}#[0-9]{6}" required onChange={e=>setHandle(e.target.value)}/><Button type="submit" disabled={!s.home}>Invite</Button></form>{s.invites.map(i=><Row key={i.guest_id} title={i.handle}><Button onClick={()=>begin({type:'revoke',guest:i.guest_id})}>Revoke invitation</Button></Row>)}</Panel>
    <details className="disclosure"><summary>Available homes · {s.offers.length}</summary><div className="card-grid">{s.offers.map(h=><Panel key={h.unit_id} title={h.title}><p>{h.description}</p><DefinitionList rows={[['Storage',h.slots+' slots'],['Price',money(h.price)]]}/><Button disabled={s.home?.debt>0} onClick={()=>begin({type:'move',unit:h.unit_id})}>Review home</Button></Panel>)}</div></details>
    {s.reclaim.length>0&&<Panel title="Previously occupied homes">{s.reclaim.map(h=><Row key={h.unit_id} title={h.title} detail={'Protected until '+date(h.priority_until)}><Button onClick={()=>begin({type:'reclaim',unit:h.unit_id})}>Review return</Button></Row>)}</Panel>}
    {s.visiting.length>0&&<Panel title="Invited places">{s.visiting.map((h,i)=><Row key={i} title={h.title} detail={h.address}/>)}</Panel>}
    {review&&<Modal title="Review housing change" onClose={()=>setReview(null)}><p>{offered?'Move to '+offered.title+'? Your current home and invitations will update.':review.type==='invite'?'Share your private home address with '+review.handle+'?':review.type==='revoke'?'Remove this guest’s access to your address?':review.type==='settle'?'Pay '+money(s.home.debt)+' to recover your collateral?':review.type==='pay_storage'?'Pay '+money(s.storage.due)+' to restore storage access?':review.type==='store'?'Move this item into storage? '+money(s.storage?.fee||s.storage_fee)+' is billed every two weeks.':'Return this item to home storage?'}</p>
      {review.type==='move'&&<><Field label="Payment"><select value={payment} onChange={e=>setPayment(e.target.value)}><option value="chroma">Pay {money(offered?.price)}</option><option value="collateral">Pledge collateral</option></select></Field>{payment==='collateral'&&<><p>Pledge at least {money(collateralRequired(offered.price))}.</p>{s.items.filter(i=>i.kind==='available'&&!i.rental&&i.value).map(i=><label className="check" key={i.id}><input type="checkbox" checked={pledges.includes(i.id)} onChange={e=>setPledges(e.target.checked?[...pledges,i.id]:pledges.filter(x=>x!==i.id))}/>{i.name} · {money(i.value)}</label>)}</>}</>}
      <Button variant="primary" busy={r.busy} onClick={async()=>{if(await r.mutate({...review,...(review.type==='move'?{payment,ids:pledges}:{})}))setReview(null);}}>Confirm change</Button><Notice error>{r.error}</Notice>
    </Modal>}
  </>}</ResourceState>;
}
