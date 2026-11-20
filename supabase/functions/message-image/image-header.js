// Header-only validation. Full image decoding and re-encoding occurs in the browser.
export function imageHeader(bytes){
 const b=bytes instanceof Uint8Array?bytes:new Uint8Array(bytes),v=new DataView(b.buffer,b.byteOffset,b.byteLength),str=(i,n)=>String.fromCharCode(...b.slice(i,i+n));let width,height,mime;
 if(b.length>=33&&str(1,3)==='PNG'&&b[0]===137&&str(12,4)==='IHDR'){
 mime='image/png';width=v.getUint32(16);height=v.getUint32(20);let p=8;while(p+12<=b.length){const n=v.getUint32(p),t=str(p+4,4);if(t==='acTL')throw Error('Animated images are for a later pass.');if(n>b.length-p-12)throw Error('Incomplete PNG.');p+=n+12;if(t==='IEND')break;}
 }else if(b.length>=20&&b[0]===255&&b[1]===216){mime='image/jpeg';let p=2;while(p+4<b.length){if(b[p++]!==255)throw Error('Invalid JPEG.');while(b[p]===255)p++;const m=b[p++];if(m===217||m===218)break;if(m===1||(m>=208&&m<=215))continue;const n=v.getUint16(p);if(n<2||p+n>b.length)throw Error('Incomplete JPEG.');if([192,193,194].includes(m)){height=v.getUint16(p+3);width=v.getUint16(p+5);break}p+=n;}
 }else if(b.length>=30&&str(0,4)==='RIFF'&&str(8,4)==='WEBP'){
 mime='image/webp';if(v.getUint32(4,true)+8!==b.length)throw Error('Incomplete WebP.');let p=12;while(p+8<=b.length){const t=str(p,4),n=v.getUint32(p+4,true),d=p+8;if(d+n>b.length)throw Error('Incomplete WebP.');if(t==='ANIM'||t==='ANMF'||(t==='VP8X'&&(b[d]&2)))throw Error('Animated images are for a later pass.');if(t==='VP8X'&&n>=10){width=1+b[d+4]+(b[d+5]<<8)+(b[d+6]<<16);height=1+b[d+7]+(b[d+8]<<8)+(b[d+9]<<16)}if(t==='VP8 '&&n>=10&&width===undefined){width=v.getUint16(d+6,true)&16383;height=v.getUint16(d+8,true)&16383}if(t==='VP8L'&&n>=5&&width===undefined){const bits=v.getUint32(d+1,true);width=(bits&16383)+1;height=((bits>>>14)&16383)+1}p=d+n+(n%2);}
 }
 if(!width||!height||!mime)throw Error('Use a valid, still JPEG, PNG, or WebP image.');return {width,height,mime};
}
