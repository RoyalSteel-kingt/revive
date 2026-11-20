import {copyFile,rm,mkdir,cp} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
for(const file of ['index.html','kiosk.html','account.css','account.js','identity.js','classic.html','style.css','main.js','model.js','backend.js','live-ui.js','kiosk-art.js'])await copyFile('src/'+file,'dist/'+file);
await mkdir('dist/setup',{recursive:true});
await copyFile('supabase/008_website_identity.sql','dist/setup/008_website_identity.sql');
for(const file of ['inventory.html','inventory.js','inventory-page.js','inventory.css'])await copyFile('src/'+file,'dist/'+file);
for(const file of ['hyphen.html','hyphen.js','hyphen-page.js','checkout.js','checkout-ui.js'])await copyFile('src/'+file,'dist/'+file);
for(const file of ['chroma.html','chroma.js','chroma-page.js','chroma.css'])await copyFile('src/'+file,'dist/'+file);
for(const file of ['vendor','scene.js','audio.js','app.js','moon.svg','portal-model.js'])await rm('dist/'+file,{recursive:true,force:true});
await copyFile('src/fluid.html','dist/fluid.html');
await mkdir('dist/fluid',{recursive:true});
for(const file of ['app.js','renderer.js','simulation.js','shaders.js','style.css'])await copyFile('src/fluid/'+file,'dist/fluid/'+file);
await mkdir('dist/liquid-kiosk',{recursive:true});
for(const file of ['app.js','gesture.js','sound.js','portal.js','world.js','material-world.js','parcel.js','catalogue.js','object-viewer.js','food-model.js','crown-model.js','style.css'])await copyFile('src/liquid-kiosk/'+file,'dist/liquid-kiosk/'+file);
console.log('Built liquid entrance, connected Hyphen counter, basic kiosk, and liquid playground.');

await copyFile('src/glass.html','dist/glass.html');
await mkdir('dist/glass',{recursive:true});
for(const file of ['app.js','shaders.js','style.css'])await copyFile('src/glass/'+file,'dist/glass/'+file);

await mkdir("dist/vendor/loaders",{recursive:true});
for(const f of ["three.module.js","three.core.js"])await copyFile("node_modules/three/build/"+f,"dist/vendor/"+f);
await copyFile("node_modules/three/examples/jsm/loaders/SVGLoader.js","dist/vendor/loaders/SVGLoader.js");

await cp('src/assets','dist/assets',{recursive:true});

for(const f of ['inventory-records.html','inventory-workspace.js','inventory-workspace-model.js','inventory-workspace.css'])await copyFile('src/'+f,'dist/'+f);

await copyFile('src/inventory-live.js','dist/inventory-live.js');

await copyFile('src/inventory-preparation.js','dist/inventory-preparation.js');

for(const f of ['mail.html','mail.css','mail.js','mail-model.js'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['shops.html','shops.css','shops.js','shop-roster.js'])await copyFile('src/'+f,'dist/'+f);

await copyFile('src/shop-details.js','dist/shop-details.js');

for(const f of ['housing.html','housing.css','housing.js','housing-model.js'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['notice-alerts.js','notice-model.js','mail-notices.js','notices.css'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['messages.html','messages.css','messages.js','social-model.js','social-presence.js'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['portal-navigation.js','portal-shell.js','portal-shell.css'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['gifts.html','gifts.css','gifts.js','gift-model.js'])await copyFile('src/'+f,'dist/'+f);

await copyFile('src/collections.js','dist/collections.js');

for(const f of ['real-rewards.html','real-rewards.css','real-rewards.js','real-rewards-model.js'])await copyFile('src/'+f,'dist/'+f);
for(const f of ['connection-study.html','connection-study.css','connection-study.js'])await copyFile('src/'+f,'dist/'+f);

for(const f of ['emoji-picker.js','emoji-data.json','emoji-data-LICENSE.txt','message-images.js','message-image-header.js'])await copyFile('src/'+f,'dist/'+f);

await copyFile('src/message-content.js','dist/message-content.js');
