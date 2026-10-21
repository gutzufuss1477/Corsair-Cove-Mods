do
  local module=assert(load(warehouseUiSource,'@WarehouseUI.lua'))()
  local nextId=10000
  local function widget(name)
    nextId=nextId+8;local address=nextId
    local w={children={},WidthOverride=740,HeightOverride=270,bOverride_WidthOverride=true,bOverride_HeightOverride=false,
      RenderTransform={Scale={X=1,Y=1}},RenderTransformPivot={X=0,Y=0}}
    function w:GetFullName()return 'Widget Fixture.'..name end
    function w:GetAddress()return address end
    function w:IsValid()return not self.dead end
    function w:GetChildrenCount()return #self.children end
    function w:GetChildAt(i)return self.children[i+1]end
    function w:SetWidthOverride(v)self.WidthOverride=v;self.bOverride_WidthOverride=true end
    function w:SetHeightOverride(v)self.HeightOverride=v;self.bOverride_HeightOverride=true end
    function w:ClearWidthOverride()self.bOverride_WidthOverride=false end
    function w:ClearHeightOverride()self.bOverride_HeightOverride=false end
    function w:SetRenderScale(v)self.RenderTransform.Scale=v end
    function w:SetRenderTransformPivot(v)self.RenderTransformPivot=v end
    function w:GetCachedGeometry()
      if self.geometryFails then error('Geometry not ready') end
      if self.geometryEmpty then return {} end
      return {X=self.layoutWidth or 1260,Y=270}
    end
    return w
  end
  local function add(parent,name,child)
    child=child or widget(name);parent.children[#parent.children+1]=child;parent[name]=child;return child
  end
  local function tile(parent,name,width,height,count)
    local w=add(parent,name);w.entryW=width;w.entryH=height;w.count=count;w.entries={widget(name..'Entry')}
    function w:GetEntryWidth()return self.entryW end
    function w:GetEntryHeight()return self.entryH end
    function w:SetEntryWidth(v)self.entryW=v end
    function w:SetEntryHeight(v)self.entryH=v end
    function w:GetNumItems()return self.count end
    function w:GetDisplayedEntryWidgets()
      if self.arrayMode~='proxy' then return self.entries end
      return {ForEach=function(_,fn)for i,e in ipairs(self.entries)do fn(i,{get=function()return e end})end end}
    end
    return w
  end
  local root=widget('WBP_Storage_C_1')
  local frame=add(root,'WBP_DefaultStructureScreen')
  -- Live 1.2.2: the real outer SizeBox_0 stayed at 800 while an inner
  -- SizeBox was set to 1340. SizeBox_0 is not exposed as a Blueprint field.
  local outer=add(frame,'SizeBox_0');outer.WidthOverride=800;frame.SizeBox_0=nil
  local nested=add(frame,'HeaderIcons')
  nested.WidgetTree=widget('HeaderTree')
  local iconTree=widget('IconTree');nested.WidgetTree.RootWidget=iconTree
  local iconBox=add(iconTree,'SizeBox_0');iconBox.WidthOverride=72
  -- A full traversal exhausts its safety bound before reaching the stock.
  for i=1,10 do
    local group=add(iconTree,'Group'..i)
    for j=1,70 do add(group,'Icon'..j) end
  end
  local panel=add(frame,'RightPanel');local widthBox=add(panel,'SizeBox');widthBox.bOverride_WidthOverride=false
  local warehouse=add(root,'WBP_StructureStorageBuilding');local refresh=0
  function warehouse:GetIsTradePost()return self.trade==true end
  function warehouse:FillStorageItemsList()refresh=refresh+1 end
  function warehouse:FillEmptyStorageItemsList()refresh=refresh+1 end
  local trans=add(warehouse,'WBP_Transportation');local heightBox=add(trans,'InStorages')
  local connections=tile(trans,'ListResourceConnections',220,270,10)
  local transportRefresh,transportModel=0,nil
  function trans:InitializeInStorages()
    transportRefresh=transportRefresh+1
    if transportModel then
      -- Model the audited native '+' predicate: allocated < capacity.
      connections.count=transportModel.resources+(transportModel.allocated<transportModel.capacity and 1 or 0)
    end
  end
  local stock=tile(warehouse,'ListStorage',132,150,45)
  local empty=tile(warehouse,'ListEmptyStorage',132,150,45)
  local controls=add(root,'WBP_StorageControls');local controlsPanel=add(controls,'Panel');add(controlsPanel,'SizeBox');add(controls,'PanelSize')
  local rows=tile(controls,'ListControls',660,80,9)
  local viewport=1920
  local controller=module.new({all=function(class)assert(class=='WBP_Storage_C');return {root}end,
    find=function(path)
      if path=='/Script/UMG.Default__SlateBlueprintLibrary' then
        return {GetLocalSize=function(_,geometry)return {X=geometry.X or 0,Y=geometry.Y or 0} end}
      end
      assert(path=='/Script/UMG.Default__WidgetLayoutLibrary')
      return {GetViewportSize=function()return {X=viewport,Y=1080}end,GetViewportScale=function()return 1 end}
    end})
  local cfg={WarehouseEnabled=true,WarehouseTypes=9,Revision='ui1'}
  local native={WarehouseSelected='1',WarehouseSelectedResources='9',WarehouseSelectedSlots='45'}
  local r=controller:tick(cfg,native)
  assert(outer.WidthOverride==1340 and iconBox.WidthOverride==72,
    'resize the outer frame in its owning tree, never a same-named nested icon')
  assert(r.errors==0,r.error);assert(r.active==1 and widthBox.WidthOverride==1340 and heightBox.HeightOverride==540)
  assert(stock.entryW>100 and stock.entryW<132 and empty.entryW==stock.entryW and stock.entryH==128)
  assert(connections.entryW==220 and connections.entries[1].RenderTransform.Scale.X==1)
  assert(rows.entryW==1260 and rows.entryH==80 and refresh==2)
  assert(transportRefresh==1,'capacity activation rebuilds the native resource/plus list too')
  controller:tick(cfg,native);assert(refresh==2,'unchanged layout does not rebuild inventory models')
  assert(transportRefresh==1,'unchanged polls preserve resource data objects and their handlers')
  -- Actual bundled UE4SS return conversion, with real nine-goods count:
  -- FGeometry's unreflected native members disappear from the returned table.
  connections.count=9;connections.geometryEmpty=true
  stock.geometryEmpty=true;empty.geometryEmpty=true
  r=controller:tick(cfg,native);assert(r.errors==0,r.error)
  assert(r.resourceColumns==5 and r.resourceRows==2 and heightBox.HeightOverride==540,
    'opaque FGeometry must not reserve five rows and leave an 810-unit gap below nine goods')
  assert(r.widthSource=='panel' and r.availableWidth==1240)
  assert(stock.entryW<128 and empty.entryW==stock.entryW,'opaque geometry also uses the widened stock panel')
  for i=1,5 do
    connections.entryW=220;heightBox.HeightOverride=540 -- original regenerated-card callbacks
    r=controller:tick(cfg,native)
    assert(heightBox.HeightOverride==540 and transportRefresh==1,
      'compact layout remains stable without recreating resource models')
  end
  connections.geometryEmpty=false;stock.geometryEmpty=false;empty.geometryEmpty=false;connections.count=10
  connections.entryW=660 -- a previous one-item layout was reused.
  controller:tick(cfg,native);assert(connections.entryW==220,'layout survives normal Blueprint updates')
  cfg.WarehouseEnabled=false;controller:tick(cfg,native)
  assert(widthBox.WidthOverride==1340,'existing extra goods stay accessible after disabling')
  native.WarehouseSelected='0';r=controller:tick(cfg,native);assert(r.errors==0,r.error)
  assert(widthBox.WidthOverride==740 and not widthBox.bOverride_WidthOverride)
  assert(outer.WidthOverride==800 and iconBox.WidthOverride==72,'restore the real outer frame without changing header icons')
  assert(heightBox.HeightOverride==270 and not heightBox.bOverride_HeightOverride)
  assert(stock.entryW==132 and stock.entryH==150 and connections.entryW==220 and rows.entryW==660)
  assert(stock.entries[1].RenderTransform.Scale.X==1 and stock.entries[1].RenderTransformPivot.X==0)
  native.WarehouseSelected='1';native.WarehouseSelectedResources='3';controller:tick(cfg,native)
  assert(widthBox.WidthOverride==1340,'extra allocated slots stay accessible even with only three goods')
  stock.count=15;controller:tick(cfg,native)
  assert(widthBox.WidthOverride==740,'disabled normal warehouses retain the vanilla layout')
  cfg.WarehouseEnabled=true;viewport=1280;r=controller:tick(cfg,native);assert(r.errors==0,r.error)
  assert(widthBox.WidthOverride<=1280*.72 and heightBox.HeightOverride==1080,'narrow screens use additional rows instead of overflowing')
  stock.entries[1]=widget('replacement entry');controller:tick(cfg,native)
  assert(stock.entries[1].RenderTransform.Scale.X==.82,'virtualized replacement entries get scaled')
  -- Regression: real UFunction return values are Lua tables without ForEach.
  assert(type(stock:GetDisplayedEntryWidgets())=='table' and stock:GetDisplayedEntryWidgets().ForEach==nil)
  stock.arrayMode='proxy';controller:tick(cfg,native)
  assert(stock.entries[1].RenderTransform.Scale.X==.82,'reflected TArray proxies remain supported')
  stock.arrayMode=nil;stock.entries={};r=controller:tick(cfg,native)
  assert(r.errors==0,'empty virtualized lists are valid Lua arrays')
  viewport=1920
  for _,types in ipairs({6,9}) do
    cfg.WarehouseTypes=types;native.WarehouseSelectedSlots=tostring(types*5)
    for resources=2,types do
      transportModel={resources=resources,allocated=resources*5,capacity=types*5}
      native.WarehouseSelectedResources=tostring(resources)
      local before=transportRefresh
      r=controller:tick(cfg,native);assert(r.errors==0,r.error)
      assert(transportRefresh==before+1,'resource-count changes refresh the original selection model')
      local expected=resources+(resources<types and 1 or 0)
      assert(connections.count==expected,'the fourth through ninth resource remain reachable via the native plus item')
      assert(r.resourceItems==expected and r.resourceColumns==5 and r.resourceRows==math.max(expected>3 and 2 or 1,math.ceil(expected/5)),
        'diagnostics report actual native-model item count separately from requested layout')
      assert(r.requestedWidth==1340 and r.availableWidth==1240 and r.entryWidth==220 and type(r.stockItems)=='number')
      assert(heightBox.HeightOverride==math.max(expected>3 and 2 or 1,math.ceil(expected/5))*270,'every resource and the plus item fit in the allocated rows')
      controller:tick(cfg,native);assert(transportRefresh==before+1,'no unnecessary rebuild after resource refresh')
    end
  end
  -- Width requests do not describe the space Slate actually allocated.
  -- Cover the reported fourth card appearing briefly and then being clipped
  -- after a Blueprint rebuild or a still-narrow first layout frame.
  cfg.WarehouseTypes=9;native.WarehouseSelectedResources='3'
  transportModel={resources=3,allocated=15,capacity=45}
  connections.layoutWidth=660;stock.layoutWidth=660;empty.layoutWidth=660
  r=controller:tick(cfg,native);assert(r.errors==0,r.error)
  assert(connections.count==4 and r.resourceColumns==2 and r.resourceRows==2)
  assert(heightBox.HeightOverride==540 and r.entryWidth*r.resourceColumns<=r.availableWidth,
    'the fourth native card gets a second row when actual width still fits only two or three')
  assert(stock.entryW==128 and empty.entryW==128,'stock columns use their actual width too')
  connections.entryW=220;heightBox.HeightOverride=540 -- actual game Blueprint rebuild for >3 items
  r=controller:tick(cfg,native)
  assert(connections.count==4 and r.resourceRows==2 and heightBox.HeightOverride==540,
    'normal rebuild cannot leave the fourth card in a clipped, unallocated row')
  connections.layoutWidth=1260;stock.layoutWidth=1260;empty.layoutWidth=1260
  r=controller:tick(cfg,native)
  assert(r.resourceColumns==5 and r.resourceRows==2 and heightBox.HeightOverride==540,
    'after Slate expands, use the new width without rebuilding resource models')
  local before=transportRefresh
  for _,badWidth in ipairs({0,-1,0/0,math.huge}) do
    connections.layoutWidth=badWidth
    r=controller:tick(cfg,native)
    assert(r.errors==0 and r.resourceColumns==5 and r.resourceRows==2 and r.widthSource=='panel',
      'unavailable cached geometry uses the verified panel width')
  end
  connections.geometryFails=true;r=controller:tick(cfg,native)
  assert(r.errors==0 and r.resourceRows==2 and transportRefresh==before,
    'unsupported geometry API uses panel width without altering game list items')
  connections.geometryFails=false;connections.layoutWidth=1260
  -- Lowering the limit does not hide already assigned goods or manufacture a
  -- plus item when the game's native capacity predicate rejects another one.
  cfg.WarehouseEnabled=false;native.WarehouseSelectedSlots='15';native.WarehouseSelectedResources='9'
  transportModel={resources=9,allocated=45,capacity=15}
  r=controller:tick(cfg,native);assert(r.errors==0 and connections.count==9 and widthBox.WidthOverride==1340)
  cfg.WarehouseEnabled=true;cfg.WarehouseTypes=9;transportModel=nil
  native.WarehouseSelected='0';controller:tick(cfg,native)
  warehouse.trade=true;native.WarehouseSelected='1';controller:tick(cfg,native)
  assert(widthBox.WidthOverride==740,'trading-post presentation is excluded')
  warehouse.trade=false;warehouse.ListStorage=nil
  for i,w in ipairs(warehouse.children)do if w==stock then table.remove(warehouse.children,i);break end end
  r=controller:tick(cfg,native);assert(r.errors==1 and r.error:find('Stock list unavailable',1,true),'missing UI fields report an error')
  print('Warehouse UI regression fixtures: opaque FGeometry returns, compact nine-goods panel, generated-card stability, duplicate widget names, actual-width wrapping, restoration and original plus model passed; in-game spacing confirmation remains outstanding')
end
