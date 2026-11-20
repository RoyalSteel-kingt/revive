import React,{useState} from 'react';
import {Panel,Button,Field,Notice,Empty,Badge,DefinitionList,Modal,Row,Tabs,ResourceState,useResource,useController,useApp,api,rpc} from './core.jsx';
import {IdentityController,identitySummary} from '../src/identity.js';
import {seed,act,definitions,slots,categories,weight,capacity,movement,maxTransfer} from '../src/inventory-workspace-model.js';
import {fromSnapshot,wireAction} from '../src/inventory-live.js';
import {ResidentServices} from './resident-services.jsx';

export function Account({titleRef}) {
  const {sample,go,bumpSession}=useApp();
  const [s,c]=useController(IdentityController);
  const [email,setEmail]=useState(''),[code,setCode]=useState(''),[name,setName]=useState('');
  const busy=['loading','working'].includes(s.phase);
  const identity=sample?{linked:true,handle:'Firstlight#041200',sf:'unregistered'}:identitySummary(s.record);
  async function verify(e){e.preventDefault();await c.verify(code);bumpSession();}
  return <div className="resident-entry">
    <section className="resident-intro" aria-labelledby="resident-title">
      <h1 id="resident-title" tabIndex={-1} ref={titleRef}>Firstlight Online</h1>
      <p>Shop for supplies, manage your belongings, and keep up with life in the colony.</p>
      <div className="actions">
        {sample
          ? <><Button variant="primary" onClick={()=>go('shops')}>Browse shops</Button><Button onClick={()=>go('account',false,{},'resident-account')}>Use my account</Button></>
          : s.user?<Button variant="primary" onClick={()=>go('shops')}>Browse shops</Button>:<Button variant="primary" onClick={()=>go('account',true)}>Explore example</Button>}
        <Button onClick={()=>go('presentation')}>Take the tour</Button>
        {!sample&&!s.user&&<a className="resident-sign-in" href="#resident-account">Sign in</a>}
      </div>
    </section>
    <ResidentServices/>
    <section className="resident-desk" id="resident-account" tabIndex={-1} aria-label="Resident account">
    <Panel title={sample||s.user?'Resident identity':'Sign in'}>
      <Notice error>{s.error}</Notice>
      {sample||s.user ? <>
        <div className="identity"><div className="avatar">{(identity.handle||s.user?.email||'F').slice(0,1)}</div><div><h3>{identity.handle||s.user?.email}</h3><Badge>{sample?'Example resident':'Connected'}</Badge></div></div>
        <DefinitionList rows={[['Colony','Firstlight'],['Foundation',identity.sf==='registered'?'Registered':'Registration pending']]}/>
        {!sample&&s.record&&!identity.linked&&s.record.can_create&&<form onSubmit={async e=>{e.preventDefault();await c.create(name);}}><Field label="Public contractor name" value={name} onChange={e=>setName(e.target.value)} pattern="[A-Za-z][A-Za-z0-9_]{2,23}" required/><Button type="submit" variant="primary" disabled={busy}>Create profile</Button></form>}
        {!sample&&<div className="actions"><Button disabled={busy} onClick={()=>c.load()}>Refresh identity</Button><Button onClick={async()=>{await c.signOut();bumpSession();}}>Sign out</Button></div>}
      </>:<>
        <p>Use your Revive email to open your Firstlight account.</p>
        <form onSubmit={e=>{e.preventDefault();c.sendCode(email.trim());}}>
          <Field label="Email address" type="email" autoComplete="email" value={email} required onChange={e=>setEmail(e.target.value)}/>
          <Button variant="primary" type="submit" busy={busy}>{busy?'Connecting…':s.phase==='code_sent'?'Send another code':'Send sign-in code'}</Button>
        </form>
        {s.phase==='code_sent'&&<form onSubmit={verify}><Field label="Email verification code" autoComplete="one-time-code" inputMode="numeric" value={code} required pattern="[0-9]{6,10}" onChange={e=>setCode(e.target.value)}/><Button variant="primary" type="submit" busy={busy}>Verify code</Button></form>}
      </>}
    </Panel>
    </section>
  </div>;
}

