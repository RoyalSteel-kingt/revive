import React, {useEffect, useState} from 'react';
import {
  Badge, Button, DefinitionList, Empty, Field, LoadingState, Modal, Notice, Panel,
  ResourceState, Row, Tabs, date, money, readLocal, rpc, saveLocal, useApp, useResource,
} from './core.jsx';
import {groups, sampleOffers, shops} from '../src/shop-roster.js';
import {couponPrice, couponReason, positions} from '../src/shop-details.js';
import {sampleMail} from '../src/mail-model.js';
import serviceKitImage from './assets/flux-service-kit.webp';
import mealPackImage from './assets/meal-pack.webp';
import rifleImage from './assets/flux-rifle.webp';
import giftBoxImage from './assets/gift-box.webp';

const productPhotos = new Map([
  ['flux-service-kit', serviceKitImage],
  ['meal-pack', mealPackImage],
  ['flux-rifle', rifleImage],
  ['gift-box', giftBoxImage],
]);

const sampleShopState = () => ({
  visited: shops.map(shop => shop.id), favorites: [], balance: 500, orders: [], sales: [], coupons: [],
});

function applyExample(state, action) {
  if (action.type==='favorite') {
    state.favorites=action.value?[...state.favorites,action.shop]:state.favorites.filter(id=>id!==action.shop);
  } else if (action.type==='purchase') {
    const price=action.body.p_price;
    if (state.balance<price) throw Error('Not enough example Chroma.');
    const coupon=state.coupons.find(c=>c.id===action.body.p_coupon);
    if (action.body.p_coupon&&!coupon?.quantity) throw Error('This coupon is no longer available.');
    if (coupon) coupon.quantity--;
    const id=crypto.randomUUID();
    const created_at=new Date().toISOString();
    state.balance-=price;
    state.orders.unshift({id,shop_id:action.shop,item_name:action.name,amount:price,created_at});
    const mail=readLocal('firstlight-react-sample/mail',sampleMail);
    mail.letters.unshift({
      id, order_id:id, sender:shops.find(shop=>shop.id===action.shop).name, subject:'A package for your home',
      kind:'shop', body:action.name+' is on its way to your home.', created_at, attachments:[],
      delivery:{status:'in_transit',eta:new Date(Date.now()+300000).toISOString(),address:'Your sample apartment'},
    });
    saveLocal('firstlight-react-sample/mail',mail);
  } else {
    if (state.sales.some(sale=>sale.id===action.body.p_item)) throw Error('This item has already been sold.');
    state.balance+=action.body.p_price;
    state.sales.unshift({id:action.body.p_item,item_name:action.name,price:action.body.p_price,created_at:new Date().toISOString()});
  }
  return state;
}

export function Shops({initialShop=null}) {
  const {go}=useApp();
  const resource=useResource({
    name:'shops',
    seed:sampleShopState,
    load:()=>rpc('shop_directory'),
    async change(action,id) {
      if (action.type==='favorite') await rpc('shop_favorite',{p_shop:action.shop,p_value:action.value});
      else await rpc(action.type==='purchase'?'shop_purchase_coupon':'shop_sell',{...action.body,p_request:id});
      return rpc('shop_directory');
    },
    reduce:applyExample,
  });
  const shop=shops.find(shop=>shop.id===initialShop);
  return <>
    {shop
      ? <header className={'merchant-banner merchant-'+shop.id} style={{'--shop-color':shop.accent}}>
          <div className="merchant-copy">
            <button className="text-link merchant-back" type="button" onClick={()=>go('shops')}>← All shops</button>
            <h2>{shop.name}</h2>
            <p>{shop.tagline}</p>
          </div>
        </header>
      : <header className="market-heading">
          <div><h2>Shops in Firstlight</h2><p>Find supplies, neighborhood favorites, and places to get your gear serviced.</p></div>
          <Button onClick={()=>go('rewards')}>Real-world rewards</Button>
        </header>}
    <ResourceState resource={resource}>
      {resource.data&&(shop?<Storefront shop={shop} resource={resource}/>:<ShopDirectory resource={resource}/>)}
    </ResourceState>
  </>;
}

