import {ReviveBackend} from './backend.js';
import {IdentityController,identitySummary} from './identity.js';
import {escapeHTML as esc} from './model.js';
const root=document.querySelector('#account');
const controller=new IdentityController(new ReviveBackend(),render);
let codeDraft='',usernameDraft='';
function render(s) {
  const busy=['working','loading'].includes(s.phase), ready=!!s.user, summary=identitySummary(s.record);
  root.setAttribute('aria-busy',String(busy));
  root.innerHTML=`${s.error?`<p class="notice error" role="alert">${esc(s.error)}</p>`:''}
  ${busy?'<p class="notice" role="status">'+(s.phase==='loading'?'Checking your account…':'One moment…')+'</p>':''}
  ${s.phase==='error'?'<section class="panel"><h2>We couldn’t verify your account.</h2><p>Try again to load your current contractor details.</p><button id="refresh">Try again</button><button id="sign-out" class="secondary">Sign out</button></section>':ready?`
  <section class="panel account-panel"><div class="section-heading"><div><span class="eyebrow">YOUR REVIVE ACCOUNT</span><h2>${summary.linked?'Contractor connected':s.record?'Create your contractor profile':'Your account'}</h2></div><span class="badge">Signed in</span></div><p class="private-email">${esc(s.user.email||'Email verified')}</p>
  ${summary.linked?`<div class="contractor"><span class="eyebrow">PUBLIC CONTRACTOR NAME</span><h3>${esc(summary.handle)}</h3><p>This is the contractor attached to your account in Revive.</p><a href="inventory.html">Open your inventory ↗</a></div>`:s.record?`<p>No contractor profile is attached to this account yet. If you already have one, sign out and use that account’s email.</p>${s.record.can_create?`<form id="profile-form"><label for="username">Public contractor name</label><input id="username" name="username" autocomplete="username" aria-describedby="name-help" pattern="[A-Za-z][A-Za-z0-9_]{2,23}" minlength="3" maxlength="24" required value="${esc(usernameDraft)}" ${busy?'disabled':''}><p class="hint" id="name-help">3–24 characters. Start with a letter; then use letters, numbers or underscores. Your six-digit tag is assigned automatically.</p><button ${busy?'disabled':''}>Create contractor profile</button></form><p class="hint">Creates your shared identity. SF registration happens during the game introduction.</p>`:'<p class="notice">New profile creation is awaiting the website identity database update. Existing profiles can still connect.</p>'}`:''}
  <div class="actions"><button id="refresh" class="secondary" ${busy?'disabled':''}>Refresh connection</button><button id="sign-out" class="secondary" ${busy?'disabled':''}>Sign out</button></div></section>
  ${s.record?`<section class="panel"><span class="eyebrow">SINGULARITY FOUNDATION</span><h2>${summary.sf==='registered'?'Registered with SF':summary.sf==='unregistered'?'Not registered with SF yet':'SF status unavailable'}</h2><p>${summary.sf==='registered'?'Your SF registration is recorded for this account.':summary.sf==='unregistered'?'Visit SF reception in-game to complete the joining introduction.':'The SF registration service has not confirmed your status. Your contractor connection is separate and can still work.'}</p>${summary.sf==='registered'&&s.record.sf.registered_at?`<p class="hint">Registered ${esc(new Date(s.record.sf.registered_at).toLocaleDateString())}</p>`:''}</section><details class="panel"><summary>Connection details</summary><dl><dt>Revive account ID</dt><dd>${esc(s.user.id)}</dd><dt>Contractor profile ID</dt><dd>${esc(s.record.profile?.id||'Not created yet')}</dd><dt>Connection method</dt><dd>Shared Revive account</dd></dl><p class="hint">These IDs should match. Use the same account in Unity to load this contractor. This confirms account ownership; it doesn’t report whether the game is currently running.</p></details>`:''}`:
  s.phase!=='error'?`<section class="panel"><span class="eyebrow">SIGN IN TO REVIVE</span><h2>${s.phase==='code_sent'?'Check your inbox.':'Find your contractor.'}</h2><p>Enter your game account’s email to receive a sign-in code.</p><form id="email-form"><label for="email">Private email</label><input id="email" name="email" type="email" autocomplete="email" required value="${esc(s.email)}" ${busy?'disabled':''}><button ${busy?'disabled':''}>${s.phase==='code_sent'?'Send another code':'Send sign-in code'}</button></form>${s.phase==='code_sent'?`<form id="code-form"><label for="code">Code sent to ${esc(s.email)}</label><input id="code" name="code" autocomplete="one-time-code" inputmode="numeric" pattern="[0-9]{6,10}" minlength="6" maxlength="10" required value="${esc(codeDraft)}"><button>Verify & connect</button></form>`:''}<p class="hint">Your email stays private. Signing in does not join SF.</p></section>`:''}`;
  const bind=(id,event,fn)=>root.querySelector(id)?.addEventListener(event,fn);
  bind('#email-form','submit',e=>{e.preventDefault();codeDraft='';controller.sendCode(root.querySelector('#email').value.trim());});
  bind('#code','input',e=>codeDraft=e.target.value);
  bind('#username','input',e=>usernameDraft=e.target.value);
  bind('#code-form','submit',e=>{e.preventDefault();controller.verify(root.querySelector('#code').value.trim());});
  bind('#profile-form','submit',e=>{e.preventDefault();controller.create(root.querySelector('#username').value.trim());});
  bind('#refresh','click',()=>controller.load());
  bind('#sign-out','click',()=>{codeDraft='';usernameDraft='';controller.signOut();});
  if(s.phase==='code_sent')root.querySelector('#code')?.focus();
}
window.addEventListener('storage',e=>{if(e.key==='revive-auth-v1'||e.key===null)location.reload();});
controller.load();
