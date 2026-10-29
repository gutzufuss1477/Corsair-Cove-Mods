-- Cove QoL Trainer 1.2.5. Native QoL hooks, Lua asset limits.
-- Restart after upgrading. Duplicate loads must not multiply values twice.
if _G.CoveQoLTrainerActive then
  print('[CoveQoL] Already loaded. Restart the game to upgrade the backend.')
  return
end
local src=debug.getinfo(1,'S').source
local dir=src:sub(1,1)=='@' and src:sub(2):match('^(.*[/\\])') or ''
local dataDir=(os.getenv('LOCALAPPDATA') or '')..'\\CorsairCoveQoL\\'
local settingsPath,statusPath=dataDir..'settings.ini',dataDir..'status.ini'
local VERSION='1.2.5'
local cfg,loadedSettings,lastResult
local nativeRefresh,nativeError,nativeStatus
local warehouseUI,warehouseUiError,warehouseUiTouched
local warehouseUiResult={checked=0,errors=0,active=0}
local workerMovementAddress=0
local housingTooltipClassAddress=0
local warehouseAssetAddress,warehouseBaseSlots=0,15
local warehouseAssetPath='/Game/Structures/DataAssets/BuildingDataAssets/Building_Logistics_Storage.Building_Logistics_Storage'
local housingTooltipClassPath='/Game/UI/LimUI/Structures/Needs/WBP_NeedOverviewEntryTooltip.WBP_NeedOverviewEntryTooltip_C'
local attackRefreshToken=1
local baseline={}
local pending=false
local lastConfigError=nil
local battleKeys={'BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}
local defaults={WarehouseEnabled=false,WarehouseTypes=9,BridgesEnabled=false,BridgesSteps=30,TransportEnabled=false,TransportSteps=20,RoutesEnabled=false,
  BattleHullEnabled=false,BattleCrewEnabled=false,BattleSuppliesEnabled=false,
  ShipsEnabled=false,ShipsSteps=20,
  ConstructionEnabled=false,ConstructionSteps=20,CampRadiusEnabled=false,CampRadiusSteps=500,CampHousingEnabled=false,CampHousingSteps=100,CampOverlapEnabled=false,
  NearestCoastEnabled=false,KeepRevealedEnabled=false,Revision='legacy'}
local function log(msg)
  local text=os.date('%Y-%m-%d %H:%M:%S')..' [CoveQoL] '..tostring(msg)
  print(text)
  pcall(function()
    local f=assert(io.open(dir..'CoveQoLTrainer.log','a')); f:write(text,'\n'); f:close()
  end)
end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function parse(raw)
  local out,legacy,seen={},{},{}
  for k,v in pairs(defaults) do out[k]=v end
  raw=raw:gsub('^\239\187\191','')
  for row in (raw..'\n'):gmatch('(.-)\n') do
    row=row:match('^%s*(.-)%s*$')
    if row~='' and not row:match('^[;#%[]') then
      local k,v=row:match('^([A-Za-z]+)%s*=%s*(.-)%s*$')
      if not k then return nil,'Invalid settings line' end
      seen[k]=true
      if k=='AttackRadiusEnabled' or k=='AttackRadiusSteps' or k=='BattleProtectionEnabled' then legacy[k]=v end
      if defaults[k]~=nil then
        if type(defaults[k])=='boolean' then
          v=v:lower()
          if v~='0' and v~='1' and v~='true' and v~='false' then return nil,'Invalid '..k end
          out[k]=(v=='1' or v=='true')
        elseif type(defaults[k])=='number' then
          local n=tonumber(v)
          if not finite(n) or n%1~=0 then return nil,'Invalid '..k end
          if k=='WarehouseTypes' then
            if n~=6 and n~=9 then return nil,'Invalid WarehouseTypes' end
            out[k]=n
          else out[k]=clamp(n,10,k=='CampRadiusSteps' and 5000 or (k=='CampHousingSteps' and 1000 or (k=='ConstructionSteps' and 200 or 100))) end
        else
          if not v:match('^[%w_-]+$') or #v>80 then return nil,'Invalid revision' end
          out[k]=v
        end
      end
    end
  end
  -- v0.6 profiles keep their enabled state; the numeric radius is retired.
  -- An explicit new switch always wins over legacy values.
  if not seen.NearestCoastEnabled and (legacy.AttackRadiusEnabled or legacy.AttackRadiusSteps) then
    local enabled=(legacy.AttackRadiusEnabled or ''):lower()
    local steps=tonumber(legacy.AttackRadiusSteps)
    if (enabled~='0' and enabled~='1' and enabled~='true' and enabled~='false')
      or not finite(steps) or steps%1~=0 then return nil,'Invalid legacy attack configuration' end
    out.NearestCoastEnabled=enabled=='1' or enabled=='true'
  end
  for _,key in ipairs(battleKeys) do
    if not seen[key] and legacy.BattleProtectionEnabled then
      local value=legacy.BattleProtectionEnabled:lower()
      if value~='0' and value~='1' and value~='true' and value~='false' then return nil,'Invalid legacy battle switch' end
      out[key]=value=='1' or value=='true'
    end
  end
  return out
end
local function readSettings()
  local f=io.open(settingsPath,'rb')
  if not f then return nil,'Settings unavailable' end
  local raw=f:read(4097); f:close()
  if not raw or #raw==0 or #raw>4096 then return nil,'Settings empty or too large' end
  -- Older profiles remain valid and start with construction disabled. Reject a
  -- partially written new pair so an active factor cannot silently reset.
  local content='\n'..raw:gsub('^\239\187\191','')
  local hasRadius=content:match('\n%s*CampRadiusEnabled%s*=') or content:match('\n%s*CampRadiusSteps%s*=')
  if hasRadius and (not content:match('\n%s*CampRadiusEnabled%s*=') or not content:match('\n%s*CampRadiusSteps%s*=')) then return nil,'Incomplete camp radius settings' end
  for _,pair in ipairs({{'WarehouseEnabled','WarehouseTypes'},{'BridgesEnabled','BridgesSteps'}}) do
    local a=content:match('\n%s*'..pair[1]..'%s*=')
    local b=content:match('\n%s*'..pair[2]..'%s*=')
    if (a and not b) or (b and not a) then return nil,'Incomplete '..pair[1]..' settings' end
  end
  local hasHousing=content:match('\n%s*CampHousingEnabled%s*=') or content:match('\n%s*CampHousingSteps%s*=')
  if hasHousing and (not content:match('\n%s*CampHousingEnabled%s*=') or not content:match('\n%s*CampHousingSteps%s*=')) then return nil,'Incomplete camp housing settings' end
  local hasConstruction=content:match('\n%s*ConstructionEnabled%s*=') or content:match('\n%s*ConstructionSteps%s*=')
  local hasBattle=false
  for _,key in ipairs(battleKeys) do if content:match('\n%s*'..key..'%s*=') then hasBattle=true end end
  for k in pairs(defaults) do
    local optional=k:find('Warehouse',1,true)==1 or k:find('Bridges',1,true)==1 or k=='Revision' or k=='CampOverlapEnabled' or (k:find('Construction',1,true)==1 and not hasConstruction)
      or (k:find('CampHousing',1,true)==1 and not hasHousing) or (k:find('CampRadius',1,true)==1 and not hasRadius) or k=='NearestCoastEnabled' or k=='KeepRevealedEnabled' or k=='RoutesEnabled'
      or (k:find('Battle',1,true)==1 and not hasBattle)
    if not optional and not content:match('\n%s*'..k..'%s*=') then
      return nil,'Missing '..k
    end
  end
  return raw
end
local function valid(o)
  local ok,v=pcall(function() return o:IsValid() end)
  return ok and v==true
end
local function number(o,k)
  local v=tonumber(o[k]); assert(finite(v),'Unreadable field '..k); return v
end
local function original(o)
  local name=o:GetFullName()
  local address=tostring(o:GetAddress())
  local entry=baseline[name]
  if not entry or entry.address~=address then
    entry={address=address,fields={}}; baseline[name]=entry
  end
  return entry.fields
end
local function count() return {checked=0,changed=0,errors=0,capped=0} end
local function attempt(c,action)
  local ok,err=pcall(action)
  if not ok then
    c.errors=c.errors+1
    if c.errors<=3 then log('FIELD_ERROR '..tostring(err):sub(1,240)) end
  end
end
local function update(c,base,key,old,target,write,read)
  assert(finite(old) and finite(target),'Non-finite value '..key)
  if base[key]==nil then base[key]=old end
  if math.abs(old-target)>0.00001 then
    write(target)
    local got=read()
    assert(finite(got) and math.abs(got-target)<=math.max(0.0001,math.abs(target)*0.00001),
      'Readback mismatch '..key)
    c.changed=c.changed+1
  end
  c.checked=c.checked+1
end
local function multiplier(enabled,steps,denom) return enabled and steps/denom or 1 end
local function transportFactor()
  return workerMovementAddress>0 and multiplier(cfg.TransportEnabled,cfg.TransportSteps,10) or 1
end
local function findHousingTooltipClass()
  local ok,address=pcall(function()
    local class=StaticFindObject(housingTooltipClassPath)
    if not valid(class) or class:GetFullName()~='WidgetBlueprintGeneratedClass '..housingTooltipClassPath then return 0 end
    local n=tonumber(class:GetAddress())
    if not finite(n) or n<=0 or n%8~=0 or n>140737488355327 then return 0 end
    return n
  end)
  return ok and address or 0
end
local function findWarehouseAsset()
  local ok,address=pcall(function()
    local o=StaticFindObject(warehouseAssetPath)
    if not valid(o) or o:GetFullName()~='CBuildingDataAsset '..warehouseAssetPath then return 0 end
    local n=tonumber(o:GetAddress())
    if not finite(n) or n<=0 or n%8~=0 or n>140737488355327 then return 0 end
    return n
  end)
  return ok and address or 0
end
local function refreshNative(writeRequest)
  -- Retry this exact identity when the UI loads/unloads it, without loading any
  -- widget or scanning live objects. Unchanged settings must not delay discovery.
  local wa=findWarehouseAsset()
  if wa~=warehouseAssetAddress then warehouseAssetAddress=wa;writeRequest=true end
  local tooltipClass=findHousingTooltipClass()
  if tooltipClass~=housingTooltipClassAddress then
    housingTooltipClassAddress=tooltipClass;writeRequest=true
  end
  local ok,err=pcall(function()
    if not nativeRefresh then error(nativeError or 'Native library unavailable') end
    if writeRequest then
      local f=assert(io.open(dataDir..'native-request.ini','w'))
      f:write('Revision='..cfg.Revision..'\nTransportFactor='..
        transportFactor()..'\nWorkerMovementAddress='..string.format('%.0f',workerMovementAddress)..
        '\nHousingTooltipClassAddress='..string.format('%.0f',housingTooltipClassAddress)..
        '\nWarehouseTypes='..(cfg.WarehouseEnabled and cfg.WarehouseTypes or 3)..
        '\nWarehouseBaseSlots='..warehouseBaseSlots..'\nWarehouseAssetAddress='..string.format('%.0f',warehouseAssetAddress)..
        '\nBattleHullEnabled='..(cfg.BattleHullEnabled and '1' or '0')..
        '\nBattleCrewEnabled='..(cfg.BattleCrewEnabled and '1' or '0')..
        '\nBattleSuppliesEnabled='..(cfg.BattleSuppliesEnabled and '1' or '0')..'\nConstructionFactor='..
        multiplier(cfg.ConstructionEnabled,cfg.ConstructionSteps,10)..'\nShipFactor='..
        multiplier(cfg.ShipsEnabled,cfg.ShipsSteps,10)..'\nCampOverlapEnabled='..
        (cfg.CampOverlapEnabled and '1' or '0')..'\nNearestCoastEnabled='..(cfg.NearestCoastEnabled and '1' or '0')..
        '\nCampHousingSteps='..(cfg.CampHousingEnabled and cfg.CampHousingSteps or 10)..'\nCampRadiusFactor='..multiplier(cfg.CampRadiusEnabled,cfg.CampRadiusSteps,10)..'\nAttackRefreshToken='..attackRefreshToken..'\nKeepRevealedEnabled='..(cfg.KeepRevealedEnabled and '1' or '0')..'\n'); f:close()
    end
    nativeRefresh()
    local f=assert(io.open(dataDir..'native-status.ini','rb'))
    local raw=f:read(4096);f:close()
    local s={}
    for k,v in raw:gmatch('([A-Za-z]+)=([^\r\n]*)') do s[k]=v end
    nativeStatus=s
    assert(s.Version==VERSION and s.Ready=='1',s.Error or 'Native hooks not ready')
    assert(s.Error=='','Native bridge: '..tostring(s.Error))
    assert(s.Revision==cfg.Revision,'Native revision not current')
    assert(tonumber(s.TransportFactor)==transportFactor(), 'Native speed mismatch')
    assert(tonumber(s.WorkerMovementAddress)==workerMovementAddress, 'Native worker identity mismatch')
    for _,key in ipairs(battleKeys) do
      assert(s[key]==(cfg[key] and '1' or '0'), 'Native battle protection mismatch: '..key)
    end
    assert(tonumber(s.ShipFactor)==multiplier(cfg.ShipsEnabled,cfg.ShipsSteps,10), 'Native ship speed mismatch')
    assert(tonumber(s.ConstructionFactor)==multiplier(cfg.ConstructionEnabled,cfg.ConstructionSteps,10), 'Native construction mismatch')
    assert(tonumber(s.CampRadiusFactor)==multiplier(cfg.CampRadiusEnabled,cfg.CampRadiusSteps,10), 'Native camp radius mismatch')
    assert(tonumber(s.CampHousingSteps)==(cfg.CampHousingEnabled and cfg.CampHousingSteps or 10), 'Native camp housing mismatch')
    assert(tonumber(s.HousingTooltipClassAddress)==housingTooltipClassAddress, 'Native housing tooltip identity mismatch')
    assert(tonumber(s.WarehouseTypes)==(cfg.WarehouseEnabled and cfg.WarehouseTypes or 3), 'Native warehouse count mismatch')
    assert(tonumber(s.WarehouseAssetAddress)==warehouseAssetAddress, 'Native warehouse identity mismatch')
    assert(tonumber(s.WarehouseBaseSlots)==warehouseBaseSlots, 'Native warehouse baseline mismatch')
    assert(s.KeepRevealedEnabled==(cfg.KeepRevealedEnabled and '1' or '0'), 'Native fog switch mismatch')
    assert(s.CampOverlapEnabled==(cfg.CampOverlapEnabled and '1' or '0'), 'Native camp overlap mismatch')
    assert(s.NearestCoastEnabled==(cfg.NearestCoastEnabled and '1' or '0'), 'Native attack switch mismatch')
    assert(tonumber(s.AttackRefreshToken)==attackRefreshToken, 'Native attack refresh token mismatch')
  end)
  if ok then nativeError=nil else nativeError=tostring(err):gsub('[\r\n]',' '):sub(1,200) end
  return ok
end
local function instances(name,c)
  local ok,list=pcall(FindAllOf,name)
  if not ok then c.errors=c.errors+1; log('DISCOVERY_ERROR '..name); return {} end
  return type(list)=='table' and list or {}
end
-- ConnectionConfigs is a fixed array indexed by connection type. The Lua
-- struct proxy exposed only its first entry. Native getters now cover every
-- selected entry and per-agent override; never also multiply the asset.
local function findWorker(r)
  local found=0
  for _,o in ipairs(instances('CMovementType',r.Transport)) do
    attempt(r.Transport,function()
      if not valid(o) or not o:GetFullName():match('/MT_Worker%.MT_Worker$') then return end
      local address=tonumber(o:GetAddress())
      assert(finite(address) and address>0 and address%1==0 and address<=140737488355327,'Invalid worker identity')
      assert(found==0 or found==address,'Ambiguous worker identity')
      found=address
    end)
  end
  return r.Transport.errors==0 and found or 0
end
-- Raise actual route quotas; no item, recipe, storage-capacity or cargo writes.
local routeFields={'MaxFetchersPerResource','MaxFetchersPerBuilding',
  'MaxFetchersPerProductionBuilding','MaxFetchersPerStorageBuilding','MaxFetchersPerHarborBuilding'}
local function patchRoutes(o,r)
  if not valid(o) then return end
  local b=original(o)
  for _,key in ipairs(routeFields) do
    attempt(r.Routes,function()
      local old=number(o,key)
      assert(old>=0 and old%1==0,'Invalid route limit '..key)
      local initial=b[key] or old
      local target=cfg.RoutesEnabled and math.max(initial,999) or initial
      update(r.Routes,b,key,old,target,function(v)o[key]=v end,function()return number(o,key)end)
    end)
  end
end
local function patchBridges(o,r)
  if not valid(o) or o:GetFullName():find('Default__',1,true) then return end
  local b=original(o)
  attempt(r.Bridges,function()
    local old=number(o,'MaxLength')
    local initial=b.MaxLength or old
    -- Leave non-positive special/uninitialized setups unchanged.
    local target=initial>0 and initial*multiplier(cfg.BridgesEnabled,cfg.BridgesSteps,10) or initial
    update(r.Bridges,b,'MaxLength',old,target,function(v)o.MaxLength=v end,function()return number(o,'MaxLength')end)
  end)
end
local function discoverWarehouseBaseline(r)
  for _,o in ipairs(instances('CStructureWarehouseDataConfig',r.Warehouse)) do
    attempt(r.Warehouse,function()
      if not valid(o) or not o:GetFullName():find(warehouseAssetPath,1,true) then return end
      local base=number(o,'MaxStorageSlots')
      assert(base%1==0 and base>0 and base<=4096,'Invalid warehouse base capacity')
      warehouseBaseSlots=base;r.Warehouse.checked=r.Warehouse.checked+1
    end)
  end
end
local function patchCampRadius(o,r)
  if not valid(o) then return end
  local b=original(o)
  attempt(r.CampRadius,function()
    local old=number(o,'PirateCampRadius')
    local initial=b.PirateCampRadius or old
    -- Match the native audited 3000-unit base, including class defaults that
    -- have not yet been populated from the building asset. Never scale a CDO's
    -- placeholder zero or a previously enlarged asset into a different radius.
    local target=cfg.CampRadiusEnabled and 3000*cfg.CampRadiusSteps/10 or initial
    update(r.CampRadius,b,'PirateCampRadius',old,target,function(v)o.PirateCampRadius=v end,function()return number(o,'PirateCampRadius')end)
  end)
end
local function patchCampConnections(o,r)
  if not valid(o) then return end
  local b=original(o)
  attempt(r.CampRadius,function()
    local key='MaxPirateCampConnectionLength'
    local old=number(o,key)
    local initial=b[key] or old
    local target=cfg.CampRadiusEnabled and math.max(initial,3000*cfg.CampRadiusSteps/10) or initial
    update(r.CampRadius,b,key,old,target,function(v)o[key]=v end,function()return number(o,key)end)
  end)
end
local function radiusState(c)
  if nativeError or (nativeStatus and nativeStatus.CampRadiusError=='1') or c.errors>0 then return 'Error' end
  if c.checked==0 or not nativeStatus or nativeStatus.CampRadiusPending~='0' then return 'Waiting' end
  return 'Applied'
end
local function state(c)
  if c.errors>0 then return 'Error' end
  if c.checked==0 then return 'Waiting' end
  return 'Applied'
end
local function attackState()
  if nativeError or (nativeStatus and nativeStatus.AttackRefreshError=='1') then return 'Error' end
  if not nativeStatus or nativeStatus.AttackPending~='0' then return 'Waiting' end
  return 'Applied'
end
local function warehouseState(c)
  if nativeError or c.errors>0 or warehouseUiError or warehouseUiResult.errors>0 or
    (nativeStatus and nativeStatus.WarehouseError=='1') then return 'Error' end
  if not cfg.WarehouseEnabled and warehouseAssetAddress==0 then return 'Applied' end
  if not nativeStatus or nativeStatus.WarehousePending~='0' then return 'Waiting' end
  return 'Applied'
end
local function writeStatus()
  local r=lastResult
  local ok,err=pcall(function()
    local overall=r and r.status or 'Waiting'
    if r and (attackState()~='Applied' or radiusState(r.CampRadius)~='Applied' or warehouseState(r.Warehouse)~='Applied' or nativeError) then overall='Partial' end
    local rows={'Version='..VERSION,'Heartbeat='..os.time(),'At='..os.date('%H:%M:%S'),
      'Revision='..(r and r.revision or ''),'Status='..(lastConfigError and 'ConfigError' or overall),
      'ConfigError='..(lastConfigError or ''),'Reason='..(r and r.reason or 'startup'),
      'RoutesEnabled='..(cfg.RoutesEnabled and '1' or '0'),
      'WarehouseUiActive='..warehouseUiResult.active,'WarehouseUiErrors='..warehouseUiResult.errors,
      'WarehouseUiResourceItems='..tostring(warehouseUiResult.resourceItems or 0),
      'WarehouseUiResourceColumns='..tostring(warehouseUiResult.resourceColumns or 0),
      'WarehouseUiResourceRows='..tostring(warehouseUiResult.resourceRows or 0),
      'WarehouseUiRequestedWidth='..tostring(warehouseUiResult.requestedWidth or 0),
      'WarehouseUiAvailableWidth='..tostring(warehouseUiResult.availableWidth or 0),
      'WarehouseUiWidthSource='..tostring(warehouseUiResult.widthSource or ''),
      'WarehouseUiEntryWidth='..tostring(warehouseUiResult.entryWidth or 0),
      'WarehouseUiStockItems='..tostring(warehouseUiResult.stockItems or 0),
      'WarehouseUiError='..tostring(warehouseUiError or warehouseUiResult.error or ''):gsub('[\r\n]',' '):sub(1,200),
      'NativeError='..(nativeError or ''),'NativeReady='..(nativeError==nil and nativeStatus and '1' or '0')}
    for _,key in ipairs({'TransportCalls','VisualCalls','VisualTimeCalls','TransportPlanCalls','LocomotionDefaultCalls','LocomotionOverrideCalls','BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled','BattleStatChecks','BattleStatBlocks','BattleSupplyChecks','BattleSupplyBlocks','ShipCalls','ShipFactor','ConstructionCalls','ConstructionFactor',
      'WarehouseSelected','WarehouseSelectedResources','WarehouseSelectedSlots','WarehouseTypes','WarehouseAssetAddress','WarehouseBaseSlots','WarehouseCount','WarehouseChanges','WarehousePending','WarehouseError','CampHousingSteps','CampHousingReads','HousingTooltipClassAddress','HousingTooltipUpdates','HousingTooltipFallbacks','HousingTooltipCampBeds','CampRadiusFactor','CampRadiusPending','CampRadiusError','CampRadiusChanges','CampRadiusCamps','CampOverlapEnabled','CampOverlapChecks','CampOverlapBypasses','NearestCoastEnabled',
      'AttackPending','AttackRefreshError','AttackRefreshes','AttackPoints','AttackEligiblePoints',
      'NearestCoastChecks','NearestCoastSelected','KeepRevealedEnabled',
      'FogKeepChecks','FogKeepOverrides','FogTransitionChecks','FogCoversBlocked'}) do
      rows[#rows+1]='Native'..key..'='..(nativeStatus and nativeStatus[key] or '0')
    end
    for _,name in ipairs({'Transport','Routes','Ships','Construction','CampRadius','CampHousing','Warehouse','Bridges','CampOverlap','NearestCoast','KeepRevealed','BattleProtection'}) do
      local c=r and r[name] or count()
      rows[#rows+1]=name..'State='..(name=='Warehouse' and warehouseState(c) or name=='CampRadius' and radiusState(c) or (name=='NearestCoast' and attackState() or (nativeError and 'Error' or state(c))))
      rows[#rows+1]=name..'Fields='..c.checked
      rows[#rows+1]=name..'Changed='..c.changed
      rows[#rows+1]=name..'Errors='..c.errors
      rows[#rows+1]=name..'Capped='..c.capped
    end
    local f=assert(io.open(statusPath,'w')); f:write(table.concat(rows,'\n'),'\n'); f:close()
  end)
  if not ok then
    if not _G.CoveQoLStatusError then log('STATUS_WRITE_ERROR '..tostring(err)) end
    _G.CoveQoLStatusError=true
  else _G.CoveQoLStatusError=nil end
end
local function apply(reason)
  local r={Transport=count(),Routes=count(),BattleProtection=count(),Ships=count(),Construction=count(),CampRadius=count(),CampHousing=count(),Warehouse=count(),Bridges=count(),CampOverlap=count(),NearestCoast=count(),KeepRevealed=count(),reason=reason,revision=cfg.Revision}
  workerMovementAddress=findWorker(r)
  discoverWarehouseBaseline(r)
  local nativeOk=refreshNative(true)
  if nativeOk and workerMovementAddress>0 then r.Transport.checked=1 end
  -- Native factor readback is confirmation of configuration, not an in-game test.
  if nativeOk then r.Ships.checked=1;r.Construction.checked=1;r.CampHousing.checked=1;r.CampOverlap.checked=1;r.NearestCoast.checked=1;r.KeepRevealed.checked=1;r.BattleProtection.checked=1 end
  local groups={
    {'CEconomyGlobalsDataAsset','Routes',patchRoutes},
    {'CBridgeSetup','Bridges',patchBridges},
    {'CEconomyGlobalsDataAsset','CampRadius',patchCampConnections},
    {'CStructurePirateCampDataConfig','CampRadius',patchCampRadius}}
  for _,g in ipairs(groups) do
    if nativeOk then
      for _,o in ipairs(instances(g[1],r[g[2]])) do
        attempt(r[g[2]],function() g[3](o,r) end)
      end
    end
  end
  if not cfg.WarehouseEnabled then r.Warehouse.checked=math.max(1,r.Warehouse.checked) end
  if not cfg.BridgesEnabled then r.Bridges.checked=math.max(1,r.Bridges.checked) end
  r.status='Applied'
  for _,name in ipairs({'Transport','Routes','Ships','Construction','CampRadius','CampHousing','Warehouse','Bridges','CampOverlap','NearestCoast','KeepRevealed','BattleProtection'}) do
    if state(r[name])~='Applied' then r.status='Partial' end
  end
  if not nativeOk then r.status='Partial';log('NATIVE_ERROR '..tostring(nativeError)) end
  lastResult=r
  log(string.format('APPLY %s revision=%s status=%s verified=%d/%d/%d changed=%d/%d/%d errors=%d/%d/%d construction=x%s ready=%s',
    reason,r.revision,r.status,r.Transport.checked,r.Routes.checked,r.Ships.checked,
    r.Transport.changed,r.Routes.changed,r.Ships.changed,r.Transport.errors,r.Routes.errors,r.Ships.errors,
    multiplier(cfg.ConstructionEnabled,cfg.ConstructionSteps,10),tostring(nativeOk)))
  writeStatus()
end
local function check(reason,force)
  local data,err=readSettings()
  if data then
    local parsed
    parsed,err=parse(data)
    if parsed then
      lastConfigError=nil
      if force or data~=loadedSettings then
        cfg=parsed; loadedSettings=data; apply(reason)
      end
      return
    end
  end
  if err~=lastConfigError then log('CONFIG_ERROR '..tostring(err)) end
  lastConfigError=err
  if force then apply(reason) end
end
local function schedule(ms,reason)
  if pending then return end
  pending=true
  ExecuteInGameThreadWithDelay(ms,function()
    pending=false
    local ok,err=pcall(check,reason,true)
    if not ok then lastConfigError='Backend error'; log('APPLY_ERROR '..tostring(err)) end
  end)
end
local function poll()
  -- UE4SS coroutines share a Lua heap. A background timer that merely queues
  -- a game-thread closure still allocates/frees Lua values concurrently with UI
  -- traversal. Use the bundled runtime's game-thread timers for the whole
  -- callback, and reuse a single looping action instead of recursive timers.
  LoopInGameThreadWithDelay(2500,function()
    local ok,err=pcall(function()
      local ok,err=pcall(check,'settings-changed',false)
      if not ok then lastConfigError='Backend error'; log('POLL_ERROR '..tostring(err)) end
      refreshNative(nativeError~=nil)
      writeStatus()
    end)
    if not ok then lastConfigError='Backend error';log('POLL_ERROR '..tostring(err)) end
  end)
end
local function pollWarehouseUI()
  LoopInGameThreadWithDelay(500,function()
    local ok,err=pcall(function()
      if cfg.WarehouseEnabled or warehouseUiTouched or
        (nativeStatus and nativeStatus.WarehouseSelected=='1' and tonumber(nativeStatus.WarehouseSelectedResources or '0')>3) then
        warehouseUiTouched=true
        refreshNative(false)
        if warehouseUI then warehouseUiResult=warehouseUI:tick(cfg,nativeStatus or {}) end
        writeStatus()
      end
    end)
    if not ok then
      warehouseUiResult={checked=0,active=0,errors=1,error=tostring(err)}
      log('WAREHOUSE_UI_ERROR '..tostring(err))
    end
  end)
end
do
  local ok,module=pcall(dofile,dir..'WarehouseUI.lua')
  if ok then warehouseUI=module.new({all=FindAllOf,find=StaticFindObject})
  else warehouseUiError=tostring(module);log('WAREHOUSE_UI_LOAD_ERROR '..warehouseUiError) end
end
cfg=parse('')
_G.CoveQoLTrainerActive=true
log('START QoL Trainer '..VERSION)
do
  local ok,err=pcall(function()
    local initialize=assert(package.loadlib(dir..'CoveQoLNative.dll','CoveQoL_Initialize'))
    nativeRefresh=assert(package.loadlib(dir..'CoveQoLNative.dll','CoveQoL_Refresh'))
    initialize()
  end)
  if not ok then nativeError=tostring(err);log('NATIVE_LOAD_ERROR '..nativeError) end
end
schedule(1800,'startup')
local function hook(name,fn)
  local ok,err=pcall(fn)
  if not ok then log('HOOK_UNAVAILABLE '..name..' '..tostring(err):sub(1,160)) end
end
local function invalidateAttackPoints() attackRefreshToken=attackRefreshToken%2147483647+1 end
hook('gamestate',function() RegisterInitGameStatePostHook(function() invalidateAttackPoints();schedule(500,'gamestate') end) end)
hook('map',function() RegisterLoadMapPostHook(function()
  invalidateAttackPoints()
  schedule(1200,'map-loaded')
  ExecuteInGameThreadWithDelay(6500,function() schedule(1,'map-settled') end)
end) end)
hook('F8',function() RegisterKeyBind(0x77,function() invalidateAttackPoints();schedule(1,'F8') end) end)
-- Coalesce notifications; wait until newly constructed assets have initialized.
for _,class in ipairs({'CMovementType','CEconomyGlobalsDataAsset','CStructurePirateCampDataConfig','CBridgeSetup','CStructureWarehouseDataConfig'}) do
  hook(class,function() NotifyOnNewObject('/Script/Cove.'..class,function() schedule(800,'assets-loaded') end) end)
end
poll()
pollWarehouseUI()