function ShopDirectory({resource}) {
  const {go}=useApp();
  const [query,setQuery]=useState('');
  const [group,setGroup]=useState('all');
  const [favoritesOnly,setFavoritesOnly]=useState(false);
  const {visited,favorites=[],balance}=resource.data;
  const locked=shops.length-visited.length;
  const matches=shops.filter(shop=>visited.includes(shop.id)
    &&(group==='all'||shop.group===group)
    &&(!favoritesOnly||favorites.includes(shop.id))
    &&[shop.name,shop.specialty,shop.repairService].join(' ').toLowerCase().includes(query.trim().toLowerCase()));
  return <>
    <div className="market-tools">
      <Field label="Search shops" type="search" placeholder="Shop name or service" value={query} onChange={e=>setQuery(e.target.value)}/>
      <Field label="Category"><select value={group} onChange={e=>setGroup(e.target.value)}>
        <option value="all">All shops</option>
        {Object.entries(groups).map(([key,name])=><option key={key} value={key}>{name}</option>)}
      </select></Field>
      <Button aria-pressed={favoritesOnly} onClick={()=>setFavoritesOnly(!favoritesOnly)}>Favorites</Button>
      <div className="merchant-wallet"><small>Serving balance</small><strong>{money(balance)}</strong></div>
    </div>
    {Object.entries(groups).map(([key,label])=>{
      const members=matches.filter(shop=>shop.group===key);
      if (!members.length) return null;
      return <section className="market-category" key={key}>
        <h3>{label}</h3>
        <div className="merchant-list">
          {members.map(shop=>{
            const isFavorite=favorites.includes(shop.id);
            return <article className="merchant-ticket" key={shop.id} style={{'--shop-color':shop.accent}}>
              <div className={'merchant-ticket-sign merchant-'+shop.id}><h4>{shop.name}</h4></div>
              <div className="merchant-ticket-body">
                <p>{shop.specialty}</p>
                {shop.repairService&&<p className="merchant-service">{shop.repairService} · In person</p>}
                <div className="merchant-ticket-actions">
                  <Button variant="primary" aria-label={'Visit '+shop.name} onClick={()=>go('shops',null,{shop:shop.id})}>Visit shop</Button>
                  <Button aria-label={'Favorite '+shop.name} aria-pressed={isFavorite}
                    onClick={()=>resource.mutate({type:'favorite',shop:shop.id,value:!isFavorite})}>{isFavorite?'★':'☆'}</Button>
                </div>
              </div>
            </article>;
          })}
        </div>
      </section>;
    })}
    {!matches.length&&<Panel><Empty title={query||favoritesOnly?'No matching shops':'No discovered shops in this category'}>Try another category or clear your filters.</Empty></Panel>}
    {locked>0&&<p className="muted">{locked} {locked===1?'shop opens':'shops open'} in this directory after discovery.</p>}
  </>;
}

