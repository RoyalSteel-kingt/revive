import React,{useState} from 'react';
import {Panel,Button,Field,Empty,Badge,DefinitionList,Modal,Row,Tabs,ResourceState,useResource,useApp,rpc,money,date} from './core.jsx';
import {sampleRewards,withSampleHelp,regions,eligible,canCancel,totalCost,orderQueue,queueLabels} from '../src/real-rewards-model.js';
import {changeRewardsSample} from './rewards-sample.js';

export function Rewards(){
  const {sample}=useApp();
  const [tab,setTab]=useState('catalog'),[filter,setFilter]=useState('all'),[form,setForm]=useState(null),[review,setReview]=useState(null),[help,setHelp]=useState(null),[error,setError]=useState('');
  const r=useResource({name:'rewards',seed:()=>withSampleHelp(sampleRewards()),persistAction:()=>({type:'recover'}),load:async owner=>{const s=await rpc('get_real_rewards');s.account_id=owner;s.support=s.deployed&&!s.staff?[]:await rpc('get_reward_help',{p_order:null});return s;},
    change:async(a,id)=>{await rpc(a.type.startsWith('help_')?'change_reward_help':'change_real_rewards',{p_request:id,p_action:a});},
    reduce:changeRewardsSample});
  const s=r.data;
  async function helpFor(order){
    try{const result=sample?{case:s.support.find(h=>h.order_id===order.id)||null,messages:s.helpMessages?.[order.id]||[]}:await rpc('get_reward_help',{p_order:order.id});setHelp({order,...result});}catch(e){setError(e.message);}
  }
  const ownOrders=s?.orders.filter(o=>!s.staff||sample||o.owner_id===s.account_id);
  function orderCard(o,staff=false) {
    return <Panel key={o.id} title={o.item_name} action={<Badge>{o.status}</Badge>}><DefinitionList rows={[['Quantity',o.quantity],['Total',money(o.total)],['Shipping',money(o.shipping)],['Created',date(o.created_at)],['Cancel by',date(o.cancel_until)],['Tracking',o.tracking]]}/>{o.address&&<details className="disclosure"><summary>Shipping address</summary><address>{o.address.name}<br/>{o.address.line1}<br/>{o.address.line2}<br/>{o.address.city}, {o.address.state} {o.address.zip}</address></details>}<div className="actions"><Button onClick={()=>helpFor(o)}>Order help</Button>{!staff&&canCancel(o)&&<Button onClick={()=>setReview({type:'cancel',id:o.id})}>Cancel order</Button>}{staff&&!['cancelled','refunded'].includes(o.status)&&<><Button onClick={()=>setReview({type:'refund',id:o.id})}>Refund order</Button>{o.status!=='delivered'&&<Button disabled={Date.now()<Date.parse(o.cancel_until)} onClick={()=>setForm({kind:'fulfill',order:o})}>Update fulfillment</Button>}</>}</div></Panel>;
  }
  return <ResourceState resource={r}>{s&&<>
    <div className="toolbar"><Badge>{money(s.serving)} in Serving</Badge><Button onClick={()=>r.reload()}>Refresh</Button></div>
    <Tabs value={tab} onChange={setTab} items={[['catalog','Catalogue'],['orders','Your orders'],['invites','Invitations'],['requests','Availability requests'],...(s.staff?[['staff','Fulfillment desk']]:[])]}/>
    {error&&<p role="alert" className="notice error">{error}</p>}
    {tab==='catalog'&&<>
      {!eligible(s)&&<div className="notice">Ordering requires tutorial completion, three discovered stores, and being home from deployment.</div>}
      <div className="toolbar"><Field label="Category"><select value={filter} onChange={e=>setFilter(e.target.value)}>{[['all','Everything'],['patch','Patches'],['sticker','Stickers'],['pin','Pins']].map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field></div>
      <div className="card-grid">{s.products.filter(p=>p.listed&&(filter==='all'||p.category===filter)).map(p=><Panel key={p.id} title={p.name}>{p.photo&&<img className="product-photo" src={p.photo} alt={p.name} loading="lazy" referrerPolicy="no-referrer"/>}<p>{p.description}</p><p className="price">{money(p.price)}</p><p>{p.stock} available · Shipping {money(s.config.shipping)}</p><Button variant="primary" disabled={!eligible(s)||!s.config.enabled||s.config.shipping===null||p.stock<1} onClick={()=>setForm({kind:'buy',product:p})}>Review order</Button>{!p.stock&&p.made_to_order&&<Button disabled={!eligible(s)} onClick={()=>setReview({type:'request',product:p.id})}>Request availability</Button>}</Panel>)}</div>
    </>}
    {tab==='orders'&&<div className="card-grid">{ownOrders.map(o=>orderCard(o))}{!ownOrders.length&&<Empty title="No orders yet"/>}</div>}
    {tab==='invites'&&<Panel title="Care-package invitations">{s.invitations.filter(i=>!s.staff||sample||i.owner_id===s.account_id).map(i=><Row key={i.id} title={i.label} detail={i.body} end={i.status}>{i.status==='invited'&&<div className="actions"><Button variant="primary" onClick={()=>setForm({kind:'accept',invitation:i})}>Accept free package</Button><Button onClick={()=>setReview({type:'decline',id:i.id})}>Decline</Button></div>}</Row>)}</Panel>}
    {tab==='requests'&&<Panel title="Availability requests">{s.interest.filter(i=>!s.staff||sample||i.owner_id===s.account_id).map(i=><Row key={i.id} title={s.products.find(p=>p.id===i.product_id)?.name||'Product request'} detail={i.status}><Button disabled={i.status==='withdrawn'} onClick={()=>setReview({type:'withdraw',id:i.id})}>Withdraw request</Button></Row>)}{!s.interest.length&&<Empty title="No availability requests"/>}</Panel>}
    {tab==='staff'&&<>
      <Panel title="Fulfillment settings"><p>Orders have a 24-hour cancellation period before preparation.</p><div className="actions"><Button onClick={()=>setForm({kind:'settings'})}>Ordering & shipping</Button><Button onClick={()=>setForm({kind:'product'})}>Add product</Button><Button onClick={()=>setForm({kind:'invite'})}>Invite recipient</Button></div>{s.products.map(p=><Row key={p.id} title={p.name} detail={p.stock+' available'}><Button onClick={()=>setForm({kind:'product',product:p})}>Edit listing</Button></Row>)}</Panel>
      <Panel title="Fulfillment queue">{Object.entries(queueLabels).map(([key,label])=><details className="disclosure" key={key}><summary>{label} · {s.orders.filter(o=>orderQueue(o,s.support)===key).length}</summary>{s.orders.filter(o=>orderQueue(o,s.support)===key).map(o=>orderCard(o,true))}</details>)}</Panel>
      <Panel title="Made-to-order requests">{s.interest.filter(i=>i.status==='requested').map(i=><Row key={i.id} title={s.products.find(p=>p.id===i.product_id)?.name||'Request'} detail={'Resident '+i.owner_id}><Button onClick={()=>setReview({type:'ready',id:i.id})}>Notify ready</Button></Row>)}</Panel>
    </>}
    {form&&<RewardForm data={s} form={form} onClose={()=>setForm(null)} onReview={a=>{setForm(null);setReview(a);}}/>}
    {review&&<Modal title="Review reward change" onClose={()=>setReview(null)}><p>{['buy','accept'].includes(review.type)?'Review the shipment details. You have 24 hours to cancel for a full refund before preparation begins.':review.type==='refund'?'Refund the full order and shipping amount?':'Confirm this '+review.type.replaceAll('_',' ')+' change?'}</p><DefinitionList rows={Object.entries(review).filter(([k])=>!['address','type','revision','id'].includes(k)).map(([k,v])=>[k==='product'?'Product':k.replaceAll('_',' ').replace(/^./,c=>c.toUpperCase()),k==='product'?s.products.find(p=>p.id===v)?.name||'Selected reward':['total','price','shipping'].includes(k)&&v!==null?money(v):typeof v==='boolean'?v?'Yes':'No':String(v??'—')])}/>{review.address&&<address>{review.address.name}<br/>{review.address.line1}<br/>{review.address.city}, {review.address.state} {review.address.zip}</address>}<Button variant="primary" busy={r.busy} onClick={async()=>{if(await r.mutate(review))setReview(null);}}>Confirm</Button><p role="alert">{r.error}</p></Modal>}
    {help&&<Modal title={'Order help · '+help.order.item_name} onClose={()=>setHelp(null)}>
      <p>Private correspondence about this order.</p>{help.messages.map((m,i)=><div className="inset" key={m.id||i}><strong>{m.author==='owner'?'Fulfillment owner':'Resident'}</strong><p className="letter-body">{m.body}</p><time>{date(m.created_at)}</time></div>)}
      <form onSubmit={async e=>{e.preventDefault();const f=Object.fromEntries(new FormData(e.currentTarget));const action={type:help.case?f.action:'help_open',id:help.order.id,...help.case?{revision:help.case.revision}:{category:f.category},body:f.body,...sample?{author:f.author||'customer'}:{}};if(await r.mutate(action))setHelp(null);}}>
        {help.case?<Field label="Action"><select name="action">{help.case.status==='resolved'?<option value="help_reopen">Reopen case</option>:<><option value="help_reply">Reply</option><option value="help_resolve">Resolve with a note</option></>}</select></Field>:<Field label="Problem"><select name="category">{['missing','damaged','incorrect','other'].map(k=><option key={k}>{k}</option>)}</select></Field>}
        <Field label="Message"><textarea name="body" rows={4} maxLength={2000} required/></Field>{sample&&<Field label="Example author"><select name="author"><option value="customer">Resident</option><option value="owner">Fulfillment owner</option></select></Field>}<Button variant="primary" type="submit">Save help request</Button><p role="alert">{r.error}</p>
      </form>
    </Modal>}
  </>}</ResourceState>;
}
function RewardForm({data,form,onClose,onReview}){
  const p=form.product;
  return <Modal title={form.kind==='buy'?'Order '+p.name:form.kind==='accept'?'Accept care package':form.kind==='product'?'Product listing':form.kind==='fulfill'?'Update fulfillment':form.kind==='settings'?'Ordering & shipping':'Invite a recipient'} onClose={onClose}>
    <form onSubmit={e=>{e.preventDefault();const f=Object.fromEntries(new FormData(e.currentTarget));
      if(['buy','accept'].includes(form.kind)){const quantity=Number(f.quantity||1),address=Object.fromEntries(['name','line1','line2','city','state','zip'].map(k=>[k,f[k]]).concat([['country','US']]));onReview(form.kind==='buy'?{type:'buy',product:p.id,quantity,revision:p.revision,total:totalCost(p,quantity,data.config.shipping),address}:{type:'accept',id:form.invitation.id,address});}
      else if(form.kind==='product')onReview({type:'product',...(p?{id:p.id,revision:p.revision}:{}),name:f.name,category:f.category,description:f.description,photo:f.photo,price:Number(f.price),stock:Number(f.stock),listed:f.listed==='on',made_to_order:f.made_to_order==='on',days:Number(f.days)});
      else if(form.kind==='settings')onReview({type:'settings',enabled:f.enabled==='on',shipping:f.shipping||null});
      else if(form.kind==='fulfill')onReview({type:'fulfill',id:form.order.id,status:{placed:'preparing',preparing:'shipped',shipped:'delivered'}[form.order.status],tracking:f.tracking||null});
      else onReview({type:'invite',handle:f.handle,label:f.label,body:f.body});
    }}>
      {['buy','accept'].includes(form.kind)?<>
        {p&&<><p>{money(p.price)} per item · Shipping {money(data.config.shipping)}</p><Field label="Quantity" name="quantity" type="number" min="1" max={Math.min(10,p.stock)} defaultValue="1" required/></>}
        <p>US delivery to your own address. You can cancel for a full refund within 24 hours.</p>
        <Field label="Recipient name" name="name" required maxLength={100} autoComplete="name"/><Field label="Street" name="line1" required maxLength={150} autoComplete="address-line1"/><Field label="Apartment / unit" name="line2" maxLength={150} autoComplete="address-line2"/>
        <div className="two-columns"><Field label="City" name="city" required maxLength={100}/><Field label="State"><select name="state" required><option value="">Choose…</option>{regions.map(r=><option key={r}>{r}</option>)}</select></Field></div><Field label="ZIP" name="zip" required pattern="[0-9]{5}(-[0-9]{4})?"/>
      </>:form.kind==='product'?<>
        <Field label="Product name" name="name" defaultValue={p?.name||''} required maxLength={100}/><Field label="Category"><select name="category" defaultValue={p?.category||'patch'}><option>patch</option><option>sticker</option><option>pin</option></select></Field><Field label="Description"><textarea name="description" defaultValue={p?.description||''} maxLength={2000}/></Field><Field label="Photo URL" name="photo" type="url" defaultValue={p?.photo||''}/>
        <div className="two-columns"><Field label="Price" name="price" type="number" min="1" max="100000000" defaultValue={p?.price||1} required/><Field label="Stock" name="stock" type="number" min="0" max="100000" defaultValue={p?.stock||0} required/></div>
        <label className="check"><input type="checkbox" name="listed" defaultChecked={p?.listed}/> Listed</label><label className="check"><input type="checkbox" name="made_to_order" defaultChecked={p?.made_to_order}/> Allow availability requests</label><Field label="Preparation days" name="days" type="number" min="1" max="365" defaultValue={p?.days||14}/>
      </>:form.kind==='settings'?<><label className="check"><input type="checkbox" name="enabled" defaultChecked={data.config.enabled}/> Accept orders</label><Field label="Shipping Chroma per order" name="shipping" type="number" min="0" defaultValue={data.config.shipping??''}/></>:form.kind==='fulfill'?<><p>{form.order.status} → {{placed:'preparing',preparing:'shipped',shipped:'delivered'}[form.order.status]}</p><Field label="Carrier & tracking reference" name="tracking" maxLength={200}/></>:<><Field label="Recipient handle" name="handle" pattern="[A-Za-z][A-Za-z0-9_]{2,23}#[0-9]{6}" required/><Field label="Invitation label" name="label" required/><Field label="Invitation message"><textarea name="body" required maxLength={2000}/></Field></>}
      <Button variant="primary" type="submit">Review</Button>
    </form>
  </Modal>;
}
