export const vertex=`#version 300 es
precision highp float;
out vec2 vUv;
void main(){vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));vUv=p;gl_Position=vec4(p*2.-1.,0.,1.);}`;
export const fragment=`#version 300 es
precision highp float;
in vec2 vUv;
out vec4 outColor;
uniform sampler2D uField;
uniform sampler2D uPigmentField;
uniform float uColored;
uniform float uOverlay;
uniform float uGlow;
uniform vec2 uGlowPoint;
uniform sampler2D uSurface;
uniform float uSurfaceEnabled;
uniform float uReveal;
uniform float uCompany;
uniform float uLiving;
uniform vec2 uCamera;
uniform vec2 uWorldBounds;
uniform vec2 uBounds;
uniform vec2 uFieldSize;
uniform vec2 uTilt;
uniform float uHeight;
uniform float uNight;
uniform float uTime;
uniform vec3 uAbsorption;
uniform vec3 uPigment;
uniform float uPearl;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float density(vec2 world){
 vec2 uv=(world-uCamera)/uBounds+.5;
 if(any(lessThan(uv,vec2(0.)))||any(greaterThan(uv,vec2(1.))))return 0.;
 vec2 q=uv*uFieldSize-.5,fr=fract(q);ivec2 i=ivec2(floor(q)),limit=ivec2(uFieldSize)-1;
 float a=texelFetch(uField,clamp(i,ivec2(0),limit),0).r,b=texelFetch(uField,clamp(i+ivec2(1,0),ivec2(0),limit),0).r;
 float c=texelFetch(uField,clamp(i+ivec2(0,1),ivec2(0),limit),0).r,d=texelFetch(uField,clamp(i+ivec2(1),ivec2(0),limit),0).r;
 return mix(mix(a,b,fr.x),mix(c,d,fr.x),fr.y);
}
vec3 pigmentAt(vec2 world){
 vec2 q=clamp((world-uCamera)/uBounds+.5,vec2(0.),vec2(1.))*uFieldSize-.5;ivec2 i=ivec2(floor(q)),limit=ivec2(uFieldSize)-1;vec2 f=fract(q);
 vec4 a=texelFetch(uPigmentField,clamp(i,ivec2(0),limit),0),b=texelFetch(uPigmentField,clamp(i+ivec2(1,0),ivec2(0),limit),0),c=texelFetch(uPigmentField,clamp(i+ivec2(0,1),ivec2(0),limit),0),d=texelFetch(uPigmentField,clamp(i+ivec2(1),ivec2(0),limit),0);
 vec4 color=mix(mix(a,b,f.x),mix(c,d,f.x),f.y);return color.rgb/max(.001,color.a);
}
float heightAt(vec2 p){float d=max(0.,density(p)-.13);return uHeight*sqrt(d)/(1.+.32*d);}
float softBox(vec2 p,vec2 center,vec2 size,float softness){vec2 d=abs(p-center)-size;return 1.-smoothstep(-softness,softness,max(d.x,d.y));}
vec3 studio(vec3 ray){
 vec2 p=ray.xy/max(.18,abs(ray.z));
 vec3 base=mix(vec3(.27,.33,.35),vec3(.018,.035,.06),uNight);
 float skylight=softBox(p,vec2(-.38,.48),vec2(.55,.14),.065);
 float strip=softBox(p,vec2(.58,-.37),vec2(.055,.85),.018);
 float window=softBox(p,vec2(-.7,-.3),vec2(.17,.5),.03);
 float darkBand=softBox(p,vec2(.08,.5),vec2(.045,.2),.015);
 vec3 cool=mix(vec3(1.35,1.48,1.52),vec3(.5,.9,1.5),uNight);
 return base+cool*skylight*(1.-darkBand*.85)+vec3(1.6,1.25,.83)*strip+vec3(.4,.55,.65)*window;
}
vec3 floorColor(vec2 p){
 vec3 base=mix(vec3(.74,.765,.738),vec3(.058,.08,.105),uNight);
 vec3 daylight=mix(vec3(.76,.70,.83),vec3(.69,.83,.78),.5+.5*sin(p.x*.24+p.y*.19));
 daylight=mix(daylight,vec3(.86,.76,.69),(.5+.5*sin(p.y*.32-p.x*.12))*.25);
 vec3 midnight=mix(vec3(.033,.05,.10),vec3(.06,.045,.115),.5+.5*sin(p.x*.2-p.y*.3));
 base=mix(base,mix(daylight,midnight,uNight),uLiving*.75);
 float grain=hash(floor(p*720.))-.5;
 base+=grain*mix(.015,.004,uLiving);
 float spread=smoothstep(0.,.08,uReveal)*(1.-smoothstep(uReveal*length(uBounds)*.65-.25,uReveal*length(uBounds)*.65+.25,length(p)));
 if(uReveal>.999)spread=1.;

 vec2 c=mod(p+.175,.35)-.175;
 float vertical=1.-smoothstep(.002,.008,abs(c.x));
 float horizontal=1.-smoothstep(.002,.008,abs(c.y));
 float dash=1.-smoothstep(.025,.039,abs(c.x));
 float bar=1.-smoothstep(.025,.039,abs(c.y));
 float plus=max(vertical*bar,horizontal*dash);
 float alternating=mod(floor((p.x+.175)/.35)+floor((p.y+.175)/.35),2.);
 plus=mix(plus,horizontal*dash,alternating);
 if(uCompany>.5&&uCompany<1.5){float wave=sin(p.x*7.+sin(p.y*3.)*.5)*.035;plus=(1.-smoothstep(.002,.006,abs(c.y+wave)))*.65;}
 else if(uCompany>1.5&&uCompany<2.5){float arch=abs(length(c*vec2(1.,.8))-.12);plus=(1.-smoothstep(.002,.006,arch))*.8;}
 else if(uCompany>2.5){float signal=1.-smoothstep(.002,.006,abs(c.y));plus=signal*(1.-smoothstep(.05,.13,abs(c.x)))*.65;}
 base=mix(base,base*.72,plus*.52*spread);
 vec3 patternLight=uCompany<.5?vec3(.45,.31,.12):vec3(.23,.34,.36);
 base+=uLiving*plus*spread*mix(vec3(.02,.024,.018),patternLight,uNight);
 // Fine engraved concentric registration rings visible through the liquid.
 float distance=length(p-vec2(.1,.04));
 float ring=1.-smoothstep(.003,.011,min(abs(distance-1.18),abs(distance-1.23)));
 base=mix(base,base*.77,ring*.5*spread);
 float broadLight=exp(-dot(p-vec2(-1.,1.),p-vec2(-1.,1.))*.18);
 base+=mix(vec3(.075,.078,.068),vec3(.025,.04,.052),uNight)*broadLight;
 if(uSurfaceEnabled>.5){vec4 mark=texture(uSurface,p/uWorldBounds+.5);float glow=uGlow*exp(-dot(p-uGlowPoint,p-uGlowPoint)*8.);
 base=mix(base,pow(mark.rgb,vec3(2.2))*(1.+glow*3.),mark.a);
 base+=vec3(.12,.26,.21)*glow*mark.a;}
 return base;
}
float shadowAt(vec2 p){
 float contact=0.;
 for(int i=0;i<5;i++){
  float k=float(i+1);vec2 offset=vec2(-.018,.028)*k;
  float h=heightAt(p+offset);
  contact+=smoothstep(.004,.09,h)/(k+1.);
 }
 float ambient=heightAt(p+vec2(.035,0.))+heightAt(p-vec2(.035,0.))+heightAt(p+vec2(0.,.035))+heightAt(p-vec2(0.,.035));
 return clamp(contact*.22+ambient*.32,0.,.42);
}
void main(){
 vec2 base=(vUv-.5)*uBounds+uCamera;
 vec3 color=floorColor(base)*(1.-shadowAt(base));float alpha=0.;
 float vicinity=max(density(base),max(density(base+uTilt*.28),density(base-uTilt*.28)));
 if(vicinity>.12){
  vec3 origin=vec3(base+uTilt*.5,.5),direction=normalize(vec3(-uTilt,-1.));
  float end=.5/(-direction.z),lo=0.,hi=0.;bool hit=false;
  for(int i=1;i<=28;i++){
   float t=end*float(i)/28.;vec3 pos=origin+direction*t;
   if(pos.z<=heightAt(pos.xy)&&density(pos.xy)>.13){lo=end*float(i-1)/28.;hi=t;hit=true;break;}
  }
  if(hit){
   for(int i=0;i<7;i++){float mid=(lo+hi)*.5;vec3 p=origin+direction*mid;if(p.z>heightAt(p.xy))lo=mid;else hi=mid;}
   vec3 p=origin+direction*((lo+hi)*.5);
   float e=.008;
   float h=heightAt(p.xy),hx=(heightAt(p.xy+vec2(e,0.))-heightAt(p.xy-vec2(e,0.)))/(2.*e),hy=(heightAt(p.xy+vec2(0.,e))-heightAt(p.xy-vec2(0.,e)))/(2.*e);
   vec3 normal=normalize(vec3(-hx,-hy,1.)),view=-direction;
   vec3 through=refract(direction,normal,1./1.36);
   vec2 bottom=p.xy-through.xy*h/min(-.08,through.z);
   vec3 substrate=floorColor(bottom)*(1.-shadowAt(bottom)*.7);
   float thickness=h/max(.35,-through.z);
   float sender=uLiving*step(2.5,uCompany)*smoothstep(-.3,.3,p.x-uCamera.x);
   vec3 pigment=mix(uPigment,vec3(.18,.84,.72),sender);
   vec3 absorption=mix(uAbsorption,vec3(2.2,.22,.3),sender);
   if(uColored>.5){absorption=pigmentAt(p.xy);pigment=exp(-absorption*.32);}
   vec3 trans=exp(-absorption*thickness*8.);
   vec3 transmitted=substrate*trans+pigment*(1.-trans)*.30;
   float fresnel=.035+.965*pow(1.-max(0.,dot(normal,view)),5.);
   vec3 reflection=studio(reflect(direction,normal));
   vec3 liquid=mix(transmitted,reflection,fresnel);
   // Broad softboxes and tight light glints expose the rounded meniscus.
   vec3 light=normalize(vec3(-.5,.8,1.6)),halfDir=normalize(light+view);
   float glint=pow(max(0.,dot(normal,halfDir)),180.);
   float glow=pow(max(0.,dot(normal,halfDir)),24.);
   liquid+=vec3(1.,.96,.85)*glint*.65+vec3(.7,.83,.9)*glow*.065;
   // Light comes from the substrate; the water itself is not emissive.
   liquid=mix(liquid,liquid*.28+reflection*.52+pigment*.35,uPearl*(1.-uColored));
   float laplacian=(heightAt(p.xy+vec2(e,0.))+heightAt(p.xy-vec2(e,0.))+heightAt(p.xy+vec2(0.,e))+heightAt(p.xy-vec2(0.,e))-4.*h)/(e*e);
   liquid+=pigment*clamp(-laplacian*.0014,0.,.10)*(1.-uPearl);
   float coverage=smoothstep(.001,.006,h);
   color=mix(color,liquid,coverage);alpha=coverage;
  }
 }
 float vignette=1.-.10*dot(vUv-.5,vUv-.5);
 color*=vignette;
 // Display transfer. Scene colors above are linear; soft shoulder retains highlights.
 color=color/(1.+max(vec3(0.),color-1.)*.5);
 float outputAlpha=mix(1.,alpha,uOverlay);outColor=vec4(pow(max(color,vec3(0.)),vec3(1./2.2))*outputAlpha,outputAlpha);
}`;
