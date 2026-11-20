import React,{useState} from 'react';
import {Panel,Button,Field,Row,Empty,Modal,DefinitionList,ResourceState,useResource,useApp,api} from './core.jsx';
import {readReceiptPage} from '../src/hyphen.js';
import {readOrders} from '../src/checkout.js';
import {shops} from '../src/shop-roster.js';
export function Repairs(){
  const {go}=useApp();
  const [item,setItem]=useState(''),[kit,setKit]=useState(''),[review,setReview]=useState(false);
  const r=useResource({name:'repairs',seed:()=>({market:{balance:200,repair_points:40},inventory:[{id:'example-rifle',definition_id:'flux-rifle',condition:35,item_definitions:{name:'Recovered Flux Rifle'}},{id:'example-kit',definition_id:'flux-service-kit',condition:100,item_definitions:{name:'Flux Service Kit'}}],receipts:[],orders:[]}),load:async owner=>{
    const [market,profile,history,orders]=await Promise.all([api.surplus(),api.profileAndInventory(owner),readReceiptPage(api,owner),readOrders(api,owner)]);
    return {market,inventory:profile.inventory,receipts:history.receipts,orders:orders.orders,cursor:history.cursor,hasOlderOrders:orders.hasOlder};
  },change:async(a,id)=>{await api.trade({p_request_id:id,p_action:'repair',p_item_id:a.item,p_kit_id:a.kit,p_expected_amount:a.amount});},
  reduce:(s,a)=>{const i=s.inventory.find(x=>x.id===a.item),k=s.inventory.find(x=>x.id===a.kit);if(!i||!k||i.condition>=100)throw Error('Select a damaged rifle and a service kit.');i.condition=Math.min(100,i.condition+s.market.repair_points);s.inventory=s.inventory.filter(x=>x!==k);s.receipts.unshift({request_id:crypto.randomUUID(),result:{name:i.item_definitions.name,action:'repair',condition:i.condition}});return s;}});
  const s=r.data;
  return <>
    <Panel title="Repair counters in Firstlight">
      {shops.filter(shop=>shop.repairService).map(shop=><Row key={shop.id} title={shop.name} detail={shop.repairService+' · In person'} end="View shop" onClick={()=>go('shops',null,{shop:shop.id})}/>)}
    </Panel>
    <ResourceState resource={r}>{s&&<>
    <Panel title="Use a service kit"><p>One Flux Service Kit restores up to {s.market.repair_points} condition points.</p><div className="two-columns"><Field label="Rifle"><select value={item} onChange={e=>setItem(e.target.value)}><option value="">Choose a rifle</option>{s.inventory.filter(i=>i.definition_id==='flux-rifle'&&i.condition<100&&i.location!=='mission').map(i=><option key={i.id} value={i.id}>{i.item_definitions?.name||i.definition_id} · {i.condition}%</option>)}</select></Field><Field label="Service kit"><select value={kit} onChange={e=>setKit(e.target.value)}><option value="">Choose a kit</option>{s.inventory.filter(i=>i.definition_id==='flux-service-kit'&&i.location!=='mission').map(i=><option key={i.id} value={i.id}>Flux Service Kit · {i.id.slice(0,8)}</option>)}</select></Field></div><Button variant="primary" disabled={!item||!kit} onClick={()=>setReview(true)}>Review repair</Button></Panel>
    <Panel title="Earlier Hyphen receipts">{s.receipts.map(x=><Row key={x.request_id} title={x.result.name} detail={x.result.action} end={x.result.condition+'% condition'}/>)}{!s.receipts.length&&<Empty title="No earlier receipts"/>}</Panel>
    <Panel title="Earlier home-delivery orders">{s.orders.map(o=><Row key={o.id} title={o.item_name} detail={o.delivery.address} end={o.delivery.status}/>)}{!s.orders.length&&<Empty title="No earlier delivery orders"/>}{s.hasOlderOrders&&<p className="muted">Showing the latest 50 home-delivery orders.</p>}</Panel>
    {s.cursor&&<Button onClick={async()=>{const user=await api.user();try{const page=await readReceiptPage(api,user.id,s.cursor);r.updateData(old=>({...old,receipts:[...old.receipts,...page.receipts],cursor:page.cursor}));}catch(e){r.updateData(old=>({...old,historyError:e.message}));}}}>Load earlier receipts</Button>}{s.historyError&&<p role="alert">{s.historyError}</p>}
    {review&&<Modal title="Confirm kit repair" onClose={()=>setReview(false)}><p>This consumes the selected service kit.</p><DefinitionList rows={[['Current condition',s.inventory.find(i=>i.id===item).condition+'%'],['After repair',Math.min(100,s.inventory.find(i=>i.id===item).condition+s.market.repair_points)+'%'],['Additional Chroma','0']]}/><Button variant="primary" busy={r.busy} onClick={async()=>{if(await r.mutate({item,kit,amount:Math.min(s.market.repair_points,100-s.inventory.find(i=>i.id===item).condition)})){setReview(false);setItem('');setKit('');}}}>Confirm repair</Button><p role="alert">{r.error}</p></Modal>}
  </>}</ResourceState>
  </>;
}
