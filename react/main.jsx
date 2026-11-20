import React,{useCallback,useEffect,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {AppContext,Button,Notice,api} from './core.jsx';
import {Account,Inventory} from './account-inventory.jsx';
import {Mail} from './mail.jsx';
import {Chroma,Housing} from './banking-housing.jsx';
import {Shops} from './shops.jsx';
import {shops} from '../src/shop-roster.js';
import {Messages} from './messages.jsx';
import {Gifts} from './gifts.jsx';
import {Rewards} from './rewards.jsx';
import {Repairs} from './repairs.jsx';
import {ColonyNotices} from './signals.jsx';
import {Presentation} from './presentation.jsx';
import './theme.css';
import './colony.css';
import './firstlight.css';
import './motion.css';
import './blue-hour.css';
import './identity-layout.css';
import './site-layout.css';
import './resident-interface.css';
import './presentation.css';

const routes={
  presentation:{file:'presentation.html',title:'Presentation',description:'A guided tour of the world and resident services.'},
  account:{file:'index.html',title:'Account',description:'Your identity in Firstlight.'},
  inventory:{file:'inventory.html',title:'Inventory',description:'Your equipment, carried supplies and home storage.'},
  mail:{file:'mail.html',title:'Mail',description:'Letters, deliveries and colony notices.'},
  shops:{file:'shops.html',title:'Shops',description:'Your discovered storefronts and supplies.'},
  housing:{file:'housing.html',title:'Housing',description:'Your home, storage and invitations.'},
  messages:{file:'messages.html',title:'Messages',description:'Conversations with friends and businesses.'},
  chroma:{file:'chroma.html',title:'Chroma',description:'Your spending balance, savings and activity.'},
  gifts:{file:'gifts.html',parent:'mail',title:'Gifts',description:'Prepare a parcel or send a little Chroma.'},
  rewards:{file:'real-rewards.html',parent:'shops',title:'Real-world rewards',description:'Firstlight keepsakes and postal orders.'},
  repairs:{file:'repairs.html',parent:'inventory',title:'Equipment care',description:'Use a service kit on compatible equipment and review earlier receipts.'}
};
const serviceLinks=['shops','housing','inventory','mail','messages','chroma','presentation'];
const aliases={'hyphen.html':'shops','inventory-records.html':'inventory','classic.html':'account','kiosk.html':'account','fluid.html':'account','glass.html':'account','connection-study.html':'account'};
function readLocation() {
  const file=location.pathname.split('/').pop()||'index.html';
  const params=new URLSearchParams(location.search);
  return {shop:file==='hyphen.html'?'hyphen':params.get('shop'),journey:params.get('journey')==='delivery'&&params.get('mode')==='sample',chapter:params.get('chapter'),route:aliases[file]||Object.keys(routes).find(k=>routes[k].file===file)||'account',sample:params.get('mode')==='sample',key:location.pathname+location.search};
}
class PageError extends React.Component {
  state={error:null};
  static getDerivedStateFromError(error){return {error};}
  componentDidCatch(error){console.error('Firstlight page failed',error);}
  render(){return this.state.error?<section className="panel"><div className="panel-head"><h2>This page needs a refresh</h2></div><div className="panel-body"><Notice error>{this.state.error.message}</Notice><Button onClick={()=>location.reload()}>Reload page</Button></div></section>:this.props.children;}
}
function App(){
  const [view,setView]=useState(readLocation),[menu,setMenu]=useState(false),[toast,setToast]=useState(''),[sessionVersion,bump]=useState(0);
  const notificationTimer=useRef(null),heading=useRef(null);
  const notify=useCallback(text=>{setToast(text);clearTimeout(notificationTimer.current);notificationTimer.current=setTimeout(()=>setToast(''),4500);},[]);
  function go(route=null,sample=null,extra={},anchor='') {
    const key=route||view.route;
    const params=new URLSearchParams();
    if(sample??view.sample)params.set('mode','sample');
    if(!route&&view.route==='shops'&&view.shop)params.set('shop',view.shop);
    for(const [k,v] of Object.entries(extra))params.set(k,v);
    history.pushState(null,'','/'+routes[key].file+(params.size?'?'+params:'')+(anchor?'#'+anchor:''));
    setView(readLocation());setMenu(false);
    if(!anchor)window.scrollTo({top:0,behavior:'instant'});
    requestAnimationFrame(()=>{
      const target=anchor?document.getElementById(anchor):heading.current;
      if(anchor)target?.scrollIntoView();
      target?.focus({preventScroll:true});
    });
  }
  useEffect(()=>{
    const pop=()=>{setView(readLocation());setMenu(false);};
    const changed=e=>{if(e.key==='revive-auth-v1'||e.key===null){api.session=new (api.constructor)().session;bump(n=>n+1);}};
    window.addEventListener('popstate',pop);window.addEventListener('storage',changed);
    return()=>{window.removeEventListener('popstate',pop);window.removeEventListener('storage',changed);clearTimeout(notificationTimer.current);};
  },[]);
  useEffect(()=>{document.title='Firstlight Online · '+(view.route==='shops'&&shops.find(s=>s.id===view.shop)?.name||routes[view.route].title);},[view.route,view.shop]);
  useEffect(()=>{if(location.hash==='#resident-account')document.getElementById('resident-account')?.scrollIntoView();},[]);
  const meta=routes[view.route],active=meta.parent||view.route;
  const presenting=view.route==='presentation';
  const storefront=view.route==='shops'?shops.find(shop=>shop.id===view.shop):null;
  const customHeading=presenting||view.route==='account'||view.route==='shops';
  const modeLabel=view.sample?'Use my account':'Explore example';
  const section=meta.parent||(Object.values(routes).some(r=>r.parent===view.route)?view.route:null);
  const context={...view,go,notify,sessionVersion,bumpSession:()=>bump(n=>n+1)};
  return <AppContext.Provider value={context}>
    <a className="skip-link" href="#main-content">Skip to content</a>
    <header className={'masthead '+(menu?'menu-open':'')}>
      <a href={'/index.html'+(view.sample?'?mode=sample':'')} className="brand" onClick={e=>{if(!e.metaKey&&!e.ctrlKey&&!e.shiftKey&&!e.altKey){e.preventDefault();go('account');}}}><strong>Firstlight Online</strong></a>
      <nav id="site-navigation" className="primary-nav" aria-label="Firstlight services">
        {serviceLinks.map(key=><a key={key} href={'/'+routes[key].file+(view.sample?'?mode=sample':'')} aria-current={active===key?'page':undefined} onClick={e=>{if(!e.metaKey&&!e.ctrlKey&&!e.shiftKey&&!e.altKey){e.preventDefault();go(key);}}}>{routes[key].title}</a>)}
      </nav>
      <div className="header-tools">
        <div className="sample-tools">
          {view.sample&&<span className="header-status">Example workspace</span>}
          {view.route!=='account'&&(view.sample||api.session)&&<Button className="mode-switch" onClick={()=>go(null,!view.sample)}>{modeLabel}</Button>}
        </div>
        <a className="account-link" href={'/index.html'+(view.sample?'?mode=sample':'')+'#resident-account'} onClick={e=>{if(!e.metaKey&&!e.ctrlKey&&!e.shiftKey&&!e.altKey){e.preventDefault();go('account',null,{},'resident-account');}}}>Account</a>
        <Button onClick={()=>setMenu(!menu)} aria-expanded={menu} aria-controls="site-navigation" className="mobile-menu">Menu</Button>
      </div>
    </header>
    <div className="site-layout" data-page={view.route}>
      <main id="main-content">
        {!customHeading&&<ColonyNotices/>}
        <div className="page" data-route={view.route} key={view.key}>
          {view.route!=='account'&&(customHeading
            ? <h1 className="visually-hidden" tabIndex="-1" ref={heading}>{storefront?.name||meta.title}</h1>
            : <div className="workspace-heading">
                <div>
                  {meta.parent&&<p className="workspace-parent">{routes[meta.parent].title}</p>}
                  <h1 tabIndex="-1" ref={heading}>{meta.title}</h1>
                  <p>{meta.description}</p>
                </div>
              </div>)}
          {section&&view.route!=='shops'&&<nav className="section-nav" aria-label={routes[section].title+' sections'}>
            {Object.entries(routes).filter(([key,r])=>key===section||r.parent===section).map(([key,r])=><a key={key} href={'/'+r.file+(view.sample?'?mode=sample':'')} aria-current={key===view.route?'page':undefined} onClick={e=>{e.preventDefault();go(key);}}>{r.title}</a>)}
          </nav>}
          <PageError key={view.key}><Page route={view.route} shop={view.shop} heading={heading}/></PageError>
        </div>
        {customHeading&&<ColonyNotices/>}
        <footer><span>Firstlight Online</span><span>Revive · Firstlight Colony</span></footer>
      </main>
    </div>
    {toast&&<div className="toast" role="status">{toast}<Button aria-label="Dismiss notification" onClick={()=>setToast('')}>×</Button></div>}
  </AppContext.Provider>;
}
function Page({route,shop,heading}){
  switch(route){
    case 'presentation':return <Presentation/>;
    case 'account':return <Account titleRef={heading}/>;
    case 'inventory':return <Inventory/>;
    case 'mail':return <Mail/>;
    case 'chroma':return <Chroma/>;
    case 'shops':return <Shops initialShop={shop}/>;
    case 'repairs':return <Repairs/>;
    case 'housing':return <Housing/>;
    case 'messages':return <Messages/>;
    case 'gifts':return <Gifts/>;
    case 'rewards':return <Rewards/>;
  }
}
createRoot(document.getElementById('root')).render(<App/>);
