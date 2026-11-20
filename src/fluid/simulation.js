// A shallow particle layer. Double-density relaxation, local viscosity, and
// dissipative surface contact; positions are reconstructed into a height field.
// Inspired by Clavet, Beaudoin & Poulin (2005), not a full 3D Navier–Stokes solver.
export class SurfaceFluid {
 constructor({width=8,height=5,maxParticles=2400,random=Math.random,seed=true}={}){
  this.width=width;this.height=height;this.max=maxParticles;this.random=random;this.count=0;
  for(const name of ['x','y','oldX','oldY','vx','vy'])this[name]=new Float32Array(maxParticles);
  for(const name of ['pigR','pigG','pigB','baseR','baseG','baseB','weight','homeFactor'])this[name]=new Float32Array(maxParticles);
  this.weight.fill(1);this.homeFactor.fill(1);this.group=new Uint16Array(maxParticles);this.colored=false;
  this.homeX=new Float32Array(maxParticles);this.homeY=new Float32Array(maxParticles);
  this.h=.155;this.spacing=.048;this.tension=.7;this.contact=.7;this.grid=new Map();this.pairs=[];
  this.pointer={active:false,x:0,y:0,vx:0,vy:0,mode:'pull',radius:.4};this.homeStrength=0;this.recoil=0;if(seed)this.reset();
 }
 addGlyph(glyph,x,y,size=.8){
  const start=this.count,half=size*.5,bar=size*.25;
  for(let dy=-half;dy<=half;dy+=this.spacing*.866)for(let dx=-half;dx<=half;dx+=this.spacing){
   if(!(Math.abs(dy)<=bar*.5||(glyph==='+'&&Math.abs(dx)<=bar*.5))||this.count>=this.max)continue;
   const i=this.count++;this.x[i]=x+dx;this.y[i]=y+dy;this.vx[i]=0;this.vy[i]=0;
  }return this.count-start;
 }
 addEllipse(x,y,rx,ry){
  const start=this.count;for(let dy=-ry;dy<=ry;dy+=this.spacing*.866)for(let dx=-rx;dx<=rx;dx+=this.spacing){if((dx/rx)**2+(dy/ry)**2>1||this.count>=this.max)continue;const i=this.count++;this.x[i]=x+dx;this.y[i]=y+dy;this.vx[i]=0;this.vy[i]=0;}return this.count-start;
 }
 captureHome(strength=16){
  if(!this.homeX){this.homeX=new Float32Array(this.max);this.homeY=new Float32Array(this.max);}
  this.homeX.set(this.x.subarray(0,this.count));this.homeY.set(this.y.subarray(0,this.count));this.homeStrength=strength;
 }
 springHome(strength=1){this.recoil=Math.min(1,Math.max(0,strength));this.pointer.active=false;}
 addDrop(x,y,radius=.22){
  const countBefore=this.count;
  for(let dy=-radius;dy<=radius;dy+=this.spacing*.866){
   const row=Math.round((dy+radius)/(this.spacing*.866));
   for(let dx=-radius;dx<=radius;dx+=this.spacing){
    const px=dx+(row%2)*this.spacing*.5;
    if(px*px+dy*dy>radius*radius||this.count>=this.max)continue;
    const i=this.count++;this.x[i]=Math.max(-this.width*.47,Math.min(this.width*.47,x+px+(this.random()-.5)*.002));
    this.y[i]=Math.max(-this.height*.47,Math.min(this.height*.47,y+dy+(this.random()-.5)*.002));this.vx[i]=0;this.vy[i]=0;
   }
  }
  return this.count-countBefore;
 }
 reset(){
  this.count=0;
  // Seed a single continuous layer, avoiding overlapping particle lattices.
  for(let y=-.66;y<=.66;y+=this.spacing*.866){
   const row=Math.round((y+.66)/(this.spacing*.866));
   for(let x=-1.32;x<=1.32;x+=this.spacing){
    const px=x+(row%2)*this.spacing*.5;
    const shape=(px/1.32)**2+(y/.66)**2;
    if(shape>1+.09*Math.sin(px*5)||this.count>=this.max)continue;
    const i=this.count++;this.x[i]=px+(this.random()-.5)*.002;this.y[i]=y+(this.random()-.5)*.002;this.vx[i]=0;this.vy[i]=0;
   }
  }
  this.addDrop(-1.65,.66,.22);this.addDrop(1.65,-.48,.29);this.addDrop(1.48,.85,.14);
  this.addDrop(-1.45,-.83,.13);this.pointer.active=false;
  for(let i=0;i<80;i++)this.step(1/120);
 }
 neighbors(){
  this.grid.clear();this.pairs.length=0;
  const columns=Math.ceil(this.width/this.h)+4;
  for(let i=0;i<this.count;i++){
   if(this.weight[i]<=0)continue;
   const cx=Math.floor((this.x[i]+this.width*.5)/this.h)+1,cy=Math.floor((this.y[i]+this.height*.5)/this.h)+1;
   for(let oy=-1;oy<=1;oy++)for(let ox=-1;ox<=1;ox++){
    const bucket=this.grid.get((cy+oy)*columns+cx+ox);if(!bucket)continue;
    for(const j of bucket){if((this.group[i]||this.group[j])&&this.group[i]!==this.group[j])continue;const dx=this.x[j]-this.x[i],dy=this.y[j]-this.y[i];if(dx*dx+dy*dy<this.h*this.h)this.pairs.push(i,j);}
   }
   const key=cy*columns+cx;let bucket=this.grid.get(key);if(!bucket){bucket=[];this.grid.set(key,bucket);}bucket.push(i);
  }
 }
 step(dt=1/120){
  dt=Math.max(.001,Math.min(1/60,dt));const p=this.pointer,n=this.count;
  const damping=Math.exp(-(1.5+this.contact*7)*dt);this.recoil=Math.max(0,this.recoil-dt*2);
  for(let i=0;i<n;i++){
   if(this.weight[i]<=0)continue;this.oldX[i]=this.x[i];this.oldY[i]=this.y[i];
   if(p.active&&(p.group==null||p.group===this.group[i])){
    const dx=this.x[i]-p.x,dy=this.y[i]-p.y,d=Math.hypot(dx,dy),q=Math.max(0,1-d/p.radius);
    if(q>0){
     if(p.mode==='push'){
      const strength=q*q*18*dt,inv=1/Math.max(.03,d);this.vx[i]+=dx*inv*strength+p.vx*q*dt*8;this.vy[i]+=dy*inv*strength+p.vy*q*dt*8;
     }else if(p.mode==='pull'){
      this.vx[i]+=(p.vx*1.4-this.vx[i]-dx*3)*q*dt*22;this.vy[i]+=(p.vy*1.4-this.vy[i]-dy*3)*q*dt*22;
     }
    }
   }
   if(this.homeStrength&&this.homeX){
    const influence=p.active&&(p.group==null||p.group===this.group[i])?Math.max(0,1-Math.hypot(this.x[i]-p.x,this.y[i]-p.y)/p.radius):0;
    const spring=this.homeStrength*this.homeFactor[i]*(1+this.recoil*3)*(1-influence*.94);
    this.vx[i]+=(this.homeX[i]-this.x[i])*spring*dt;this.vy[i]+=(this.homeY[i]-this.y[i])*spring*dt;
   }
   this.vx[i]*=damping;this.vy[i]*=damping;
   const speed=Math.hypot(this.vx[i],this.vy[i]);if(speed>5){this.vx[i]*=5/speed;this.vy[i]*=5/speed;}
   this.x[i]+=this.vx[i]*dt;this.y[i]+=this.vy[i]*dt;
  }
  this.neighbors();
  // Density and near density constraints, accumulated symmetrically per pair.
  if(!this.rho||this.rho.length<this.max){this.rho=new Float32Array(this.max);this.near=new Float32Array(this.max);this.dx=new Float32Array(this.max);this.dy=new Float32Array(this.max);}
  const rho=this.rho,near=this.near;rho.fill(0,0,n);near.fill(0,0,n);this.dx.fill(0,0,n);this.dy.fill(0,0,n);
  for(let k=0;k<this.pairs.length;k+=2){const i=this.pairs[k],j=this.pairs[k+1];const r=Math.hypot(this.x[j]-this.x[i],this.y[j]-this.y[i]);const q=Math.max(0,1-r/this.h),q2=q*q,q3=q2*q;rho[i]+=q2;rho[j]+=q2;near[i]+=q3;near[j]+=q3;}
  const dt2=dt*dt,rest=5,stiff=24+this.tension*28,nearStiff=65;
  for(let k=0;k<this.pairs.length;k+=2){
   const i=this.pairs[k],j=this.pairs[k+1],dx=this.x[j]-this.x[i],dy=this.y[j]-this.y[i],r=Math.max(.0001,Math.hypot(dx,dy)),q=Math.max(0,1-r/this.h);
   let d=dt2*((stiff*(rho[i]+rho[j]-2*rest))*q+nearStiff*(near[i]+near[j])*q*q)*.5;
   d=Math.max(-.0015,Math.min(.003,d));const sx=dx/r*d,sy=dy/r*d;
   this.dx[i]-=sx;this.dy[i]-=sy;this.dx[j]+=sx;this.dy[j]+=sy;
  }
  const bx=this.width*.475,by=this.height*.475;
  for(let i=0;i<n;i++){
   if(this.weight[i]<=0)continue;this.x[i]=Math.max(-bx,Math.min(bx,this.x[i]+this.dx[i]));this.y[i]=Math.max(-by,Math.min(by,this.y[i]+this.dy[i]));
   this.vx[i]=(this.x[i]-this.oldX[i])/dt;this.vy[i]=(this.y[i]-this.oldY[i])/dt;
   // Surface adhesion dissipates tiny residual motion after the pressure solve.
   if((!p.active||p.group!=null&&p.group!==this.group[i])&&Math.abs(this.vx[i])<.007)this.vx[i]=0;if((!p.active||p.group!=null&&p.group!==this.group[i])&&Math.abs(this.vy[i])<.007)this.vy[i]=0;
  }
  // Viscosity is applied after reconstructing velocities, so the next step
  // retains it rather than overwriting it during the positional solve.
  for(let k=0;k<this.pairs.length;k+=2){
   const i=this.pairs[k],j=this.pairs[k+1];const q=Math.max(0,1-Math.hypot(this.x[j]-this.x[i],this.y[j]-this.y[i])/this.h);
   const mix=q*q*.06,ux=(this.vx[j]-this.vx[i])*mix,uy=(this.vy[j]-this.vy[i])*mix;
   this.vx[i]+=ux;this.vy[i]+=uy;this.vx[j]-=ux;this.vy[j]-=uy;
   if(this.colored){const exchange=Math.min(.035,q*q*dt*1.8);let d=(this.pigR[j]-this.pigR[i])*exchange;this.pigR[i]+=d;this.pigR[j]-=d;d=(this.pigG[j]-this.pigG[i])*exchange;this.pigG[i]+=d;this.pigG[j]-=d;d=(this.pigB[j]-this.pigB[i])*exchange;this.pigB[i]+=d;this.pigB[j]-=d;}
  }
  if(this.colored)for(let i=0;i<n;i++){if(!this.weight[i]||!this.homeFactor[i]||p.active&&(p.group==null||p.group===this.group[i]))continue;const restore=Math.min(1,dt*.42*this.homeFactor[i]);this.pigR[i]+=(this.baseR[i]-this.pigR[i])*restore;this.pigG[i]+=(this.baseG[i]-this.pigG[i])*restore;this.pigB[i]+=(this.baseB[i]-this.pigB[i])*restore;
  }
 }
 rasterize(out,w,h,region={width:this.width,height:this.height,x:0,y:0},pigment=null){
  out.fill(0);if(pigment)pigment.fill(0);const sx=w/region.width,sy=h/region.height,r=.145,rx=Math.ceil(r*sx),ry=Math.ceil(r*sy);
  for(let i=0;i<this.count;i++){
   if(this.weight[i]<=0)continue;
   if(this.weight[i]<=0||(region.groupOnly&&!this.group[i]))continue;const cx=((this.x[i]-region.x)/region.width+.5)*w,cy=((this.y[i]-region.y)/region.height+.5)*h;
   if(cx+rx<0||cx-rx>=w||cy+ry<0||cy-ry>=h)continue;
   for(let yy=Math.max(0,Math.floor(cy-ry));yy<Math.min(h,cy+ry);yy++){
    const dy=(yy+.5-cy)/sy;
    for(let xx=Math.max(0,Math.floor(cx-rx));xx<Math.min(w,cx+rx);xx++){
     const dx=(xx+.5-cx)/sx,q=1-(dx*dx+dy*dy)/(r*r);if(q>0){const pixel=yy*w+xx,value=q*q*q*.22*this.weight[i];out[pixel]+=value;if(pigment){const at=pixel*4;pigment[at]+=value*this.pigR[i];pigment[at+1]+=value*this.pigG[i];pigment[at+2]+=value*this.pigB[i];pigment[at+3]+=value;}}
    }
   }
  }
  return out;
 }
}
