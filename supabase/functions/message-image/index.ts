import {imageHeader} from './image-header.js';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const url=Deno.env.get('SUPABASE_URL')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
async function rpc(name:string,body:unknown){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.message||'Image operation failed.');return data}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return reply({error:'POST required.'},405);
 try{
  const auth=req.headers.get('Authorization')||'';const userResponse=await fetch(url+'/auth/v1/user',{headers:{apikey:anon,Authorization:auth}});if(!userResponse.ok)return reply({error:'Sign in to send an image.'},401);const user=await userResponse.json();
  if(Number(req.headers.get('content-length'))>2200000)return reply({error:'Image upload exceeds 2 MB plus its preview.'},413);
  // Bound the stream before parsing multipart data; do not buffer unbounded requests.
  const reader=req.body?.getReader();if(!reader)throw Error('Missing image.');const chunks:Uint8Array[]=[];let size=0;for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>2200000){await reader.cancel();return reply({error:'Upload is too large.'},413)}chunks.push(value)}
  const form=await new Response(new Blob(chunks),{headers:{'Content-Type':req.headers.get('content-type')||''}}).formData();
  const id=String(form.get('id')),thread=String(form.get('thread')),full=form.get('full'),thumb=form.get('thumb');if(!/^[0-9a-f-]{36}$/i.test(id)||!/^[0-9a-f-]{36}$/i.test(thread)||!(full instanceof File)||!(thumb instanceof File))throw Error('Invalid image request.');if(full.size>2000000||thumb.size>80000)throw Error('Image or preview exceeds its limit.');
  const bytes=new Uint8Array(await full.arrayBuffer()),small=new Uint8Array(await thumb.arrayBuffer()),h=imageHeader(bytes),th=imageHeader(small);if(h.width>2048||h.height>2048||th.width>400||th.height>400)throw Error('Image dimensions exceed the limit.');
  const digests=await Promise.all([bytes,small].map(async b=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',b))).map(n=>n.toString(16).padStart(2,'0')).join('')));
  // Opportunistic cleanup. Never delete attached images or live drafts younger than 24 hours.
  try{const stale=await rpc('cleanup_message_images',{});if(stale.length){const r=await fetch(url+'/storage/v1/object/message-images',{method:'DELETE',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({prefixes:stale.flatMap((i:{full:string,thumb:string})=>[i.full,i.thumb])})});if(r.ok)await rpc('cleanup_message_images',{p_deleted:stale.map((i:{id:string})=>i.id)})}}catch{console.warn('Deferred image cleanup.');}
  const reserved=await rpc('reserve_message_image',{p_owner:user.id,p_id:id,p_thread:thread,p_bytes:full.size,p_thumb_bytes:thumb.size,p_width:h.width,p_height:h.height,p_mime:h.mime,p_thumb_mime:th.mime,p_fingerprint:digests.join(':')});
  if(reserved.status==='pending'){
   for(const [path,data,mime] of [[reserved.full,bytes,h.mime],[reserved.thumb,small,th.mime]] as const){const r=await fetch(url+'/storage/v1/object/message-images/'+path,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':mime,'x-upsert':'true','Cache-Control':'private, max-age=3600'},body:data});if(!r.ok)throw Error('Could not upload the image. Please retry.');}
   await rpc('finish_message_image',{p_id:id,p_owner:user.id});
  }
  return reply({id});
 }catch(e){return reply({error:e instanceof Error?e.message:'Could not send image.'},400)}
});
