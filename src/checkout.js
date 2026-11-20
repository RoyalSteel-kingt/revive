import {ApiError} from './backend.js';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const amount=n=>Number.isSafeInteger(n)&&n>=0&&n<=1e12;
function invalid(){throw new ApiError('The shop response could not be verified. Please refresh.',0,'checkout');}
export function validateOrder(o,owner){
 if(!o||o.account_id!==owner||!UUID.test(o.id)||!UUID.test(o.request_id)||!UUID.test(o.item_id)||o.shop_id!=='hyphen'||typeof o.item_name!=='string'||!amount(o.amount)||o.amount<1||!Number.isInteger(o.condition)||o.condition<1||o.condition>100||!Number.isFinite(Date.parse(o.created_at)))invalid();
 const d=o.delivery||o.order_deliveries;if(!d||!UUID.test(d.id)||d.order_id!==o.id||typeof d.unit_id!=='string'||typeof d.address!=='string'||!['queued','delivered'].includes(d.status)||d.status==='delivered'&&!Number.isFinite(Date.parse(d.delivered_at)))invalid();
 return {...o,delivery:d};
}
export async function readCheckout(api,owner){
 const c=await api.request('/rest/v1/rpc/get_hyphen_checkout',{method:'POST',body:{}});
 if(c?.account_id!==owner||c.shop_id!=='hyphen'||!['needs_profile','unavailable','shop_locked','needs_home','ready'].includes(c.state)||!amount(c.balance)||!Array.isArray(c.offers))invalid();
 if(c.offers.some(o=>!o||typeof o.id!=='string'||typeof o.name!=='string'||typeof o.description!=='string'||!amount(o.price)||o.price<1||!Number.isInteger(o.condition)||o.condition<1||o.condition>100))invalid();
 if(c.state==='ready'&&(!c.home||typeof c.home.unit_id!=='string'||typeof c.home.address!=='string'))invalid();
 return c;
}
export async function readOrders(api,owner){
 const q=new URLSearchParams({select:'id,account_id,request_id,shop_id,offer_id,definition_id,item_id,item_name,condition,amount,created_at,order_deliveries(id,order_id,unit_id,address,status,delivered_at)',account_id:'eq.'+owner,shop_id:'eq.hyphen',order:'created_at.desc,id.desc',limit:'51'});
 const rows=await api.request('/rest/v1/purchase_orders?'+q);if(!Array.isArray(rows))invalid();return {orders:rows.map(o=>validateOrder(o,owner)).slice(0,50),hasOlder:rows.length>50};
}
export class CheckoutController{
 constructor(api,onChange=()=>{},onUpdated=()=>{},onSessionLost=()=>{}){this.api=api;this.onChange=onChange;this.onUpdated=onUpdated;this.onSessionLost=onSessionLost;this.epoch=0;this.state={phase:'hidden',user:null,catalog:null,orders:[],hasOlder:false,error:'',ordersError:'',pending:null,busy:false,notice:''};}
 update(v){Object.assign(this.state,v);this.onChange(this.state);}
 reset(){++this.epoch;this.update({phase:'hidden',user:null,catalog:null,orders:[],hasOlder:false,error:'',ordersError:'',pending:null,busy:false,notice:''});}
 key(owner){return 'revive-home-purchase/v1/'+owner;}
 pending(owner){for(const s of [this.api.storage,this.api.legacyStorage])try{const p=JSON.parse(s?.getItem(this.key(owner)));if(p&&UUID.test(p.p_request_id)&&typeof p.p_offer_id==='string'&&Number.isInteger(p.p_expected_price)&&p.p_expected_price>0&&typeof p.p_home_unit==='string')return {p_request_id:p.p_request_id,p_offer_id:p.p_offer_id,p_expected_price:p.p_expected_price,p_home_unit:p.p_home_unit};}catch{}return null;}
 save(owner,p){const primary=this.api.storage||this.api.legacyStorage;if(p){try{if(!primary)throw Error();primary.setItem(this.key(owner),JSON.stringify(p));if(primary.getItem(this.key(owner))!==JSON.stringify(p))throw Error();}catch{throw new ApiError('Browser storage is unavailable. Enable it before purchasing so an interrupted payment can be recovered safely.',0,'storage');}}else for(const s of [this.api.storage,this.api.legacyStorage])try{s?.removeItem(this.key(owner));}catch{}this.update({pending:p});}
 async load(user){const epoch=++this.epoch;this.update({phase:'loading',user,catalog:null,orders:[],hasOlder:false,error:'',ordersError:'',pending:this.pending(user.id),busy:false,notice:''});
  const [c,o]=await Promise.allSettled([readCheckout(this.api,user.id),readOrders(this.api,user.id)]);if(epoch!==this.epoch)return;
  const denied=[c,o].find(r=>r.status==='rejected'&&[401,403].includes(r.reason.status));if(denied){this.api.clearSession();this.reset();this.onSessionLost();return;}
  this.update({phase:'ready',catalog:c.status==='fulfilled'?c.value:null,error:c.status==='rejected'?c.reason.message:'',orders:o.status==='fulfilled'?o.value.orders:[],hasOlder:o.status==='fulfilled'?o.value.hasOlder:false,ordersError:o.status==='rejected'?o.reason.message:''});
 }
 canBuy(offer){return this.state.phase==='ready'&&!this.state.busy&&!this.state.pending&&this.state.catalog?.state==='ready'&&this.state.catalog.balance>=offer.price;}
 async purchase(offer=null){
  if(this.state.busy||!this.state.user||this.state.phase!=='ready')return;
  if(offer&&!this.canBuy(offer)||!offer&&!this.state.pending)return;
  const owner=this.state.user.id,user=this.state.user,epoch=this.epoch;
  const request=offer?{p_request_id:crypto.randomUUID(),p_offer_id:offer.id,p_expected_price:offer.price,p_home_unit:this.state.catalog.home.unit_id}:this.state.pending;
  try{this.save(owner,request);}catch(e){this.update({error:e.message});return;}this.update({busy:true,error:'',notice:''});
  try{
   const order=validateOrder(await this.api.request('/rest/v1/rpc/place_hyphen_order',{method:'POST',body:request}),owner);if(epoch!==this.epoch)return;if(order.request_id!==request.p_request_id||order.offer_id!==request.p_offer_id||order.amount!==request.p_expected_price||order.delivery.unit_id!==request.p_home_unit)invalid();
   this.save(owner,null);await this.load(user);if(this.state.user?.id!==owner)return;
   this.update({notice:'Purchase recorded. Your order is queued for delivery to '+order.delivery.address+'.'});this.onUpdated();
  }catch(e){if(epoch!==this.epoch)return;
   if([401,403].includes(e.status)){this.api.clearSession();this.reset();this.onSessionLost();return;}
   if(e.status>=400&&e.status<500&&![408,429].includes(e.status))this.save(owner,null);
   this.update({busy:false,error:(e.message||'The purchase could not be confirmed.')+(this.state.pending?' Recover this same purchase before starting another.':'')});
  }
 }
}
