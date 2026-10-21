-- Runtime layout only: original widgets, list models, tooltips and handlers.
-- No packaged widget assets or inventory records are replaced.
local M={}
function M.new(api)
  local saved,refreshKeys={},{}
  local function valid(o)
    local ok,v=pcall(function()return o:IsValid()end);return ok and v==true
  end
  local function field(o,k)
    local ok,v=pcall(function()return o[k]end);if ok then return v end
  end
  local function id(o)return o:GetFullName()..'@'..tostring(o:GetAddress())end
  local function remember(o)
    local key=id(o);if not saved[key] then saved[key]={} end;return saved[key]
  end
  local function walk(root,visit,ownTreeOnly)
    local seen,n,done={},0,false
    local function step(o)
      if done or not valid(o) then return end
      local key=id(o);if seen[key] or n>=600 then return end
      seen[key]=true;n=n+1
      if visit(o)==true then done=true;return end
      -- Names such as SizeBox_0 repeat in nested Blueprint widgets. A lookup
      -- must stay in its owner's WidgetTree, not pick an icon's inner size box.
      if not ownTreeOnly or o==root then
        local tree=field(o,'WidgetTree');if valid(tree) then step(field(tree,'RootWidget')) end
      end
      local ok,count=pcall(function()return o:GetChildrenCount()end)
      if ok and type(count)=='number' then
        for i=0,math.min(count,100)-1 do step(o:GetChildAt(i)) end
      end
    end
    step(root)
  end
  local function named(root,name)
    local direct=field(root,name);if valid(direct) then return direct end
    local found
    walk(root,function(o)
      if o:GetFullName():match('[%.:]([^%.:]+)$')==name then found=o;return true end
    end,true)
    return found
  end
  local function size(o,axis,value)
    assert(valid(o),'Missing warehouse '..axis..' container')
    local b=remember(o);local key=axis..'Override';local flag='bOverride_'..key
    if not b[key] then b[key]={value=tonumber(o[key]),enabled=o[flag]==true} end
    assert(b[key].value,'Unreadable warehouse size')
    if o[flag]~=true or math.abs(tonumber(o[key])-value)>.01 then o['Set'..key](o,value) end
    assert(o[flag]==true and math.abs(tonumber(o[key])-value)<.1,'Warehouse size readback failed')
  end
  local function scale(o,factor)
    local b=remember(o)
    if not b.scale then
      local s=o.RenderTransform.Scale;local p=o.RenderTransformPivot
      b.scale={X=s.X,Y=s.Y};b.pivot={X=p.X,Y=p.Y}
    end
    o:SetRenderTransformPivot({X=.5,Y=.5})
    o:SetRenderScale({X=b.scale.X*factor,Y=b.scale.Y*factor})
  end
  local function eachEntry(list,fn)
    -- UFunction return arrays are copied to ordinary Lua tables in the bundled
    -- UE4SS build. Reflected array properties can instead be TArray proxies.
    -- Treating both as proxies aborted layout before stock sizing and refresh.
    local entries=list:GetDisplayedEntryWidgets()
    local iterator=field(entries,'ForEach')
    if type(iterator)=='function' then
      iterator(entries,function(_,ref)
        local o=ref:get();if valid(o) then fn(o) end
      end)
    else
      assert(type(entries)=='table','Unsupported warehouse entry array')
      for _,o in ipairs(entries) do if valid(o) then fn(o) end end
    end
  end
  local function tile(list,width,height,factor)
    assert(valid(list),'Missing warehouse tile list')
    local b=remember(list)
    if not b.tile then b.tile={width=list:GetEntryWidth(),height=list:GetEntryHeight()} end
    if math.abs(list:GetEntryWidth()-width)>.01 then list:SetEntryWidth(width) end
    if math.abs(list:GetEntryHeight()-height)>.01 then list:SetEntryHeight(height) end
    eachEntry(list,function(o)scale(o,factor)end)
  end
  local function restoreOne(o)
    local key=id(o);local b=saved[key];if not b then return end
    for _,axis in ipairs({'Width','Height'}) do
      local k=axis..'Override';local old=b[k]
      if old then
        o['Set'..k](o,old.value)
        if not old.enabled then o['Clear'..k](o) end
      end
    end
    if b.tile then
      -- Displayed entries are separate virtualized user widgets, not panel children.
      eachEntry(o,restoreOne)
      o:SetEntryWidth(b.tile.width);o:SetEntryHeight(b.tile.height)
    end
    if b.scale then o:SetRenderScale(b.scale);o:SetRenderTransformPivot(b.pivot) end
    saved[key]=nil
  end
  local function panelWidth(panel,width)
    local box=named(panel,'SizeBox')
    size(box,'Width',width)
  end
  local function viewportWidth(root)
    local ok,width=pcall(function()
      local lib=api.find('/Script/UMG.Default__WidgetLayoutLibrary')
      local v=lib:GetViewportSize(root);local dpi=lib:GetViewportScale(root)
      return v.X/math.max(.25,dpi)
    end)
    return ok and type(width)=='number' and width>0 and width or 1920
  end
  local function listWidth(list,requested)
    -- This UE4SS build converts UFunction struct returns into reflected fields.
    -- FGeometry has none: GetCachedGeometry returns {}, so round-tripping it
    -- through GetLocalSize yields zero, even for a fully laid-out visible list.
    local ok,width=pcall(function()
      local geometry=list:GetCachedGeometry()
      if type(geometry)=='table' and next(geometry)==nil then return nil end
      local lib=api.find('/Script/UMG.Default__SlateBlueprintLibrary')
      return tonumber(lib:GetLocalSize(geometry).X)
    end)
    local source='geometry'
    if not ok or type(width)~='number' or width~=width or width<1 or width==math.huge then
      -- Both outer and inner SizeBoxes have already been set and read back.
      -- Use that configured inner width, not the vanilla 660-unit three-card
      -- panel: nine goods otherwise reserve five rows forever instead of two.
      width=requested;source='panel'
    end
    -- Leave room for the scrollbar and float/pixel rounding at the last column.
    return math.max(1,math.floor(math.min(requested,width)-20)),source
  end
  local function restoreLayout(root)
    local function restoreNamed(owner,name)
      if not valid(owner) then return end
      local o=named(owner,name);if valid(o) then restoreOne(o) end
      return o
    end
    -- Restore only the widgets we edit. A traversal of the entire panel can
    -- exhaust its bound in the header's nested icons before reaching the stock.
    local frame=restoreNamed(root,'WBP_DefaultStructureScreen')
    restoreNamed(frame,'SizeBox_0')
    restoreNamed(restoreNamed(frame,'RightPanel'),'SizeBox')
    local warehouse=restoreNamed(root,'WBP_StructureStorageBuilding')
    local transport=restoreNamed(warehouse,'WBP_Transportation')
    restoreNamed(transport,'ListResourceConnections');restoreNamed(transport,'InStorages')
    restoreNamed(warehouse,'ListStorage');restoreNamed(warehouse,'ListEmptyStorage')
    local controls=restoreNamed(root,'WBP_StorageControls')
    restoreNamed(restoreNamed(controls,'Panel'),'SizeBox')
    restoreNamed(controls,'PanelSize');restoreNamed(controls,'ListControls')
  end
  local function expand(root,types,slots,revision,resourceCount)
    local warehouse=assert(named(root,'WBP_StructureStorageBuilding'),'Warehouse section unavailable')
    if warehouse:GetIsTradePost() then return end
    local frame=assert(named(root,'WBP_DefaultStructureScreen'),'Warehouse frame unavailable')
    local side=assert(named(frame,'RightPanel'),'Warehouse side panel unavailable')
    local width=math.max(740,math.min(1340,viewportWidth(root)*.72))
    panelWidth(side,width)
    -- Some templates add a second width constraint outside the shared side panel.
    local outer=named(frame,'SizeBox_0')
    if valid(outer) and field(outer,'bOverride_WidthOverride')==true then size(outer,'Width',width) end
    local inner=width-80
    local transport=assert(named(warehouse,'WBP_Transportation'),'Transport section unavailable')
    local connections=assert(named(transport,'ListResourceConnections'),'Transport list unavailable')
    local key=id(root)
    local signature=revision..':'..types..':'..slots..':'..resourceCount
    if refreshKeys[key]~=signature then
      -- Capacity writes do not emit the game's warehouse-change event. Rebuild
      -- the original data models, including the engine-created '+' item. Its
      -- native predicate compares allocated slots with StorageData.MaxSlotsCount.
      -- Repeat after assigning/removing a resource, not on every layout poll.
      transport:InitializeInStorages()
      warehouse:FillEmptyStorageItemsList()
      warehouse:FillStorageItemsList()
      refreshKeys[key]=signature
    end
    local available,widthSource=listWidth(connections,inner)
    -- Size for actual goods plus the single native '+' button. Reserving nine
    -- empty resource cards made a mostly empty warehouse needlessly tall.
    local resources=connections:GetNumItems()
    -- Generated/released entries call the game's SetTransportationWidgetsSize:
    -- width = 660 / clamp(item count, 1, 3), height = 270 or 540.
    -- Preserve these cell dimensions instead of triggering competing relayouts.
    -- Never shrink below the original two-row height when there are >3 items.
    local entryWidth=660/math.max(1,math.min(resources,3))
    local columns=math.max(1,math.floor(available/entryWidth))
    local rows=math.max(resources>3 and 2 or 1,math.ceil(resources/columns))
    tile(connections,entryWidth,270,1)
    size(named(transport,'InStorages'),'Height',rows*270)
    local storage=assert(named(warehouse,'ListStorage'),'Stock list unavailable')
    local empty=assert(named(warehouse,'ListEmptyStorage'),'Empty stock list unavailable')
    local storageWidth=listWidth(storage,inner)
    local emptyWidth=listWidth(empty,inner)
    local stockWidth=math.min(storageWidth,emptyWidth)
    local stockColumns=math.max(1,math.floor(stockWidth/112))
    tile(storage,math.floor(stockWidth/stockColumns),128,.82)
    tile(empty,math.floor(stockWidth/stockColumns),128,.82)
    local controls=named(root,'WBP_StorageControls')
    if valid(controls) then
      local controlPanel=named(controls,'Panel')
      if valid(controlPanel) then panelWidth(controlPanel,width) end
      local box=named(controls,'PanelSize');if valid(box) then size(box,'Width',width) end
      -- Controls retain their original row height and buttons, gaining width only.
      local list=named(controls,'ListControls')
      if valid(list) then
        local b=remember(list);if not b.tile then b.tile={width=list:GetEntryWidth(),height=list:GetEntryHeight()} end
        list:SetEntryWidth(inner)
      end
    end
    -- Keep only scalar baselines. No strong UObject references survive this call.
    return {resourceItems=resources,resourceColumns=columns,resourceRows=rows,
      requestedWidth=width,availableWidth=available,widthSource=widthSource,
      entryWidth=entryWidth,stockItems=storage:GetNumItems()}
  end
  function M.tick(self,config,native)
    local result={checked=0,errors=0,active=0}
    local ok,err=pcall(function()
      local roots=api.all('WBP_Storage_C') or {}
      for _,root in ipairs(roots) do
        if valid(root) and not root:GetFullName():find('Default__',1,true) then
          local success,why=pcall(function()
            local count=tonumber(native.WarehouseSelectedResources) or 0
            local section=named(root,'WBP_StructureStorageBuilding')
            local list=valid(section) and named(section,'ListStorage')
            local allocated=valid(list) and list:GetNumItems() or 0
            local active=native.WarehouseSelected=='1' and (config.WarehouseEnabled or count>3 or allocated>15)
            if active then
              local metrics=expand(root,math.max(config.WarehouseEnabled and config.WarehouseTypes or 3,count),
                tonumber(native.WarehouseSelectedSlots) or 15,config.Revision,count)
              if metrics then for k,v in pairs(metrics) do result[k]=v end end
              result.active=result.active+1
            else
              local key=id(root);local needsRefresh=refreshKeys[key]~=nil
              restoreLayout(root);refreshKeys[key]=nil
              if needsRefresh and native.WarehouseSelected=='1' and valid(section) then
                local transport=named(section,'WBP_Transportation')
                if valid(transport) then transport:InitializeInStorages() end
                section:FillEmptyStorageItemsList();section:FillStorageItemsList()
              end
            end
            result.checked=result.checked+1
          end)
          if not success then result.errors=result.errors+1;result.error=tostring(why) end
        end
      end
    end)
    if not ok then result.errors=result.errors+1;result.error=tostring(err) end
    return result
  end
  return setmetatable({},{__index=M})
end
return M