function Storefront({shop,resource}) {
  const {sample,go,journey}=useApp();
  const [view,setView]=useState('browse');
  const [catalog,setCatalog]=useState(null);
  const [quotes,setQuotes]=useState([]);
  const [error,setError]=useState('');
  const [loading,setLoading]=useState(false);
  const [inspection,setInspection]=useState(null);
  const [review,setReview]=useState(null);
  const [couponId,setCouponId]=useState('');
  const [delivery,setDelivery]=useState(null);
  const isHyphen=shop.id==='hyphen';

  async function openShop() {
    setLoading(true);
    setError('');
    try {
      if (sample) {
        setCatalog({offers:sampleOffers(shop),home:{unit_id:'sample-home',address:'Your sample apartment'}});
        setQuotes(isHyphen&&!resource.data.sales.length?[{id:'sample-relay',name:'Recovered focusing assembly',condition:100,position:'home',price:30}]:[]);
      } else {
        const [stock,buyback]=await Promise.all([rpc('shop_catalog',{p_shop:shop.id}),isHyphen?rpc('shop_quotes'):[]]);
        setCatalog(stock);
        setQuotes(buyback);
      }
    } catch (error) {
      setError(error.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(()=>{openShop();},[shop.id]);

  const coupons=(sample?resource.data.coupons:catalog?.coupons)||[];
  const coupon=coupons.find(option=>option.id===couponId);
  const price=review?(review.type==='purchase'?couponPrice(review.item.price,coupon):review.item.price):0;
  const orders=sample?resource.data.orders.filter(order=>order.shop_id===shop.id):catalog?.orders||[];
  const sales=sample&&isHyphen?resource.data.sales:catalog?.sales||[];
  const tabs=[
    ['browse','Browse goods'],
    ...(isHyphen?[['sell','Sell to us']]:[]),
    ...(shop.repairService?[['repairs','Repair counter']]:[]),
    ['orders','Your orders'],
  ];

  function begin(type,item) {
    setCouponId('');
    setReview({type,item});
  }

  function openDelivery(orderId) {
    go('mail',null,{folder:'deliveries',order:orderId,...(journey?{journey:'delivery'}:{})});
  }

  async function confirm() {
    const {type,item}=review;
    const body=type==='purchase'
      ? {p_shop:shop.id,p_offer:item.id,p_price:price,p_home:catalog.home.unit_id,p_coupon:couponId||null}
      : {p_item:item.id,p_price:price};
    const result=await resource.mutate({type,shop:shop.id,name:item.name,body});
    if (!result) return;
    setReview(null);
    if (sample) {
      if (type==='sell') setQuotes(quotes=>quotes.filter(quote=>quote.id!==item.id));
      else if (result.orders[0]?.id) setDelivery({order:result.orders[0].id,offer:item.id,name:item.name});
    } else {
      await openShop();
    }
  }

  return <>
    <div className="merchant-bar">
      <Tabs items={tabs} value={view} onChange={setView} label={shop.name+' departments'}/>
      <div className="merchant-wallet"><small>Serving balance</small><strong>{money(resource.data.balance)}</strong></div>
    </div>
    <Notice error>{error}</Notice>
    {!catalog&&!error&&<LoadingState>Loading storefront…</LoadingState>}
    {!catalog&&error&&<Button busy={loading} onClick={openShop}>Retry storefront</Button>}
    {delivery&&<aside className="journey-step" aria-label="Order placed">
      <div><strong>Order placed</strong><p>{delivery.name} is on its way to your home.</p></div>
      <Button variant="primary" onClick={()=>openDelivery(delivery.order)}>Open delivery in Mail</Button>
    </aside>}
    {journey&&!delivery&&<aside className="journey-step" aria-label="Example delivery">
      <div><strong>Example delivery · 1 of 2</strong><p>Order a meal pack to see how a shop purchase appears in Mail.</p></div>
      <Button onClick={()=>go('presentation',true,{chapter:'shops'})}>Return to presentation</Button>
    </aside>}
    {catalog&&view==='browse'&&<>
      <header className="shelf-heading">
        <div><h3>On the shelf</h3><p>{catalog.home?'Orders deliver to '+catalog.home.address+'.':'Set a home address to receive shop orders.'}</p></div>
        <Button busy={loading} onClick={openShop}>Refresh stock</Button>
      </header>
      <div className="product-shelf">
        {catalog.offers.map(item=><article className="shelf-product" key={item.id}>
          {productPhotos.has(item.definition_id)&&<div className="shelf-window">
            <img className="shelf-photo" alt="" loading="lazy" width="460" height="460" src={productPhotos.get(item.definition_id)}/>
          </div>}
          <div className="shelf-copy">
            <h4>{item.name}</h4>
            <p>{item.description}</p>
            <div className="shelf-price"><strong>{money(item.price)}</strong>{item.condition!=null&&<small>{item.condition}% condition</small>}</div>
            <div className="shelf-actions">
              <Button variant="primary" disabled={!catalog.home} onClick={()=>begin('purchase',item)}>{journey&&item.definition_id==='meal-pack'?'Review meal pack':'Buy '+item.name}</Button>
              <button className="text-link" type="button" aria-label={'Details for '+item.name} onClick={()=>setInspection(item)}>Details</button>
            </div>
          </div>
        </article>)}
      </div>
      {!catalog.offers.length&&<Panel><Empty title="No items on the shelf"/></Panel>}
    </>}
    {catalog&&view==='sell'&&<Panel title="Buyback quotes">
      {quotes.map(quote=><Row key={quote.id} title={quote.name} detail={quote.position+' · '+quote.condition+'%'} end={money(quote.price)}>
        <Button onClick={()=>begin('sell',quote)}>Review sale</Button>
      </Row>)}
      {!quotes.length&&<Empty title="No eligible items for buyback"/>}
    </Panel>}
    {catalog&&view==='repairs'&&<Panel title={shop.repairService}>
      <p>Visit the {shop.name} counter in person for this service.</p>
      <Button onClick={()=>go('repairs')}>Equipment care and service kits</Button>
    </Panel>}
    {catalog&&view==='orders'&&<Panel title="Receipts and deliveries">
      {orders.map(order=><Row key={order.id} title={order.item_name} detail={date(order.created_at)} end={money(order.amount)}>
        <Button onClick={()=>openDelivery(order.id)}>Open delivery</Button>
      </Row>)}
      {sales.map((sale,index)=><Row key={sale.id||index} title={sale.item_name} detail={'Sold · '+date(sale.created_at)} end={money(sale.price)}/>)}
      {!orders.length&&!sales.length&&<Empty title="No transactions with this shop yet"/>}
    </Panel>}
    {inspection&&<Modal title={inspection.name} onClose={()=>setInspection(null)}>
      {productPhotos.has(inspection.definition_id)&&<img className="inspection-photo" src={productPhotos.get(inspection.definition_id)} alt={inspection.name}/>}
      <p>{inspection.description}</p>
      <DefinitionList rows={[
        ['Manufacturer',inspection.manufacturer||'Not listed'],['Condition',inspection.condition+'%'],
        ['Weight',inspection.weight!=null?inspection.weight+' lb':null],['Position',positions[inspection.slot]||'Carried item'],
        ['Capacity',inspection.capacity],['Allowance',inspection.allowance?inspection.allowance+' lb':null],['Price',money(inspection.price)],
      ]}/>
      <Button variant="primary" disabled={!catalog.home} onClick={()=>{begin('purchase',inspection);setInspection(null);}}>Review purchase</Button>
    </Modal>}
    {review&&<Modal title={review.type==='purchase'?'Review purchase':'Review sale'} onClose={()=>setReview(null)}>
      <h3>{review.item.name}</h3>
      <p>{review.type==='purchase'?'Deliver to '+catalog.home.address:'Sell from '+review.item.position+'.'}</p>
      {review.type==='purchase'&&<Field label="Coupon"><select value={couponId} onChange={e=>setCouponId(e.target.value)}>
        <option value="">No coupon</option>
        {coupons.map(option=><option key={option.id} value={option.id} disabled={!!couponReason(option,shop.id,review.item.price)}>
          {option.label} · {couponReason(option,shop.id,review.item.price)||option.percent_off+'% off'}
        </option>)}
      </select></Field>}
      <p className="price">{money(price)}</p>
      <Notice error>{resource.error}</Notice>
      <Button variant="primary" busy={resource.busy} onClick={confirm}>Confirm {review.type==='purchase'?'purchase':'sale'}</Button>
    </Modal>}
  </>;
}
