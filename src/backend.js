export const PROJECT_URL='https://oowlgmookinibahpeyxl.supabase.co';
export const PUBLISHABLE_KEY='sb_publishable_4kasHoliFC1-GmUxGpb_Uw_PHK1Bg91';
export function profileHandle(profile){if(!profile?.username)return '';return profile.discriminator?profile.username+'#'+profile.discriminator:profile.username;}
const SESSION_KEY='revive-auth-v1';
function browserStorage(name){try{return globalThis[name];}catch{return null;}}
export class ApiError extends Error{constructor(message,status,code){super(message);this.status=status;this.code=code;}}
export class ReviveBackend{
 constructor({fetcher=(...args)=>globalThis.fetch(...args),storage,legacyStorage}={}){
  this.fetcher=fetcher;this.storage=storage===undefined?(browserStorage('localStorage')||browserStorage('sessionStorage')):storage;
  this.legacyStorage=legacyStorage===undefined?(storage===undefined?browserStorage('sessionStorage'):null):legacyStorage;
  this.session=null;this.refreshing=null;
  for(const source of [this.storage,this.legacyStorage]){try{const s=JSON.parse(source?.getItem(SESSION_KEY));if(s?.access_token&&s?.refresh_token){this.session=s;try{this.storage?.setItem(SESSION_KEY,JSON.stringify(s));if(this.legacyStorage!==this.storage)this.legacyStorage?.removeItem(SESSION_KEY);}catch{}break;}}catch{}}
 }
 async raw(path,{method='GET',body,token}={}){
  const headers={apikey:PUBLISHABLE_KEY};
  if(body!==undefined)headers['Content-Type']='application/json';
  if(token)headers.Authorization='Bearer '+token;
  const url=PROJECT_URL+path;
  const options={method,headers,body:body===undefined?undefined:JSON.stringify(body)};
  const controller=new AbortController();
  options.signal=controller.signal;
  const timer=setTimeout(()=>controller.abort(),15000);
  let response;
  try{
   response=await this.fetcher(url,options);
  }catch(cause){
   console.error('[Revive API] Request failed:',method,url.split('?')[0],cause);
   const timedOut=controller.signal.aborted;
   const detail=cause?.message||String(cause);
   const error=new ApiError(timedOut?'The Supabase request timed out. Please try again.':'Supabase request failed: '+detail,0,timedOut?'timeout':'network');
   error.cause=cause;
   throw error;
  }finally{clearTimeout(timer);}
  const text=await response.text();
  let data;
  try{data=text?JSON.parse(text):null;}catch{throw new ApiError('The backend returned an unexpected response.',response.status,'response');}
  if(!response.ok)throw new ApiError(data?.msg||data?.message||data?.error_description||data?.error||'Request failed.',response.status,data?.code||data?.error_code);
  return data;
 }
 setSession(data){if(!data?.access_token||!data?.refresh_token)throw new ApiError('Sign-in did not return a valid session.',0,'session');this.session={access_token:data.access_token,refresh_token:data.refresh_token,expires_at:data.expires_at||Math.floor(Date.now()/1000)+(data.expires_in||3600),user:data.user};try{this.storage?.setItem(SESSION_KEY,JSON.stringify(this.session));}catch{}}
 clearSession(){this.session=null;for(const source of [this.storage,this.legacyStorage])try{source?.removeItem(SESSION_KEY);}catch{}}
 async sendCode(email){return this.raw('/auth/v1/otp',{method:'POST',body:{email,create_user:true}});}
 async verifyCode(email,token){const data=await this.raw('/auth/v1/verify',{method:'POST',body:{email,token,type:'email'}});this.setSession(data);return data.user;}
 async token(){if(!this.session)throw new ApiError('Sign in to access your account.',401,'signed_out');if(this.session.expires_at>Math.floor(Date.now()/1000)+60)return this.session.access_token;if(!this.refreshing)this.refreshing=this.raw('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:this.session.refresh_token}}).then(data=>{this.setSession(data);return this.session.access_token;}).catch(err=>{if([400,401,403].includes(err.status))this.clearSession();throw err;}).finally(()=>this.refreshing=null);return this.refreshing;}
 async request(path,options={}){return this.raw(path,{...options,token:await this.token()});}
 async user(){const user=await this.request('/auth/v1/user');this.session.user=user;return user;}
 async signOut(){try{if(this.session)await this.request('/auth/v1/logout?scope=local',{method:'POST'});}finally{this.clearSession();}}
 async profileAndInventory(id){const safe=encodeURIComponent(id);const [profiles,inventory]=await Promise.all([this.request('/rest/v1/profiles?select=*&id=eq.'+safe),this.request('/rest/v1/item_instances?select=id,owner_id,definition_id,condition,location,source,created_at,item_definitions(name,category,description)&owner_id=eq.'+safe+'&order=created_at.desc')]);return {profile:profiles[0]||null,inventory};}
 async register(username){return this.request('/rest/v1/rpc/register_profile',{method:'POST',body:{p_username:username}});}
 async home(){return this.request('/rest/v1/rpc/get_my_constellation_home',{method:'POST',body:{}});}
 async surplus(){return this.request('/rest/v1/rpc/get_surplus_terminal',{method:'POST',body:{}});}
 async trade(operation){return this.request('/rest/v1/rpc/surplus_trade',{method:'POST',body:operation});}
}
