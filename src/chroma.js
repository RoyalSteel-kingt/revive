import {ApiError} from './backend.js';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const HISTORY_PAGE_SIZE=25;
const validAmount=n=>Number.isSafeInteger(n)&&n>=0&&n<=1000000000000;
const error=()=>new ApiError('Your banking records could not be verified. Please refresh.',0,'chroma');
const checkOwner=owner=>{if(!UUID.test(owner))throw error();};
export const formatChroma=n=>Number(n).toLocaleString()+' Chroma';
export function filterTransactions(rows,{type='all',search=''}={}){
 const term=search.trim().toLowerCase();
 return rows.filter(t=>(type==='all'||type==='credit'&&t.delta>0&&t.source!=='savings'||type==='debit'&&t.delta<0&&t.source!=='savings'||type==='opening'&&t.kind==='opening'||type==='savings'&&t.source==='savings')&&(!term||[t.description,t.source,t.reference,t.id].some(v=>String(v||'').toLowerCase().includes(term))));
}
export async function readWallet(api,owner){
 checkOwner(owner);const query=new URLSearchParams({select:'account_id,balance',account_id:'eq.'+owner,limit:'1'});const rows=await api.request('/rest/v1/chroma_wallets?'+query);
 if(!Array.isArray(rows)||rows.length>1||rows.some(r=>!r||r.account_id!==owner||!validAmount(r.balance)))throw error();return rows[0]||null;
}
export async function readTransactionPage(api,owner,cursor=null){
 checkOwner(owner);const query=new URLSearchParams({select:'id,account_id,delta,balance_before,balance_after,source,reference,description,kind,created_at',account_id:'eq.'+owner,order:'created_at.desc,id.desc',limit:String(HISTORY_PAGE_SIZE+1)});
 if(cursor){if(!UUID.test(cursor.id)||!Number.isFinite(Date.parse(cursor.created_at)))throw error();query.set('or',`(created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id}))`);}
 const rows=await api.request('/rest/v1/chroma_transactions?'+query);
 if(!Array.isArray(rows)||rows.some(t=>!t||t.account_id!==owner||!UUID.test(t.id)||!Number.isFinite(Date.parse(t.created_at))||!Number.isSafeInteger(t.delta)||!validAmount(t.balance_before)||!validAmount(t.balance_after)||t.balance_after-t.balance_before!==t.delta||typeof t.description!=='string'||typeof t.source!=='string'||!['movement','opening'].includes(t.kind)||t.kind==='movement'&&t.delta===0||t.kind==='opening'&&t.delta!==0||t.reference!==null&&!UUID.test(t.reference)))throw error();
 const transactions=rows.slice(0,HISTORY_PAGE_SIZE),last=transactions.at(-1);return {transactions,cursor:rows.length>HISTORY_PAGE_SIZE?{id:last.id,created_at:last.created_at}:null};
}

export class ChromaController{
  constructor(api,onChange=()=>{}){this.api=api;this.onChange=onChange;this.epoch=0;this.state={phase:'loading',user:null,wallet:null,walletError:'',transactions:[],historyError:'',cursor:null,moreLoading:false,synced:null,error:''};}
  update(values){Object.assign(this.state,values);this.onChange(this.state);}
  message(e){return [401,403].includes(e.status)?'Your session expired. Sign in again.':e.message||'Chroma could not be loaded. Please try again.';}
  clear(phase='loading',message=''){this.update({phase,user:null,wallet:null,walletError:'',transactions:[],historyError:'',cursor:null,moreLoading:false,synced:null,error:message});}
  async load(){
    const epoch=++this.epoch;this.clear();
    if(!this.api.session){this.clear('signed_out');return;}
    try{
      const user=await this.api.user();if(epoch!==this.epoch)return;
      const [wallet,history]=await Promise.allSettled([readWallet(this.api,user.id),readTransactionPage(this.api,user.id)]);if(epoch!==this.epoch)return;
      const revoked=[wallet,history].find(r=>r.status==='rejected'&&[401,403].includes(r.reason.status));
      if(revoked)throw revoked.reason;
      this.update({phase:'ready',user,wallet:wallet.status==='fulfilled'?wallet.value:null,walletError:wallet.status==='rejected'?this.message(wallet.reason):'',transactions:history.status==='fulfilled'?history.value.transactions:[],cursor:history.status==='fulfilled'?history.value.cursor:null,historyError:history.status==='rejected'?this.message(history.reason):'',synced:new Date()});
    }catch(e){if(epoch!==this.epoch)return;if([401,403].includes(e.status))this.api.clearSession();this.clear(this.api.session?'error':'signed_out',this.message(e));}
  }
  async loadMore(){
    if(this.state.phase!=='ready'||this.state.moreLoading||!this.state.cursor)return;
    const epoch=this.epoch,owner=this.state.user.id,cursor=this.state.cursor;this.update({moreLoading:true,historyError:''});
    try{
      const next=await readTransactionPage(this.api,owner,cursor);if(epoch!==this.epoch)return;
      const ids=new Set(this.state.transactions.map(r=>r.id));
      this.update({transactions:[...this.state.transactions,...next.transactions.filter(r=>!ids.has(r.id))],cursor:next.cursor,moreLoading:false});
    }catch(e){if(epoch!==this.epoch)return;if([401,403].includes(e.status)){this.api.clearSession();++this.epoch;this.clear('signed_out',this.message(e));}else this.update({historyError:this.message(e),moreLoading:false});}
  }
  async signOut(){++this.epoch;this.clear();try{await this.api.signOut();}catch{}this.clear('signed_out');}
}
