import React from 'react';
import {useApp} from './core.jsx';

const services=[
  {id:'shops',name:'Shops',description:'Browse local shops, supplies, and repair services.'},
  {id:'inventory',name:'Inventory',description:'View your equipment and move items between your backpack and home.'},
  {id:'housing',name:'Housing',description:'Find your address, home storage, and invitations.'},
  {id:'mail',name:'Mail',description:'Read letters and notices, track deliveries, and open gifts.'},
  {id:'messages',name:'Messages',description:'Talk with friends and local businesses.'},
  {id:'chroma',name:'Chroma',description:'Check your balance, savings, and recent transactions.'},
];

export function ResidentServices() {
  const {go,sample}=useApp();

  return <section className="resident-services" aria-labelledby="resident-services-heading">
    <h2 id="resident-services-heading">Resident services</h2>
    <ul className="resident-service-list">
      {services.map(({id,name,description})=><li key={id}>
        <h3><a href={'/'+id+'.html'+(sample?'?mode=sample':'')}
          onClick={event=>{
            if(event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
            event.preventDefault();
            go(id);
          }}>{name}</a></h3>
        <p>{description}</p>
      </li>)}
    </ul>
  </section>;
}
