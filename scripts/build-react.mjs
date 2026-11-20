import {build} from 'esbuild';
import {mkdir,rm,writeFile,copyFile,cp} from 'node:fs/promises';
await rm('dist',{recursive:true,force:true});
await mkdir('dist',{recursive:true});
await build({entryPoints:['react/main.jsx'],bundle:true,minify:true,sourcemap:true,outdir:'dist/assets',publicPath:'/assets',entryNames:'app-[hash]',assetNames:'[name]-[hash]',loader:{'.png':'file','.svg':'file','.woff2':'file','.webp':'file'},metafile:true}).then(async result=>{
 const outputs=Object.keys(result.metafile.outputs);
 const js=outputs.find(p=>p.endsWith('.js'));
 const css=outputs.find(p=>p.endsWith('.css'));
 const html='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="theme-color" content="#111522"><meta name="description" content="Firstlight Online. Your account, belongings, mail, shops and home in Firstlight Colony."><title>Firstlight Online</title><link rel="stylesheet" href="/'+css.replace('dist/','')+'"></head><body><div id="root"></div><script type="module" src="/'+js.replace('dist/','')+'"></script></body></html>';
 const routes=['presentation','index','inventory','mail','shops','housing','messages','chroma','gifts','repairs','real-rewards','hyphen','inventory-records','classic','kiosk','fluid','glass','connection-study'];
 for(const route of routes)await writeFile('dist/'+route+'.html',html);
});
await cp('src/assets','dist/assets/original',{recursive:true});
await copyFile('src/emoji-data.json','dist/emoji-data.json');
await copyFile('src/emoji-data-LICENSE.txt','dist/emoji-data-LICENSE.txt');
console.log('Built Firstlight Online and its React page entries.');