export function Inventory() {
  const {sample}=useApp();
  const [selected,setSelected]=useState(null),[query,setQuery]=useState(''),[category,setCategory]=useState('all'),[review,setReview]=useState(null),[qty,setQty]=useState(1),[storageView,setStorageView]=useState('person');
  const r=useResource({
    name:'inventory',seed,persistAction:(a,s)=>({requestBody:{p_expected_revision:s.revision,p_action:wireAction(s,a)}}),
    load:async()=>fromSnapshot(await rpc('get_inventory_workspace')),
    change:async(action,id,state)=>{
      if(action.type==='consolidate')return fromSnapshot(await rpc('get_inventory_workspace'));
      return fromSnapshot(await rpc('change_inventory_workspace',{p_request_id:id,...(action.requestBody||{p_expected_revision:state.revision,p_action:wireAction(state,action)})}));
    },
    reduce:act
  });
  const data=r.data;
  const selectedItem=data&&selected ? (selected.where==='equipment'?data.equipment[selected.id]:data[selected.where]?.find(i=>i.id===selected.id)):null;
  const definition=selectedItem?definitions[selectedItem.def]:null;
  function rows(where) {
    return data[where].filter(i=>(category==='all'||definitions[i.def]?.category===category)&&definitions[i.def]?.name.toLowerCase().includes(query.toLowerCase())).map(i=><Row key={i.id} title={definitions[i.def]?.name||i.def} detail={i.qty+' unit(s) · '+(i.properties.condition??100)+'% condition'} end={(definitions[i.def].weight*i.qty).toLocaleString()+' lb'} selected={selected?.id===i.id&&selected.where===where} onClick={()=>setSelected({where,id:i.id})}/>);
  }
  const isCarried=storageView==='person';
  const isEquipment=storageView==='equipment';
  const contents=data&&!isEquipment?rows(storageView):[];
  const storageLabel=isCarried?'Backpack':isEquipment?'Equipped gear':'Home storage';
  return <ResourceState resource={r}>{data&&<>
    <div className="inventory-overview">
      <Tabs label="Inventory locations" items={[['person','Backpack'],['home','Home storage'],['equipment','Equipment']]} value={storageView} onChange={setStorageView}/>
      <Button onClick={()=>r.reload()}>Refresh</Button>
    </div>
    <div className="toolbar">
      <Field label="Find an item" type="search" placeholder="Search belongings…" value={query} onChange={e=>setQuery(e.target.value)}/>
      <Field label="Category"><select value={category} onChange={e=>setCategory(e.target.value)}><option value="all">All categories</option>{Object.entries(categories).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field>
    </div>
    {data.deployed&&<Notice>Transfers and equipment changes are locked during deployment.</Notice>}
    <Panel title={storageLabel} className="inventory-contents" action={!isEquipment&&<Badge>{data[storageView].length+' / '+(isCarried?capacity(data,'person'):data.homeLimit)}</Badge>}>
      {isCarried&&<div className="metrics"><span>{weight(data)} lb carried</span><span>{movement(data)}% movement</span></div>}
      {isEquipment?Object.entries(slots).map(([key,label])=><Row key={key} title={label} detail={data.equipment[key]?definitions[data.equipment[key].def]?.name:'Empty position'} onClick={data.equipment[key]?()=>setSelected({where:'equipment',id:key}):undefined}/>)
        :contents.length?contents:<Empty title={isCarried?'No matching carried items':'No matching stored items'}/>}
    </Panel>
    {sample&&<div className="actions"><Button onClick={()=>setReview({type:'consolidate'})}>Combine matching home stacks</Button></div>}
    {(review||selectedItem)&&<Modal title={review?(review.type==='transfer'?'Move item':'Review equipment change'):definition.name} onClose={()=>{setReview(null);setSelected(null);}}>
      {review?<>
        <p>{review.type==='transfer'?'Move to '+(review.from==='home'?'your backpack':'home storage')+'.':'Apply this change to your equipment?'}</p>
        {review.type==='transfer'&&<Field label="Quantity" type="number" min="1" max={maxTransfer(data,review.from,review.id)} value={qty} onChange={e=>setQty(Number(e.target.value))}/>}
        <div className="actions"><Button variant="primary" busy={r.busy} disabled={review.type==='transfer'&&(!Number.isInteger(qty)||qty<1||qty>maxTransfer(data,review.from,review.id))} onClick={async()=>{const ok=await r.mutate({...review,...(review.type==='transfer'?{qty}:{})});if(ok){setReview(null);setSelected(null);}}}>Confirm change</Button><Button onClick={()=>setReview(null)}>{selectedItem?'Back':'Cancel'}</Button></div><Notice error>{r.error}</Notice>
      </>:<>
        <p>{definition.description}</p>
        <DefinitionList rows={[['Quantity',selectedItem.qty],['Unit weight',definition.weight+' lb'],['Condition',(selectedItem.properties.condition??100)+'%'],['Location',selected.where==='equipment'?'Equipped':selected.where==='person'?'Backpack':'Home storage']]}/>
        {selected.where==='equipment'
          ?<Button disabled={data.deployed} onClick={()=>setReview({type:'unequip',slot:selected.id})}>Store equipped item</Button>
          :<div className="actions"><Button variant="primary" disabled={data.deployed||maxTransfer(data,selected.where,selectedItem.id)<1} onClick={()=>{setQty(1);setReview({type:'transfer',from:selected.where,id:selectedItem.id});}}>Move item</Button>{definition.slot&&<Button disabled={data.deployed} onClick={()=>setReview({type:'equip',from:selected.where,id:selectedItem.id})}>Equip</Button>}</div>}
      </>}
    </Modal>}
  </>}</ResourceState>;
}
