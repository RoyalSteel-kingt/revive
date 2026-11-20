import {SurfaceFluid} from './simulation.js';
import {WetRenderer} from './renderer.js';
const $=s=>document.querySelector(s),canvas=$('#surface'),status=$('#runtime-status'),mark=$('#pointer-mark');
let renderer,sim,paused=matchMedia('(prefers-reduced-motion: reduce)').matches,mode='pull',activePointer=null,lastPointer=null,lastTime=0,accumulator=0,stirUntil=0,dirty=true,visible=true,contextLost=false;
function fail(error){$('#error').hidden=false;$('#error-message').textContent=error.message||String(error);status.textContent='Surface unavailable';console.error('[Revive material]',error);}
function interact(){document.body.classList.add('interacted');}
function updatePause(){const b=$('#pause');b.textContent=paused?'Resume':'Pause';b.setAttribute('aria-pressed',String(paused));status.textContent=paused?'Paused · inspect the surface':'LIVE MATERIAL / DRAG TO FEEL';}
function point(e){const r=canvas.getBoundingClientRect();return{x:((e.clientX-r.left)/r.width-.5)*sim.width,y:(.5-(e.clientY-r.top)/r.height)*sim.height};}
try{
 renderer=new WetRenderer(canvas);
 function layout(){const aspect=canvas.clientWidth/Math.max(1,canvas.clientHeight);const width=aspect<1?4.8:8,height=width/aspect;if(!sim)sim=new SurfaceFluid({width,height});else{sim.width=width;sim.height=height;}dirty=true;}
 layout();window.addEventListener('resize',layout);updatePause();
 document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;sim.pointer.mode=mode;document.querySelectorAll('[data-mode]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',String(x===b));});});
 canvas.addEventListener('pointerdown',e=>{if(e.button!==0||activePointer!==null)return;interact();if(paused){status.textContent='Resume the surface to move the liquid.';return;}const p=point(e);activePointer=e.pointerId;canvas.setPointerCapture(e.pointerId);lastPointer={...p,time:performance.now()};Object.assign(sim.pointer,{...p,active:true,mode,vx:0,vy:0});mark.classList.add('active');if(mode==='pour')sim.addDrop(p.x,p.y,.12);});
 canvas.addEventListener('pointermove',e=>{mark.style.left=e.clientX+'px';mark.style.top=e.clientY+'px';mark.style.opacity='1';if(activePointer!==e.pointerId)return;const p=point(e),now=performance.now(),dt=Math.max(.012,(now-lastPointer.time)/1000);Object.assign(sim.pointer,{...p,vx:Math.max(-5,Math.min(5,(p.x-lastPointer.x)/dt)),vy:Math.max(-5,Math.min(5,(p.y-lastPointer.y)/dt))});lastPointer={...p,time:now};});
 function release(e){if(activePointer!==e.pointerId)return;activePointer=null;lastPointer=null;sim.pointer.active=false;sim.pointer.vx=0;sim.pointer.vy=0;mark.classList.remove('active');dirty=true;}
 canvas.addEventListener('pointerup',release);canvas.addEventListener('pointercancel',release);canvas.addEventListener('lostpointercapture',release);canvas.addEventListener('pointerleave',()=>{if(activePointer===null)mark.style.opacity='0';});
 canvas.addEventListener('dblclick',e=>{if(paused)return;const p=point(e);sim.addDrop(p.x,p.y,.23);interact();});
 $('#drop').onclick=()=>{const count=sim.addDrop((Math.random()-.5)*1.8,(Math.random()-.5)*1.1,.23);dirty=true;interact();status.textContent=count?'A new drop. Give it a little push.':'The surface is full. Reset to begin again.';};
 $('#stir').onclick=()=>{paused=false;updatePause();stirUntil=performance.now()+1700;interact();};
 $('#reset').onclick=()=>{sim.reset();document.body.classList.remove('interacted');dirty=true;status.textContent='A fresh spill. Make yourself comfortable.';};
 $('#pause').onclick=()=>{paused=!paused;sim.pointer.active=false;activePointer=null;stirUntil=0;accumulator=0;updatePause();dirty=true;};
 function settings(open){$('#settings').hidden=!open;$('#settings-toggle').setAttribute('aria-expanded',String(open));}
 $('#settings-toggle').onclick=()=>settings($('#settings').hidden);$('#close-settings').onclick=()=>settings(false);
 document.addEventListener('keydown',e=>{if(e.key==='Escape')settings(false);});
 for(const id of ['tension','contact','depth'])$('#'+id).oninput=e=>{const value=Number(e.target.value);$('#'+id+'-value').textContent=value+'%';if(id==='depth')renderer.height=value/100*.3;else sim[id]=value/100;dirty=true;};
 document.querySelectorAll('[data-palette]').forEach(b=>b.onclick=()=>{renderer.preset=b.dataset.palette;document.querySelectorAll('[data-palette]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',String(x===b));});$('#material-name').textContent={amber:'HYPHEN / LIQUID AMBER',clear:'FIRSTLIGHT ONLINE / CLEAR SURFACE',ink:'SIDEBAND / INDIGO INK',pearl:'FIRSTLIGHT ONLINE / PEARL SURFACE'}[renderer.preset];dirty=true;});
 $('#night').onclick=()=>{renderer.night=renderer.night?0:1;document.body.classList.toggle('night',!!renderer.night);$('#night').setAttribute('aria-pressed',String(!!renderer.night));dirty=true;};
 $('#angle').onclick=()=>{const oblique=renderer.tilt[1]===0;renderer.tilt=[0,oblique ? 0.4 : 0];$('#angle').textContent=oblique?'Oblique view':'Top-down view';$('#angle').setAttribute('aria-pressed',String(oblique));dirty=true;};
 document.addEventListener('visibilitychange',()=>{visible=!document.hidden;lastTime=0;accumulator=0;sim.pointer.active=false;activePointer=null;stirUntil=0;});
 window.addEventListener('blur',()=>{sim.pointer.active=false;activePointer=null;lastPointer=null;stirUntil=0;mark.classList.remove('active');});
 canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();contextLost=true;fail(Error('The graphics context was interrupted. Reload this material test to restore it.'));});
 let pourTime=0;
 function frame(now){
  requestAnimationFrame(frame);if(!visible||contextLost)return;
  const dt=lastTime?Math.min(.04,(now-lastTime)/1000):1/60;lastTime=now;
  if(!paused){
   if(stirUntil>now){const t=now*.004;Object.assign(sim.pointer,{active:true,mode:'pull',x:Math.cos(t)*.5,y:Math.sin(t)*.32,vx:-Math.sin(t)*2,vy:Math.cos(t)*1.28});}
   else if(stirUntil){stirUntil=0;sim.pointer.active=false;sim.pointer.mode=mode;}
   if(lastPointer&&now-lastPointer.time>60){sim.pointer.vx*=.7;sim.pointer.vy*=.7;}
   if(activePointer!==null&&mode==='pour'){pourTime+=dt;if(pourTime>.055){pourTime=0;sim.addDrop(sim.pointer.x,sim.pointer.y,.065);}}
   accumulator+=dt;let steps=0;while(accumulator>=1/120&&steps<4){sim.step(1/120);accumulator-=1/120;steps++;}dirty=true;
  }
  if(dirty){renderer.time=now*.001;renderer.draw(sim);dirty=false;}
 }
 requestAnimationFrame(frame);
}catch(error){fail(error);}
