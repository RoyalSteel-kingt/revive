update public.item_definitions set description='Personal shield-tech designed for field equipment.' where id='field-shield';
update public.item_definitions set description='A compact recovery supply.' where id='health-stim';
update public.item_definitions set description='An elaborate supper, carefully packed for an evening at home.' where id='aurelle-supper';
update public.item_definitions set description='Recovered wire for maintenance and fabrication.' where id='salvage-wire';
update public.item_definitions set description='Processed material for fabrication.' where id='refined-alloy';
insert into shop_private.offers values('trigger:field-shield','trigger','field-shield',100,100,4);
