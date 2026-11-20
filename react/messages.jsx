import React,{useEffect,useRef,useState} from 'react';
import {Panel,Button,Field,Empty,Badge,Modal,Row,Tabs,ResourceState,useResource,useApp,api,rpc,date} from './core.jsx';
import {sampleSocial,changeSample} from '../src/social-model.js';
import {prepareImage,uploadImage,imageBlob,sampleImage} from '../src/message-images.js';
import {stickers,stickerArt,encodeMedia,decodeMedia,messagePreview} from '../src/message-content.js';

export function Messages() {
  const {sample,go}=useApp();
  const [selected,setSelected]=useState(null),[rows,setRows]=useState([]),[people,setPeople]=useState(false),[query,setQuery]=useState(''),[tab,setTab]=useState('all'),[drafts,setDrafts]=useState({}),[photos,setPhotos]=useState([]),[emoji,setEmoji]=useState(false),[error,setError]=useState(''),[sending,setSending]=useState(false),[confirm,setConfirm]=useState(null),[older,setOlder]=useState(false);
  const [emojiQuery,setEmojiQuery]=useState(''),[emojiData,setEmojiData]=useState([]);
  useEffect(()=>{if(emoji&&!emojiData.length)fetch('/emoji-data.json').then(r=>r.json()).then(setEmojiData).catch(()=>{});},[emoji]);
  const file=useRef(null),epoch=useRef(0),log=useRef(null),photoRef=useRef(photos);
  const r=useResource({name:'social',seed:sampleSocial,load:()=>rpc('get_social_workspace'),change:(a,id)=>rpc('change_social_workspace',{p_request:id,p_action:a}),reduce:changeSample});
  const s=r.data,t=s?.threads.find(t=>t.id===selected);
  const matches=s?.threads.filter(thread=>thread.name.toLowerCase().includes(query.toLowerCase())&&(tab==='all'||(tab==='business'?!!thread.shop_id:!thread.shop_id)));
  useEffect(()=>{photoRef.current=photos;},[photos]);
  useEffect(()=>()=>{epoch.current++;for(const p of photoRef.current)URL.revokeObjectURL(p.url);},[]);
  async function conversation(id,append=false) {
    const generation=++epoch.current;setError('');
    try {
      const result=sample?{messages:r.data.messages[id]||[]}:await rpc('get_social_conversation',{p_thread:id,p_before:append?rows[0]?.seq:null});
      if(generation!==epoch.current)return;
      setRows(old=>append?[...result.messages,...old]:result.messages);
      setOlder(!sample&&result.messages.length===50);
    }catch(e){setError(e.message);}
  }
  useEffect(()=>{if(selected&&s){if(sample)setRows(s.messages[selected]||[]);else conversation(selected);}},[selected,s]);
  useEffect(()=>{if(log.current)log.current.scrollTop=log.current.scrollHeight;},[selected,rows.length]);
  useEffect(()=>{if(t?.unread&&rows.length&&!r.busy&&!r.pending)r.mutate({type:'read',thread:t.id,through:rows.at(-1).seq});},[t?.id,t?.unread,rows.length]);
  function selectConversation(id) {
    if(id===selected)return;
    epoch.current++;
    setRows([]);
    setOlder(false);
    setError('');
    for(const photo of photos)URL.revokeObjectURL(photo.url);
    setPhotos([]);
    setSelected(id);
  }
  async function change(a){
    const result=await r.mutate(a);
    if(result&&['open','business'].includes(a.type)){
      const thread=result.threads.find(t=>a.type==='open'?t.peer===a.peer:t.shop_id===a.shop);
      if(thread)selectConversation(thread.id);
      setPeople(false);
    }
    return result;
  }
  async function send(e) {
    e.preventDefault();if(!t||sending||r.busy)return;
    const body=drafts[selected]||'';
    if(!body.trim()&&!photos.length)return;
    setSending(true);setError('');
    try {
      const groups=Array.from({length:Math.ceil(photos.length/10)},()=>crypto.randomUUID());
      for(let i=0;i<photos.length;i++) {
        const photo=photos[i];let attachment;
        if(sample){await sampleImage(photo.id,photo);attachment={id:photo.id,width:photo.width,height:photo.height,bytes:photo.full.size,mime:photo.mime};}
        else attachment=await uploadImage(api,photo,selected);
        if(!await change({type:'send',thread:selected,body:encodeMedia({type:'photo',group:groups[Math.floor(i/10)],index:i%10,total:Math.min(10,photos.length-Math.floor(i/10)*10)}),image:attachment}))return;
        URL.revokeObjectURL(photo.url);setPhotos(items=>items.filter(p=>p.id!==photo.id));
      }
      if(body.trim()&&!await change({type:'send',thread:selected,body}))return;
      setDrafts(d=>({...d,[selected]:''}));
    }catch(e){setError(e.message);}finally{setSending(false);}
  }
  async function prepare(files) {
    setSending(true);setError('');
    try{for(const file of [...files]){const p=await prepareImage(file);setPhotos(items=>[...items,{...p,url:URL.createObjectURL(p.full)}]);}}
    catch(e){setError(e.message);}finally{setSending(false);}
  }
  return <ResourceState resource={r}>{s&&<>
    <div className="conversation-layout">
      {!t?<><div className="toolbar"><Field label="Find a conversation" type="search" value={query} onChange={e=>setQuery(e.target.value)}/><Button onClick={()=>setPeople(true)}>Friends & requests</Button><Button onClick={()=>r.reload()}>Refresh</Button></div>
        <Panel title="Conversations"><Tabs label="Conversation type" value={tab} onChange={setTab} items={[[ 'all','All'],['friends','Friends'],['business','Businesses']]}/>{matches.map(thread=><Row key={thread.id} title={thread.name} detail={messagePreview(thread.preview)} end={thread.unread?<Badge>New</Badge>:null} onClick={()=>selectConversation(thread.id)}/>)}{!matches.length&&(s.threads.length?<Empty title="No matching conversations"/>:<Empty title="Start a conversation">Open Friends & requests to find someone.</Empty>)}</Panel>
      </>:<>
        <div className="actions conversation-back"><Button disabled={sending} onClick={()=>selectConversation(null)}>All conversations</Button><Button disabled={sending} onClick={()=>r.reload()}>Refresh</Button></div>
        <Panel title={t.name} action={<Button onClick={()=>change({type:'mute',thread:t.id,value:!t.muted})}>{t.muted?'Unmute':'Mute'}</Button>}>
          <div className="message-log" ref={log} role="log" aria-label="Messages">{older&&<Button onClick={()=>conversation(t.id,true)}>Load earlier messages</Button>}{rows.map(m=><Message key={m.seq} message={m} sample={sample}/>)}{!rows.length&&<Empty title="Your conversation starts here"/>}</div>
          {t.can_send?<form onSubmit={send} className="composer">
            {photos.length>0&&<div className="photo-drafts">{photos.map(p=><div key={p.id}><img src={p.url} alt="Ready to send"/><Button aria-label="Remove photo" onClick={()=>{URL.revokeObjectURL(p.url);setPhotos(photos.filter(x=>x.id!==p.id));}}>×</Button></div>)}</div>}
            <Field label="Message"><textarea value={drafts[selected]||''} onChange={e=>setDrafts(d=>({...d,[selected]:e.target.value}))} maxLength={4000} rows={3} placeholder="Write a message…"/></Field>
            <div className="actions"><Button onClick={()=>file.current.click()} disabled={sending}>Photos</Button><input hidden ref={file} type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={e=>{prepare(e.target.files);e.target.value='';}}/><Button onClick={()=>setEmoji(!emoji)}>Emoji & stickers</Button><Button variant="primary" busy={sending} disabled={r.busy||!photos.length&&!drafts[selected]?.trim()} type="submit">{sending?'Sending…':'Send'}</Button></div>
            {emoji&&<div className="expression-picker"><Field label="Find emoji" value={emojiQuery} onChange={e=>setEmojiQuery(e.target.value)}/><div className="emoji-buttons">{(emojiQuery?emojiData.flatMap(g=>g.items).filter(e=>e.label.toLowerCase().includes(emojiQuery.toLowerCase())).slice(0,60):['😊','💙','✨','👋','😂','🌙','🐻','👍','💕','🥹','🎉','🤔'].map(emoji=>({emoji,label:emoji}))).map(({emoji:v,label})=><Button key={v} aria-label={'Insert '+label} onClick={()=>setDrafts(d=>({...d,[selected]:(d[selected]||'')+v}))}>{v}</Button>)}</div><div className="sticker-grid">{stickers.map(sticker=><Button key={sticker.id} onClick={()=>change({type:'send',thread:selected,body:encodeMedia({type:'sticker',id:sticker.id})})}><img src={'data:image/svg+xml,'+encodeURIComponent(stickerArt(sticker.id))} alt={sticker.name}/></Button>)}</div></div>}
          </form>:<Empty title="Messaging is unavailable">Your earlier conversation remains here.</Empty>}
          <div className="actions">{t.shop_id?<Button onClick={()=>setConfirm({type:'business_stop',thread:t.id})}>Stop business contact</Button>:<Button onClick={()=>setConfirm({type:'block',peer:t.peer})}>Block resident</Button>}</div>
        </Panel>
      </>}
    </div>
    {error&&<p className="notice error" role="alert">{error}</p>}
    {people&&<Modal title="Friends & requests" onClose={()=>setPeople(false)}>
      <form onSubmit={e=>{e.preventDefault();change({type:'request',handle:new FormData(e.currentTarget).get('handle').trim()});}}><Field name="handle" label="Contractor name and tag" placeholder="Name#123456" required pattern="[A-Za-z][A-Za-z0-9_]{2,23}#[0-9]{6}"/><Button variant="primary" type="submit">Send friend request</Button></form>
      <h3>Friends</h3>{s.friends.map(f=><Row key={f.id} title={f.handle} detail={f.presence}><div className="actions"><Button onClick={()=>change({type:'open',peer:f.id})}>Message</Button><Button onClick={()=>go('gifts',null,{to:f.handle})}>Send gift</Button><Button onClick={()=>go('housing',null,{invite:f.handle})}>Invite home</Button><Button onClick={()=>setConfirm({type:'remove',peer:f.id})}>Remove</Button></div></Row>)}
      <h3>Requests</h3>{s.requests.map(q=><Row key={q.id} title={q.handle} detail={q.incoming?'Incoming':'Sent'}><div className="actions">{q.incoming&&<Button onClick={()=>change({type:'accept',peer:q.id})}>Accept</Button>}<Button onClick={()=>change({type:q.incoming?'decline':'cancel',peer:q.id})}>{q.incoming?'Decline':'Cancel request'}</Button></div></Row>)}
      <h3>Businesses</h3>{s.businesses.map(b=><Row key={b.id} title={b.name}><Button onClick={()=>setConfirm({type:'business',shop:b.id})}>Start inquiry</Button></Row>)}
      <h3>Blocked residents</h3>{s.blocked.map(b=><Row key={b.id} title={b.handle}><Button onClick={()=>setConfirm({type:'unblock',peer:b.id})}>Unblock</Button></Row>)}
      <details className="disclosure"><summary>Presence preferences</summary><form onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);change({type:'settings',share_presence:f.has('share'),mode:f.get('presence')});}}><label className="check"><input name="share" type="checkbox" defaultChecked={s.settings.share_presence}/> Share presence with friends</label><Field label="Presence"><select name="presence" defaultValue={s.settings.mode}>{['offline','available','away','busy'].map(v=><option key={v}>{v}</option>)}</select></Field><Button type="submit">Save preferences</Button></form></details><p role="alert">{r.error}</p>
    </Modal>}
    {confirm&&<Modal title="Confirm contact change" onClose={()=>setConfirm(null)}><p>{confirm.type==='block'?'Block messages and requests from this resident?':confirm.type==='business'?'Allow this business to reply to your inquiry?':confirm.type==='remove'?'Remove this resident from your friends?':confirm.type==='unblock'?'Unblock this resident?':'Stop this business from replying to this conversation?'}</p><Button variant="primary" onClick={async()=>{if(await change(confirm))setConfirm(null);}}>Confirm</Button><p role="alert">{r.error}</p></Modal>}
  </>}</ResourceState>;
}

