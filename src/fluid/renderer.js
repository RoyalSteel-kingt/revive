import {vertex,fragment} from './shaders.js';
export class WetRenderer{
 constructor(canvas,{overlay=false}={}){
  this.canvas=canvas;this.gl=canvas.getContext('webgl2',{alpha:overlay,antialias:false,powerPreference:'high-performance'});
  if(!this.gl)throw Error('This material test needs WebGL 2. Try a browser with hardware acceleration enabled.');
  const gl=this.gl;
  function compile(type,source){const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){const message=gl.getShaderInfoLog(shader);gl.deleteShader(shader);throw Error(message);}return shader;}
  const vs=compile(gl.VERTEX_SHADER,vertex),fs=compile(gl.FRAGMENT_SHADER,fragment);this.program=gl.createProgram();gl.attachShader(this.program,vs);gl.attachShader(this.program,fs);gl.linkProgram(this.program);gl.deleteShader(vs);gl.deleteShader(fs);
  if(!gl.getProgramParameter(this.program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(this.program));
  gl.useProgram(this.program);this.vao=gl.createVertexArray();gl.bindVertexArray(this.vao);
  this.uniform={};for(const name of ['uField','uPigmentField','uColored','uOverlay','uGlowPoint','uGlow','uSurface','uSurfaceEnabled','uReveal','uCompany','uLiving','uCamera','uWorldBounds','uBounds','uFieldSize','uTilt','uHeight','uNight','uTime','uAbsorption','uPigment','uPearl'])this.uniform[name]=gl.getUniformLocation(this.program,name);
  this.fieldW=512;this.fieldH=320;this.field=new Float32Array(this.fieldW*this.fieldH);
  this.texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,this.texture);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.R32F,this.fieldW,this.fieldH,0,gl.RED,gl.FLOAT,this.field);
  gl.uniform1i(this.uniform.uField,0);gl.uniform2f(this.uniform.uFieldSize,this.fieldW,this.fieldH);
  this.pigmentField=new Float32Array(this.fieldW*this.fieldH*4);this.pigmentTexture=gl.createTexture();gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,this.pigmentTexture);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA32F,this.fieldW,this.fieldH,0,gl.RGBA,gl.FLOAT,this.pigmentField);gl.uniform1i(this.uniform.uPigmentField,2);this.glow=0;this.glowPoint=[0,0];
  this.surfaceTexture=gl.createTexture();gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,this.surfaceTexture);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array(4));gl.uniform1i(this.uniform.uSurface,1);
  this.overlay=overlay;this.surfaceEnabled=0;this.reveal=1;this.company=0;this.living=0;this.camera={x:0,y:0,zoom:1};this.viewBounds=null;
  this.height=.18;this.night=0;this.tilt=[0,.4];this.preset='amber';this.time=0;
 }
 setSurface(canvas){const gl=this.gl;gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,this.surfaceTexture);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,canvas);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);this.surfaceEnabled=1;}
 resize(){const dpr=Math.min(window.devicePixelRatio||1,this.canvas.clientWidth<600?1.25:1.6),w=Math.round(this.canvas.clientWidth*dpr),h=Math.round(this.canvas.clientHeight*dpr);if(this.canvas.width!==w||this.canvas.height!==h){this.canvas.width=w;this.canvas.height=h;this.gl.viewport(0,0,w,h);}}
 draw(sim){
  this.resize();const gl=this.gl;const bounds=this.viewBounds||[sim.width,sim.height],width=bounds[0]/this.camera.zoom,height=bounds[1]/this.camera.zoom;sim.rasterize(this.field,this.fieldW,this.fieldH,{width,height,x:this.camera.x,y:this.camera.y,groupOnly:this.overlay},sim.colored?this.pigmentField:null);gl.useProgram(this.program);gl.bindVertexArray(this.vao);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,this.fieldW,this.fieldH,gl.RED,gl.FLOAT,this.field);
  gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,this.surfaceTexture);
  gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,this.pigmentTexture);if(sim.colored)gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,this.fieldW,this.fieldH,gl.RGBA,gl.FLOAT,this.pigmentField);
  const u=this.uniform;gl.uniform1f(u.uColored,sim.colored?1:0);gl.uniform1f(u.uOverlay,this.overlay?1:0);gl.uniform1f(u.uGlow,this.glow);gl.uniform2f(u.uGlowPoint,...this.glowPoint);gl.uniform1f(u.uSurfaceEnabled,this.surfaceEnabled);gl.uniform1f(u.uReveal,this.reveal);gl.uniform1f(u.uCompany,this.company);gl.uniform1f(u.uLiving,this.living);gl.uniform2f(u.uCamera,this.camera.x,this.camera.y);gl.uniform2f(u.uWorldBounds,sim.width,sim.height);gl.uniform2f(u.uBounds,width,height);gl.uniform2f(u.uTilt,...this.tilt);gl.uniform1f(u.uHeight,this.height);gl.uniform1f(u.uNight,this.night);gl.uniform1f(u.uTime,this.time);
  const palettes={amber:{absorb:[.38,1.6,7.5],pigment:[1.,.7,.08],pearl:0},clear:{absorb:[.2,.11,.06],pigment:[.55,.72,.8],pearl:0},ink:{absorb:[10.,12.,3.],pigment:[.12,.12,.4],pearl:.08},pearl:{absorb:[1.,.4,.1],pigment:[.78,.62,.91],pearl:.68}};
  const p=palettes[this.preset]||palettes.amber;gl.uniform3f(u.uAbsorption,...p.absorb);gl.uniform3f(u.uPigment,...p.pigment);gl.uniform1f(u.uPearl,p.pearl);gl.drawArrays(gl.TRIANGLES,0,3);
 }
 dispose(){const gl=this.gl;gl.deleteProgram(this.program);gl.deleteTexture(this.texture);gl.deleteTexture(this.surfaceTexture);gl.deleteTexture(this.pigmentTexture);gl.deleteVertexArray(this.vao);}
}