function Message({message:m,sample}) {
  const [url,setURL]=useState(null),[error,setError]=useState(''),[full,setFull]=useState(false);
  const media=decodeMedia(m.body);
  useEffect(()=>{
    let active=true,objectURL;
    if(m.image)(async()=>{try{const blob=sample?(await sampleImage(m.image.id))?.thumb:await imageBlob(api,m.image.thumb);if(!blob)throw Error('Image unavailable');objectURL=URL.createObjectURL(blob);if(active)setURL(objectURL);else URL.revokeObjectURL(objectURL);}catch(e){if(active)setError(e.message);}})();
    return()=>{active=false;if(objectURL)URL.revokeObjectURL(objectURL);};
  },[m.image?.id,sample]);
  return <article className={'message '+(m.mine?'mine':'')}>
    {m.image&&<Button onClick={()=>setFull(true)}>{url?<img className="message-photo" src={url} alt="Photo attachment"/>:error||'Loading photo…'}</Button>}
    {media?.type==='sticker'?<img className="message-sticker" alt={stickers.find(s=>s.id===media.id)?.name||'Sticker'} src={'data:image/svg+xml,'+encodeURIComponent(stickerArt(media.id))}/>:!media&&m.body?<p>{m.body}</p>:null}
    <time>{date(m.created_at)}</time>
    {full&&<PhotoViewer image={m.image} sample={sample} onClose={()=>setFull(false)}/>}
  </article>;
}
function PhotoViewer({image,sample,onClose}) {
  const [url,setURL]=useState(null),[error,setError]=useState('');
  useEffect(()=>{let current=true,url; (async()=>{try{const blob=sample?(await sampleImage(image.id))?.full:await imageBlob(api,image.full);if(!blob)throw Error('Image unavailable');url=URL.createObjectURL(blob);if(current)setURL(url);else URL.revokeObjectURL(url);}catch(e){if(current)setError(e.message);}})();return()=>{current=false;if(url)URL.revokeObjectURL(url);};},[image,sample]);
  return <Modal title="Photo attachment" onClose={onClose}>{url?<><img className="full-photo" src={url} alt="Full photo"/><a className="button secondary" href={url} download="firstlight-photo.webp">Download photo</a></>:<p>{error||'Loading photo…'}</p>}</Modal>;
}
