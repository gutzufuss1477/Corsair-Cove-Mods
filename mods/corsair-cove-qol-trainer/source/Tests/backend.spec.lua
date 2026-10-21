local passed=0
local function eq(actual,expected,context)
  if type(actual)=='number' and type(expected)=='number' and math.abs(actual-expected)<0.0001 then return end
  assert(actual==expected,(context or '')..' expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error('FAIL '..name..': '..tostring(err)) end
  passed=passed+1; print('PASS '..name)
end
local function object(name,addr,fields)
  fields.GetFullName=function()return name end
  fields.GetAddress=function()return addr end
  fields.IsValid=function()return true end
  return fields
end
local function config(changes)
  local c={TransportEnabled='1',TransportSteps='20',CarryEnabled='1',CarrySteps='3',
    ShipsEnabled='1',ShipsSteps='20',RoutesEnabled='1',BattleHullEnabled='0',BattleCrewEnabled='0',BattleSuppliesEnabled='0',Revision='one'}
  for k,v in pairs(changes or {}) do c[k]=tostring(v) end
  local rows={}
  for k,v in pairs(c) do rows[#rows+1]=k..'='..v end
  return table.concat(rows,'\n')
end
local function fixture(raw,withoutNative)
  local h={now=0,tasks={},files={},hooks={},notifies={},scans=0,logs={}}
  local settings='TEST\\CorsairCoveQoL\\settings.ini'
  local status='TEST\\CorsairCoveQoL\\status.ini'
  h.files[settings]=raw==false and nil or (raw or config())
  if raw==false then h.files[settings]=nil end
  local speeds={[1]=0.6,[2]=1.5,[3]=0}
  h.speeds=speeds
  local map={ForEach=function(_,fn)
    for k in pairs(speeds) do
      fn({get=function()return k end},{get=function()return speeds[k] end,set=function(_,v)speeds[k]=v end})
    end
  end}
  h.economy=object('Economy',1,{AgentBaseSpeed=300,WarehouseFetchAmount=10,MaxPirateCampConnectionLength=10000,
    HarborBuildingsFetcherBatchSizeFactor=20,NetworkComponentSpeedSettings=map,
    MaxFetchersPerResource=3,MaxFetchersPerBuilding=5,MaxFetchersPerProductionBuilding=5,
    MaxFetchersPerStorageBuilding=5,MaxFetchersPerHarborBuilding=3,MaxResourcesPerStorageBuilding=5})
  h.worker=object('Movement /MT_Worker.MT_Worker',2,{ConnectionConfigs={MaxSpeed=1000}})
  h.item=object('Item',3,{BatchSize=1,BatchSizeMaximum=24})
  h.ship=object('Ship',4,{ShipStats={Speed=24}})
  h.camp=object('Camp config',5,{PirateCampRadius=3000})
  h.objects={CStructurePirateCampDataConfig={h.camp},CEconomyGlobalsDataAsset={h.economy},CMovementType={h.worker},
    CItemDataAsset={h.item},CShipDataAsset={h.ship}}
  local env=setmetatable({},{__index=_G}); env._G=env
  env.os={getenv=function()return 'TEST' end,time=function()return 1000000000+math.floor(h.now/1000) end,
    date=function()return '12:00:00' end}
  env.print=function(s)h.logs[#h.logs+1]=s end
  env.io={open=function(path,mode)
    if mode=='rb' and not h.files[path] then return nil end
    if mode=='w' then h.files[path]='' end
    return {
      read=function(_,n)return h.files[path]:sub(1,n) end,
      write=function(self,...)h.files[path]=(h.files[path] or '')..table.concat({...});return self end,
      close=function()end}
  end}
  -- Legacy async-to-game dispatch must never return: even a queue-only async
  -- callback uses the same Lua heap concurrently with the game-thread callback.
  env.ExecuteWithDelay=function()error('Unsafe background Lua timer')end
  env.ExecuteInGameThread=function()error('Unexpected immediate cross-thread dispatch')end
  env.ExecuteInGameThreadWithDelay=function(ms,fn)
    h.tasks[#h.tasks+1]={at=h.now+ms,fn=fn};return #h.tasks
  end
  env.LoopInGameThreadWithDelay=function(ms,fn)
    h.tasks[#h.tasks+1]={at=h.now+ms,fn=fn,interval=ms};return #h.tasks
  end
  env.FindAllOf=function(class)
    assert(h.inGameCallback,'UObject access must stay in game-thread callbacks')
    if h.throwUi and class=='WBP_Storage_C' then error('UI unavailable') end
    h.scans=h.scans+1;return h.objects[class]
  end
  env.package={loadlib=function(_,entry)
    if withoutNative then return nil,'Native DLL missing' end
    return function()
      if entry=='CoveQoL_Initialize' then return end
      local d={}
      for k,v in (h.files['TEST\\CorsairCoveQoL\\native-request.ini'] or ''):gmatch('([A-Za-z]+)=([^\n]*)')do d[k]=v end
      h.native=d
      h.files['TEST\\CorsairCoveQoL\\native-status.ini']='Version=1.2.4\nReady=1\nError=\nRevision='..
        (h.nativeStale and 'stale' or d.Revision or '')..'\nTransportFactor='..(d.TransportFactor or '1')..
        '\nWorkerMovementAddress='..(h.workerMismatch and '0' or d.WorkerMovementAddress or '0')..
        '\nLocomotionDefaultCalls=21\nLocomotionOverrideCalls=4'..
        '\nConstructionFactor='..
        (h.constructionMismatch and '1' or d.ConstructionFactor or '1')..
        '\nShipFactor='..(h.shipMismatch and '1' or d.ShipFactor or '1')..'\nShipCalls=12\nBattleStatChecks=8\nBattleStatBlocks=2\nBattleSupplyChecks=3\nBattleSupplyBlocks=1'..
        '\nCampHousingSteps='..(h.housingMismatch and '10' or d.CampHousingSteps or '10')..'\nCampHousingReads=4'..
        '\nHousingTooltipClassAddress='..(h.tooltipMismatch and '0' or d.HousingTooltipClassAddress or '0')..
        '\nWarehousePending='..(h.warehousePending and '1' or '0')..'\nWarehouseError='..(h.warehouseError and '1' or '0')..'\nWarehouseSelected=0\nWarehouseCount=1\nHousingTooltipUpdates=5\nHousingTooltipFallbacks=0\nHousingTooltipCampBeds=250'..
        '\nCampRadiusFactor='..(d.CampRadiusFactor or '1')..'\nCampRadiusPending=0\nCampRadiusError=0'..
        '\nCampOverlapEnabled='..(h.overlapMismatch and '0' or d.CampOverlapEnabled or '0')..
        '\nKeepRevealedEnabled='..(h.fogMismatch and '0' or d.KeepRevealedEnabled or '0')..
        '\nFogKeepChecks=9\nFogKeepOverrides=3\nFogTransitionChecks=4\nFogCoversBlocked=1'..
        '\nCampOverlapChecks=7\nCampOverlapBypasses=2'..
        '\nNearestCoastEnabled='..(h.attackMismatch and '0' or d.NearestCoastEnabled or '0')..
        '\nAttackRefreshToken='..(d.AttackRefreshToken or '1')..
        '\nAttackPending='..(h.attackPending and '1' or '0')..'\nAttackRefreshError='..(h.attackRefreshError and '1' or '0')..
        '\nAttackRefreshes=1\nAttackPoints=20\nAttackEligiblePoints=3\nNearestCoastChecks=20\nNearestCoastSelected=20'..
        '\nTransportCalls=0\nVisualCalls=13\nVisualTimeCalls=6\nTransportPlanCalls=17\nConstructionCalls=0\n'
      for _,key in ipairs({'WarehouseTypes','WarehouseBaseSlots','WarehouseAssetAddress','BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}) do
        local value=d[key] or '0'
        if h.battleMismatch==key then value=value=='1' and '0' or '1' end
        local path='TEST\\CorsairCoveQoL\\native-status.ini'
        h.files[path]=h.files[path]..key..'='..value..'\n'
      end
    end
  end}
  env.dofile=function(path)assert(path:match('WarehouseUI.lua$'));return assert(load(warehouseUiSource,'@WarehouseUI.lua','t',env))() end
  env.RegisterInitGameStatePostHook=function(fn)h.hooks.game=fn end
  env.RegisterLoadMapPostHook=function(fn)h.hooks.map=fn end
  env.RegisterKeyBind=function(_,fn)h.hooks.key=fn end
  env.NotifyOnNewObject=function(class,fn)h.notifies[class]=fn end
  env.StaticFindObject=function(path)
    if path=='/Game/Structures/DataAssets/BuildingDataAssets/Building_Logistics_Storage.Building_Logistics_Storage' then return h.warehouseAsset end
    eq(path,'/Game/UI/LimUI/Structures/Needs/WBP_NeedOverviewEntryTooltip.WBP_NeedOverviewEntryTooltip_C','only exact tooltip lookup')
    if h.tooltipThrow then error('widget unloading') end
    return h.tooltipClass
  end
  function h:load()assert(load(trainerSource,'@main.lua','t',env))()end
  function h:set(changes)h.files[settings]=config(changes)end
  function h:raw(value)h.files[settings]=value end
  function h:status()
    local out={}
    for k,v in (h.files[status] or ''):gmatch('([A-Za-z]+)=([^\n]*)')do out[k]=v end
    return out
  end
  function h:advance(ms)
    local untilAt=h.now+ms
    for _=1,10000 do
      table.sort(h.tasks,function(a,b)return a.at<b.at end)
      if not h.tasks[1] or h.tasks[1].at>untilAt then h.now=untilAt;return end
      local next=table.remove(h.tasks,1);h.now=next.at
      assert(not h.inGameCallback,'game-thread actions must not overlap')
      h.inGameCallback=true;next.fn();h.inGameCallback=false
      if next.interval then next.at=h.now+next.interval;h.tasks[#h.tasks+1]=next end
    end
    error('Scheduler runaway')
  end
  h:load();return h
end
test('native settings and route limits apply without cargo changes',function()
  local h=fixture();h:advance(2000)
  eq(h.economy.AgentBaseSpeed,300);eq(h.worker.ConnectionConfigs.MaxSpeed,1000)
  eq(h.speeds[1],0.6);eq(h.speeds[3],0)
  eq(h.economy.WarehouseFetchAmount,10);eq(h.item.BatchSize,1);eq(h.item.BatchSizeMaximum,24)
  eq(tonumber(h.native.TransportFactor),2);eq(h.native.CarryFactor,nil)
  eq(tonumber(h.native.ShipFactor),2);eq(h:status().NativeShipCalls,'12');eq(h:status().NativeBattleStatBlocks,'2')
  eq(h.ship.ShipStats.Speed,24);eq(h:status().Status,'Applied');eq(h:status().Revision,'one')
end)
test('routes restore all five original limits and never touch storage slots',function()
  local h=fixture();h:advance(2000)
  for _,k in ipairs({'MaxFetchersPerResource','MaxFetchersPerBuilding','MaxFetchersPerProductionBuilding','MaxFetchersPerStorageBuilding','MaxFetchersPerHarborBuilding'}) do eq(h.economy[k],999) end
  eq(h.economy.MaxResourcesPerStorageBuilding,5);eq(h:status().RoutesEnabled,'1')
  h:set({RoutesEnabled=0,Revision='routes-off'});h:advance(3000)
  eq(h.economy.MaxFetchersPerResource,3);eq(h.economy.MaxFetchersPerStorageBuilding,5);eq(h.economy.MaxFetchersPerHarborBuilding,3)
  eq(h:status().RoutesFields,'5');eq(h.native.CarryFactor,nil);eq(h:status().RoutesEnabled,'0')
end)
test('pre-existing higher route limits are preserved',function()
  local h=fixture();h.economy.MaxFetchersPerResource=1500;h:advance(2000)
  eq(h.economy.MaxFetchersPerResource,1500)
  h:set({RoutesEnabled=0});h:advance(3000);eq(h.economy.MaxFetchersPerResource,1500)
end)
test('legacy capacity settings are ignored; new options default off',function()
  local raw=config({CarryEnabled='yes',CarrySteps='infinity'})
  raw=raw:gsub('RoutesEnabled=1',''):gsub('BattleHullEnabled=0',''):gsub('BattleCrewEnabled=0',''):gsub('BattleSuppliesEnabled=0','')
  local h=fixture(raw);h:advance(2000)
  eq(h.economy.MaxFetchersPerResource,3);eq(h.item.BatchSizeMaximum,24)
  eq(h.native.BattleHullEnabled,'0');eq(h.native.CarryFactor,nil);eq(h:status().Status,'Applied')
  eq(h.notifies['/Script/Cove.CItemDataAsset'],nil)
end)
test('battle switch readback, independence and reset',function()
  local h=fixture(config({BattleHullEnabled=1,BattleCrewEnabled=0,BattleSuppliesEnabled=1}));h:advance(2000)
  eq(h.native.BattleHullEnabled,'1');eq(h:status().BattleProtectionState,'Applied')
  eq(h:status().NativeBattleSupplyBlocks,'1');eq(tonumber(h.native.TransportFactor),2)
  h.battleMismatch='BattleHullEnabled';h.hooks.key();h:advance(2)
  eq(h:status().BattleProtectionState,'Error');eq(h:status().NativeReady,'0')
  h.battleMismatch=false;h:set({BattleHullEnabled=0,BattleCrewEnabled=0,BattleSuppliesEnabled=0});h:advance(3000)
  eq(h.native.BattleHullEnabled,'0');eq(h:status().BattleProtectionState,'Applied')
end)
test('all eight protection combinations have independent confirmed values',function()
  local h=fixture();h:advance(2000)
  for hull=0,1 do for crew=0,1 do for supplies=0,1 do
    h:set({BattleHullEnabled=hull,BattleCrewEnabled=crew,BattleSuppliesEnabled=supplies});h:advance(3000)
    eq(h.native.BattleHullEnabled,tostring(hull));eq(h.native.BattleCrewEnabled,tostring(crew));eq(h.native.BattleSuppliesEnabled,tostring(supplies))
    eq(h:status().NativeBattleHullEnabled,tostring(hull));eq(h:status().NativeBattleCrewEnabled,tostring(crew));eq(h:status().NativeBattleSuppliesEnabled,tostring(supplies))
    eq(h:status().BattleProtectionState,'Applied');eq(tonumber(h.native.TransportFactor),2)
  end end end
end)
test('combined legacy protection migrates but explicit individual switches win',function()
  local raw=config({BattleProtectionEnabled=1}):gsub('BattleHullEnabled=0',''):gsub('BattleCrewEnabled=0',''):gsub('BattleSuppliesEnabled=0','')
  local h=fixture(raw);h:advance(2000)
  for _,key in ipairs({'BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}) do eq(h.native[key],'1') end
  eq(h.native.BattleProtectionEnabled,nil)
  h:set({BattleProtectionEnabled='invalid-retired-value',BattleHullEnabled=0,BattleCrewEnabled=1,BattleSuppliesEnabled=0});h:advance(3000)
  eq(h.native.BattleHullEnabled,'0');eq(h.native.BattleCrewEnabled,'1');eq(h.native.BattleSuppliesEnabled,'0');eq(h:status().Status,'Applied')
  h:raw(raw:gsub('BattleProtectionEnabled=1','BattleProtectionEnabled=0'));h:advance(3000)
  for _,key in ipairs({'BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}) do eq(h.native[key],'0') end
end)
test('invalid or partial individual protection configuration retains every previous value',function()
  local initial={BattleHullEnabled=1,BattleCrewEnabled=0,BattleSuppliesEnabled=1}
  local h=fixture(config(initial));h:advance(2000)
  for _,key in ipairs({'BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}) do
    for _,bad in ipairs({'2','yes',''}) do
      local raw=config({BattleHullEnabled=0,BattleCrewEnabled=1,BattleSuppliesEnabled=0})
      raw=raw:gsub(key..'=[01]',bad=='' and '' or key..'='..bad)
      h:raw(raw);h:advance(3000)
      eq(h:status().Status,'ConfigError')
      eq(h.native.BattleHullEnabled,'1');eq(h.native.BattleCrewEnabled,'0');eq(h.native.BattleSuppliesEnabled,'1')
    end
  end
end)
test('each individual native protection acknowledgement is required',function()
  local h=fixture(config({BattleHullEnabled=1,BattleCrewEnabled=0,BattleSuppliesEnabled=1}));h:advance(2000)
  for _,key in ipairs({'BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled'}) do
    h.battleMismatch=key;h.hooks.key();h:advance(2);eq(h:status().BattleProtectionState,'Error')
    h.battleMismatch=nil;h.hooks.key();h:advance(2);eq(h:status().BattleProtectionState,'Applied')
  end
end)
test('failed route writes are never reported as applied',function()
  local h=fixture();h.economy.MaxFetchersPerResource=nil
  setmetatable(h.economy,{__index=function(_,k)if k=='MaxFetchersPerResource' then return 3 end end,__newindex=function()end})
  h:advance(2000);eq(h:status().RoutesState,'Error');eq(h:status().Status,'Partial')
end)

test('F8 and lifecycle reapply without compounding',function()
  local h=fixture();h:advance(2000)
  for _=1,4 do h.hooks.key();h:advance(2) end
  h.hooks.map();h:advance(7000)
  eq(h.economy.AgentBaseSpeed,300);eq(h.item.BatchSize,1);eq(h.ship.ShipStats.Speed,24)
  eq(h:status().TransportChanged,'0')
end)

test('carrier-only changes preserve cargo and ships and publish real carrier diagnostics',function()
  local h=fixture(config({TransportSteps=10,CarrySteps=1,ShipsSteps=100}));h:advance(2000)
  h:set({TransportSteps=50,CarrySteps=1,ShipsSteps=100,Revision='carrier5'});h:advance(3000)
  eq(tonumber(h.native.TransportFactor),5);eq(h.native.CarryFactor,nil);eq(tonumber(h.native.ShipFactor),10)
  eq(h.economy.AgentBaseSpeed,300);eq(h.item.BatchSizeMaximum,24)
  eq(h:status().NativeVisualCalls,'13');eq(h:status().NativeVisualTimeCalls,'6');eq(h:status().NativeTransportPlanCalls,'17')
  h:set({TransportEnabled=0,CarrySteps=1,ShipsSteps=100,Revision='carrierOff'});h:advance(3000)
  eq(tonumber(h.native.TransportFactor),1);eq(h.native.CarryFactor,nil);eq(tonumber(h.native.ShipFactor),10)
  eq(h.worker.ConnectionConfigs.MaxSpeed,1000)
end)
test('module switches are independent and disabled restores exact values',function()
  local h=fixture();h:advance(2000)
  h:set({TransportEnabled=0,ShipsEnabled=0,CarrySteps=5,Revision='two'});h:advance(3000)
  eq(h.economy.AgentBaseSpeed,300);eq(h.speeds[1],0.6);eq(h.worker.ConnectionConfigs.MaxSpeed,1000)
  eq(h.ship.ShipStats.Speed,24);eq(h.item.BatchSizeMaximum,24)
  eq(tonumber(h.native.TransportFactor),1);eq(h.native.CarryFactor,nil)
  h:set({TransportEnabled=0,CarryEnabled=0,ShipsEnabled=0});h:advance(3000)
  eq(h.item.BatchSize,1);eq(h.item.BatchSizeMaximum,24);eq(h.economy.WarehouseFetchAmount,10)
end)
test('ship speed uses native factor without modifying or capping ship stats',function()
  local h=fixture(config({ShipsSteps=100}));h.ship.ShipStats.Speed=35;h:advance(2000)
  eq(h.ship.ShipStats.Speed,35);eq(h:status().ShipsCapped,'0');eq(tonumber(h.native.ShipFactor),10)
  h:set({ShipsEnabled=0});h:advance(3000);eq(h.ship.ShipStats.Speed,35);eq(tonumber(h.native.ShipFactor),1)
  local a=fixture(config({TransportEnabled=0,CarryEnabled=0,ShipsEnabled=0}))
  a.ship.ShipStats.Speed=120;a.economy.AgentBaseSpeed=25000;a:advance(2000)
  eq(a.ship.ShipStats.Speed,120);eq(a.economy.AgentBaseSpeed,25000)
end)
test('idle heartbeats do not search game objects',function()
  local h=fixture();h:advance(2000);local scans=h.scans;local before=h:status().Heartbeat
  h:advance(60000);eq(h.scans,scans);assert(h:status().Heartbeat~=before)
end)
test('duplicate script load does not add hooks/timers or multiply',function()
  local h=fixture();h:advance(2000);local tasks=#h.tasks;h:load();eq(#h.tasks,tasks)
  h:advance(4000);eq(h.ship.ShipStats.Speed,24)
end)
test('incomplete/deleted/oversized settings retain last valid configuration',function()
  local h=fixture();h:advance(2000)
  for _,raw in ipairs({'TransportEnabled=0','',string.rep('a',4097)})do
    h:raw(raw);h:advance(3000);eq(h.worker.ConnectionConfigs.MaxSpeed,1000);eq(h:status().Status,'ConfigError')
  end
  h:raw(nil);h:advance(3000);eq(h.item.BatchSizeMaximum,24);eq(h:status().Status,'ConfigError')
  h:set({Revision='fixed'});h:advance(3000);eq(h:status().Status,'Applied');eq(h:status().Revision,'fixed')
end)
test('invalid numeric, boolean, and revision inputs never alter values',function()
  local h=fixture();h:advance(2000)
  for _,bad in ipairs({{TransportSteps='nan'},{ConstructionSteps='inf',ConstructionEnabled=1},{ShipsSteps='1e999'},
    {TransportSteps='25.5'},{RoutesEnabled='yes'},{Revision='a=b'}})do
    h:set(bad);h:advance(3000);eq(h.ship.ShipStats.Speed,24);eq(h:status().Status,'ConfigError')
  end
end)
test('BOM, CRLF, uppercase booleans and comments work',function()
  local h=fixture('\239\187\191; CarrySteps=20\r\n'..config({TransportEnabled='TRUE',CarryEnabled='FALSE'}):gsub('\n','\r\n'))
  h:advance(2000);eq(h.worker.ConnectionConfigs.MaxSpeed,1000);eq(h.item.BatchSize,1);eq(h:status().Status,'Applied')
end)
test('no settings file leaves the game unchanged',function()
  local h=fixture(false);h:advance(2000);eq(h.economy.AgentBaseSpeed,300);eq(h.item.BatchSize,1)
  eq(h.ship.ShipStats.Speed,24);eq(h:status().Status,'ConfigError')
end)
test('empty world reports waiting instead of success',function()
  local h=fixture();h.objects={};h:advance(2000)
  eq(h:status().Status,'Partial');eq(h:status().TransportState,'Waiting');eq(h:status().ShipsState,'Applied')
end)
test('new asset notifications coalesce and capture the new object baseline',function()
  local h=fixture();h:advance(2000);local scans=h.scans
  h.objects.CEconomyGlobalsDataAsset={object('Economy',99,{MaxFetchersPerResource=7,MaxFetchersPerBuilding=8,
    MaxFetchersPerProductionBuilding=9,MaxFetchersPerStorageBuilding=10,MaxFetchersPerHarborBuilding=11})}
  for _=1,20 do h.notifies['/Script/Cove.CEconomyGlobalsDataAsset']() end
  h:advance(1000);eq(h.scans-scans,6);eq(h.objects.CEconomyGlobalsDataAsset[1].MaxFetchersPerResource,999)
  h:set({RoutesEnabled=0});h:advance(3000);eq(h.objects.CEconomyGlobalsDataAsset[1].MaxFetchersPerResource,7)
end)
test('worker asset needs no field access or writes; all movement limits are native',function()
  local h=fixture()
  h.worker.ConnectionConfigs=setmetatable({},{__index=function()error('Unexpected movement read')end,__newindex=function()error('Unexpected movement write')end})
  h:advance(2000);eq(h:status().TransportState,'Applied');eq(h:status().Status,'Applied')
  eq(h.native.WorkerMovementAddress,'2');eq(h:status().NativeLocomotionDefaultCalls,'21');eq(h:status().NativeLocomotionOverrideCalls,'4')
  eq(h:status().ShipsState,'Applied');eq(h.item.BatchSizeMaximum,24)
end)

test('missing worker holds transport at x1 until the exact asset appears',function()
  local h=fixture();h.objects.CMovementType={object('Movement /MT_WorkerFake.MT_WorkerFake',99,{})}
  h:advance(2000);eq(h:status().TransportState,'Waiting');eq(tonumber(h.native.TransportFactor),1);eq(h.native.WorkerMovementAddress,'0')
  h.objects.CMovementType={h.worker};h.notifies['/Script/Cove.CMovementType']();h:advance(1000)
  eq(h:status().TransportState,'Applied');eq(tonumber(h.native.TransportFactor),2);eq(h.native.WorkerMovementAddress,'2')
end)

test('worker asset replacement updates identity and ambiguity disables acceleration',function()
  local h=fixture();h:advance(2000)
  h.objects.CMovementType={object('Movement /Game/Agents/MT_Worker.MT_Worker',123456789012,{})}
  h.hooks.map();h:advance(7000);eq(h.native.WorkerMovementAddress,'123456789012')
  table.insert(h.objects.CMovementType,h.worker);h.hooks.key();h:advance(2)
  eq(h:status().TransportState,'Error');eq(h.native.WorkerMovementAddress,'0');eq(tonumber(h.native.TransportFactor),1)
end)

test('worker identity readback mismatch cannot report synchronization',function()
  local h=fixture();h.workerMismatch=true;h:advance(2000)
  eq(h:status().TransportState,'Error');eq(h:status().NativeReady,'0')
  h.workerMismatch=false;h.hooks.key();h:advance(2);eq(h:status().TransportState,'Applied')
end)
test('invalid object cannot stop the remaining objects',function()
  local h=fixture()
  table.insert(h.objects.CEconomyGlobalsDataAsset,1,object('Broken',44,{}))
  h:advance(2000);eq(h.item.BatchSizeMaximum,24);eq(h:status().RoutesState,'Error')
end)
test('bounds are enforced without interpreting comment values',function()
  local h=fixture('; TransportSteps=100\n'..config({TransportSteps=-1,CarrySteps=999,ShipsSteps=15}))
  h:advance(2000);eq(h.economy.AgentBaseSpeed,300);eq(h.item.BatchSizeMaximum,24);eq(tonumber(h.native.ShipFactor),1.5)
end)
test('missing native library blocks all native modules including ships',function()
  local h=fixture(nil,true);h:advance(2000)
  eq(h.worker.ConnectionConfigs.MaxSpeed,1000);eq(h.item.BatchSizeMaximum,24)
  eq(h.ship.ShipStats.Speed,24);eq(h:status().NativeReady,'0')
  eq(h:status().TransportState,'Error');eq(h:status().RoutesState,'Error');eq(h:status().Status,'Partial')
  eq(h:status().ShipsState,'Error')
end)

test('ship readback mismatch cannot report success and recovers on reapply',function()
  local h=fixture();h.shipMismatch=true;h:advance(2000)
  eq(h:status().ShipsState,'Error');eq(h:status().NativeReady,'0');eq(h.ship.ShipStats.Speed,24)
  h.shipMismatch=false;h.hooks.key();h:advance(2)
  eq(h:status().ShipsState,'Applied');eq(tonumber(h:status().NativeShipFactor),2)
end)

test('ship assets are never scanned or rewritten by native speed control',function()
  local h=fixture();h.objects.CShipDataAsset=setmetatable({},{__pairs=function()error('Ship scan forbidden')end})
  h.ship.ShipStats=setmetatable({},{__index=function()error('Stat access forbidden')end,__newindex=function()error('Stat write forbidden')end})
  h:advance(2000);eq(h:status().ShipsState,'Applied');eq(h.notifies['/Script/Cove.CShipDataAsset'],nil)
  h:set({ShipsSteps=55});h:advance(3000);eq(tonumber(h.native.ShipFactor),5.5)
end)
test('stale native revision cannot masquerade as successful transport',function()
  local h=fixture();h.nativeStale=true;h:advance(2000)
  eq(h:status().NativeReady,'0');eq(h:status().TransportState,'Error')
  eq(h.worker.ConnectionConfigs.MaxSpeed,1000)
  h.nativeStale=false;h.hooks.key();h:advance(2)
  eq(h:status().NativeReady,'1');eq(h.worker.ConnectionConfigs.MaxSpeed,1000)
end)
test('legacy settings leave construction disabled and remain valid',function()
  local h=fixture();h:advance(2000)
  eq(tonumber(h.native.ConstructionFactor),1);eq(h:status().ConstructionState,'Applied')
  eq(h:status().NativeConstructionFactor,'1');eq(h:status().NativeConstructionCalls,'0')
  eq(h:status().Status,'Applied')
end)
test('construction factor applies and resets independently without object scans',function()
  local h=fixture(config({ConstructionEnabled=1,ConstructionSteps=55}));h:advance(2000)
  eq(tonumber(h.native.ConstructionFactor),5.5);eq(tonumber(h.native.TransportFactor),2)
  eq(h.native.CarryFactor,nil);eq(h.ship.ShipStats.Speed,24)
  for _=1,3 do h.hooks.key();h:advance(2) end
  eq(tonumber(h.native.ConstructionFactor),5.5)
  local scans=h.scans;h:advance(20000);eq(h.scans,scans)
  h:set({ConstructionEnabled=0,ConstructionSteps=55});h:advance(3000)
  eq(tonumber(h.native.ConstructionFactor),1);eq(tonumber(h.native.TransportFactor),2)
  eq(h.native.CarryFactor,nil);eq(h.ship.ShipStats.Speed,24)
end)
test('construction bounds and invalid partial settings preserve last valid factor',function()
  local h=fixture(config({ConstructionEnabled=1,ConstructionSteps=999}));h:advance(2000)
  eq(tonumber(h.native.ConstructionFactor),20)
  for _,bad in ipairs({{ConstructionEnabled=1},{ConstructionSteps=50},
    {ConstructionEnabled='yes',ConstructionSteps=50},{ConstructionEnabled=1,ConstructionSteps='nan'},
    {ConstructionEnabled=1,ConstructionSteps='50.5'}}) do
    h:set(bad);h:advance(3000);eq(tonumber(h.native.ConstructionFactor),20)
    eq(h:status().Status,'ConfigError')
  end
  h:set({ConstructionEnabled=1,ConstructionSteps=-1});h:advance(3000)
  eq(tonumber(h.native.ConstructionFactor),1);eq(h:status().Status,'Applied')
end)
test('construction requires native factor confirmation',function()
  local h=fixture(config({ConstructionEnabled=1,ConstructionSteps=50}))
  h.constructionMismatch=true;h:advance(2000)
  eq(h:status().NativeReady,'0');eq(h:status().ConstructionState,'Error')
  eq(h:status().Status,'Partial');eq(h.ship.ShipStats.Speed,24)
  h.constructionMismatch=false;h.hooks.key();h:advance(2)
  eq(h:status().ConstructionState,'Applied');eq(h:status().NativeConstructionFactor,'5.0')
  local missing=fixture(config({ConstructionEnabled=1,ConstructionSteps=50}),true)
  missing:advance(2000);eq(missing:status().ConstructionState,'Error')
end)
test('overlap is opt-in for legacy profiles and toggles independently',function()
  local h=fixture();h:advance(2000)
  eq(h.native.CampOverlapEnabled,'0');eq(h:status().CampOverlapState,'Applied')
  h:set({CampOverlapEnabled=1,ConstructionEnabled=1,ConstructionSteps=55});h:advance(3000)
  eq(h.native.CampOverlapEnabled,'1');eq(h:status().NativeCampOverlapEnabled,'1')
  eq(h:status().NativeCampOverlapChecks,'7');eq(h:status().NativeCampOverlapBypasses,'2')
  h:set({CampOverlapEnabled=0,ConstructionEnabled=1,ConstructionSteps=55});h:advance(3000)
  eq(h.native.CampOverlapEnabled,'0');eq(tonumber(h.native.ConstructionFactor),5.5)
  eq(tonumber(h.native.TransportFactor),2);eq(h.native.CarryFactor,nil)
end)
test('invalid overlap value preserves last valid settings',function()
  local h=fixture(config({CampOverlapEnabled=1}));h:advance(2000)
  for _,bad in ipairs({'yes','2','1junk',''}) do
    h:set({CampOverlapEnabled=bad,TransportSteps=10});h:advance(3000)
    eq(h:status().Status,'ConfigError');eq(h.native.CampOverlapEnabled,'1')
    eq(tonumber(h.native.TransportFactor),2)
  end
end)
test('overlap requires native readback and recovers after mismatch',function()
  local h=fixture(config({CampOverlapEnabled=1}));h.overlapMismatch=true;h:advance(2000)
  eq(h:status().CampOverlapState,'Error');eq(h:status().Status,'Partial')
  h.overlapMismatch=false;h.hooks.key();h:advance(2)
  eq(h:status().CampOverlapState,'Applied');eq(h:status().NativeCampOverlapEnabled,'1')
  local missing=fixture(config({CampOverlapEnabled=1}),true);missing:advance(2000)
  eq(missing:status().CampOverlapState,'Error')
end)
test('older profiles leave nearest coast independent and disabled',function()
  local h=fixture();h:advance(2000)
  eq(h.native.NearestCoastEnabled,'0')
  eq(h:status().NearestCoastState,'Applied')
  h:set({NearestCoastEnabled=1});h:advance(3000)
  eq(h.native.NearestCoastEnabled,'1')
  eq(tonumber(h.native.TransportFactor),2);eq(h.native.CarryFactor,nil)
  eq(h:status().NativeAttackEligiblePoints,'3')
end)
test('attack state waits for world refresh and acknowledges without rescanning assets',function()
  local h=fixture(config({NearestCoastEnabled=1}));h.attackPending=true;h:advance(2000)
  eq(h:status().NearestCoastState,'Waiting');eq(h:status().Status,'Partial')
  local scans=h.scans;h.attackPending=false;h:advance(3000)
  eq(h:status().NearestCoastState,'Applied');eq(h:status().Status,'Applied');eq(h.scans,scans)
  h.attackRefreshError=true;h:advance(3000);eq(h:status().NearestCoastState,'Error');eq(h:status().Status,'Partial')
  h.attackRefreshError=false;h:advance(3000);eq(h:status().Status,'Applied')
end)
test('map and manual reload invalidate attack caches but idle polls do not',function()
  local h=fixture();h:advance(2000);local token=tonumber(h.native.AttackRefreshToken)
  h:advance(10000);eq(tonumber(h.native.AttackRefreshToken),token)
  h.hooks.map();h:advance(2000);eq(tonumber(h.native.AttackRefreshToken),token+1)
  h.hooks.game();h:advance(600);eq(tonumber(h.native.AttackRefreshToken),token+2)
  h.hooks.key();h:advance(2);eq(tonumber(h.native.AttackRefreshToken),token+3)
end)
test('nearest coast switch rejects malformed values atomically',function()
  local h=fixture(config({NearestCoastEnabled=1}));h:advance(2000)
  for _,bad in ipairs({'yes','2','1junk',''}) do
    h:set({NearestCoastEnabled=bad,TransportSteps=10});h:advance(3000)
    eq(h:status().Status,'ConfigError');eq(h.native.NearestCoastEnabled,'1');eq(tonumber(h.native.TransportFactor),2)
  end
  h:set({NearestCoastEnabled=0});h:advance(3000);eq(h.native.NearestCoastEnabled,'0')
end)

test('v0.6 radius profiles migrate enabled state and retire numeric radius',function()
  local h=fixture(config({AttackRadiusEnabled=1,AttackRadiusSteps=85}));h:advance(2000)
  eq(h.native.NearestCoastEnabled,'1');eq(h.native.AttackRadius,nil)
  h:set({AttackRadiusEnabled=0,AttackRadiusSteps=300});h:advance(3000);eq(h.native.NearestCoastEnabled,'0')
  h:set({NearestCoastEnabled=0,AttackRadiusEnabled=1,AttackRadiusSteps='bad'});h:advance(3000)
  eq(h:status().Status,'Applied');eq(h.native.NearestCoastEnabled,'0')
  h:set({AttackRadiusEnabled=1});h:advance(3000);eq(h:status().Status,'ConfigError')
  eq(h.native.NearestCoastEnabled,'0')
end)

test('attack native mismatch and missing DLL cannot report success',function()
  local h=fixture(config({NearestCoastEnabled=1}));h.attackMismatch=true;h:advance(2000)
  eq(h:status().NearestCoastState,'Error');eq(h:status().NativeReady,'0')
  local missing=fixture(nil,true);missing:advance(2000);eq(missing:status().NearestCoastState,'Error')
end)
test('fog option defaults off for existing profiles and is independent',function()
  local h=fixture();h:advance(2000)
  eq(h.native.KeepRevealedEnabled,'0');eq(h:status().KeepRevealedState,'Applied')
  h:set({KeepRevealedEnabled=1,NearestCoastEnabled=1,CampOverlapEnabled=1});h:advance(3000)
  eq(h.native.KeepRevealedEnabled,'1');eq(h:status().NativeFogCoversBlocked,'1')
  eq(h.native.NearestCoastEnabled,'1');eq(h.native.CampOverlapEnabled,'1');eq(tonumber(h.native.TransportFactor),2)
  h:set({KeepRevealedEnabled=0,NearestCoastEnabled=1,CampOverlapEnabled=1});h:advance(3000)
  eq(h.native.KeepRevealedEnabled,'0');eq(h.native.NearestCoastEnabled,'1');eq(h.native.CampOverlapEnabled,'1')
end)
test('invalid fog option keeps last valid settings for all modules',function()
  local h=fixture(config({KeepRevealedEnabled=1}));h:advance(2000)
  for _,bad in ipairs({'yes','2','1junk',''}) do
    h:set({KeepRevealedEnabled=bad,TransportSteps=10});h:advance(3000)
    eq(h:status().Status,'ConfigError');eq(h.native.KeepRevealedEnabled,'1');eq(tonumber(h.native.TransportFactor),2)
  end
end)
test('fog option survives map reload and idle polling performs no extra object scans',function()
  local h=fixture(config({KeepRevealedEnabled=1}));h:advance(2000)
  local scans=h.scans;h:advance(10000);eq(h.scans,scans);eq(h.native.KeepRevealedEnabled,'1')
  h.hooks.map();h:advance(2000);eq(h.native.KeepRevealedEnabled,'1');eq(h:status().KeepRevealedState,'Applied')
end)
test('fog native readback is required and mismatch recovers',function()
  local h=fixture(config({KeepRevealedEnabled=1}));h.fogMismatch=true;h:advance(2000)
  eq(h:status().KeepRevealedState,'Error');eq(h:status().Status,'Partial')
  h.fogMismatch=false;h.hooks.key();h:advance(2);eq(h:status().KeepRevealedState,'Applied')
  local missing=fixture(config({KeepRevealedEnabled=1}),true);missing:advance(2000)
  eq(missing:status().KeepRevealedState,'Error')
end)


test('range multiplier updates placement and connections without compounding',function()
  local h=fixture(config({CampRadiusEnabled=1,CampRadiusSteps=500}));h:advance(2000)
  eq(h.camp.PirateCampRadius,150000);eq(h.economy.MaxPirateCampConnectionLength,150000);eq(tonumber(h.native.CampRadiusFactor),50)
  h.hooks.key();h:advance(2000);eq(h.camp.PirateCampRadius,150000)
  h:set({CampRadiusEnabled=0,CampRadiusSteps=500,Revision='off'});h:advance(3000)
  eq(h.camp.PirateCampRadius,3000);eq(h.economy.MaxPirateCampConnectionLength,10000)
end)

test('class-default radius uses the audited base and restores its placeholder',function()
  local h=fixture(config({CampRadiusEnabled=1,CampRadiusSteps=500}))
  h.camp.PirateCampRadius=0;h:advance(2000);eq(h.camp.PirateCampRadius,150000)
  h:set({CampRadiusEnabled=0,CampRadiusSteps=500,Revision='restore'});h:advance(3000);eq(h.camp.PirateCampRadius,0)
end)
test('old profiles leave housing off and unchanged through map reload',function()
  local h=fixture(config());h:advance(2000)
  eq(h.native.CampHousingSteps,'10');eq(h:status().CampHousingState,'Applied')
  h.hooks.map();h:advance(2000);eq(h.native.CampHousingSteps,'10')
end)

test('housing changes independently and restores x1 when disabled',function()
  local h=fixture(config({CampHousingEnabled=1,CampHousingSteps=100}));h:advance(2000)
  eq(h.native.CampHousingSteps,'100');eq(h:status().CampHousingState,'Applied')
  eq(h:status().NativeCampHousingReads,'4');eq(h.native.CampRadiusFactor,'1')
  h:set({CampHousingEnabled=1,CampHousingSteps=205,Revision='housing-new'});h:advance(3000)
  eq(h.native.CampHousingSteps,'205');eq(tonumber(h.native.TransportFactor),2)
  h.hooks.map();h:advance(2000);eq(h.native.CampHousingSteps,'205')
  h:set({CampHousingEnabled=0,CampHousingSteps=205,Revision='housing-off'});h:advance(3000)
  eq(h.native.CampHousingSteps,'10');eq(h:status().CampHousingState,'Applied')
end)

test('housing bounds clamp while malformed or partial pairs keep last valid settings',function()
  local h=fixture(config({CampHousingEnabled=1,CampHousingSteps=9999}));h:advance(2000)
  eq(h.native.CampHousingSteps,'1000')
  for _,bad in ipairs({'CampHousingEnabled=1','CampHousingSteps=50',
      'CampHousingEnabled=yes\nCampHousingSteps=100','CampHousingEnabled=1\nCampHousingSteps=NaN',
      'CampHousingEnabled=1\nCampHousingSteps=100.5'}) do
    h:raw(config()..'\n'..bad);h:advance(3000)
    eq(h:status().Status,'ConfigError');eq(h.native.CampHousingSteps,'1000')
  end
  h:set({CampHousingEnabled=1,CampHousingSteps=0});h:advance(3000)
  eq(h.native.CampHousingSteps,'10')
end)

test('housing requires matching native readback and recovers',function()
  local h=fixture(config({CampHousingEnabled=1,CampHousingSteps=100}));h.housingMismatch=true;h:advance(2000)
  eq(h:status().CampHousingState,'Error');eq(h:status().Status,'Partial')
  h.housingMismatch=false;h.hooks.key();h:advance(2)
  eq(h:status().CampHousingState,'Applied')
  local missing=fixture(config({CampHousingEnabled=1,CampHousingSteps=100}),true);missing:advance(2000)
  eq(missing:status().CampHousingState,'Error')
end)
test('housing tooltip class appears and disappears without settings edits',function()
  local h=fixture();h:advance(2000)
  eq(h.native.HousingTooltipClassAddress,'0')
  local path='/Game/UI/LimUI/Structures/Needs/WBP_NeedOverviewEntryTooltip.WBP_NeedOverviewEntryTooltip_C'
  h.tooltipClass=object('WidgetBlueprintGeneratedClass '..path,800,{})
  h:advance(3000);eq(h.native.HousingTooltipClassAddress,'800')
  eq(h:status().NativeHousingTooltipUpdates,'5')
  h.tooltipClass=object('WidgetBlueprintGeneratedClass '..path,1600,{})
  h:advance(3000);eq(h.native.HousingTooltipClassAddress,'1600')
  h.tooltipClass=nil;h:advance(3000);eq(h.native.HousingTooltipClassAddress,'0')
end)
test('housing tooltip discovery fails closed for wrong class or address',function()
  local h=fixture();h:advance(2000)
  local name='WidgetBlueprintGeneratedClass /Game/UI/LimUI/Structures/Needs/WBP_NeedOverviewEntryTooltip.WBP_NeedOverviewEntryTooltip_C'
  for _,n in ipairs({-8,801,math.huge,140737488355328}) do
    h.tooltipClass=object(name,n,{});h:advance(3000);eq(h.native.HousingTooltipClassAddress,'0')
  end
  h.tooltipClass=object('WrongWidget',800,{});h:advance(3000);eq(h.native.HousingTooltipClassAddress,'0')
  h.tooltipThrow=true;h:advance(3000);eq(h.native.HousingTooltipClassAddress,'0');eq(h:status().NativeReady,'1')
end)
test('housing tooltip acknowledgement mismatch is visible and recovers',function()
  local h=fixture();h:advance(2000)
  h.tooltipClass=object('WidgetBlueprintGeneratedClass /Game/UI/LimUI/Structures/Needs/WBP_NeedOverviewEntryTooltip.WBP_NeedOverviewEntryTooltip_C',800,{})
  h.tooltipMismatch=true;h:advance(3000);assert(h:status().NativeError:find('tooltip identity mismatch',1,true))
  h.tooltipMismatch=false;h:advance(3000);eq(h:status().NativeError,'')
end)
test('bridge length scales once, preserves unrelated fields and restores',function()
  local h=fixture(config({BridgesEnabled=1,BridgesSteps=30}))
  local bridge=object('Bridge setup',1000,{MaxLength=12000,MinSteepnessAngle=-20,MaxSteepnessAngle=30,FootprintRadius=70})
  h.objects.CBridgeSetup={bridge};h:advance(2000)
  eq(bridge.MaxLength,36000);eq(h:status().BridgesState,'Applied')
  h.hooks.key();h:advance(2);eq(bridge.MaxLength,36000)
  h:set({BridgesEnabled=1,BridgesSteps=65});h:advance(3000);eq(bridge.MaxLength,78000)
  eq(bridge.MinSteepnessAngle,-20);eq(bridge.MaxSteepnessAngle,30);eq(bridge.FootprintRadius,70)
  h:set({BridgesEnabled=0,BridgesSteps=65});h:advance(3000);eq(bridge.MaxLength,12000)
end)
test('new bridge setups capture their own baseline and report failed writes',function()
  local h=fixture(config({BridgesEnabled=1,BridgesSteps=100}));h:advance(2000);eq(h:status().BridgesState,'Waiting')
  local b=object('Bridge setup',1008,{MaxLength=9000});local special=object('Special bridge',1016,{MaxLength=0})
  local default=object('CBridgeSetup /Script/Cove.Default__CBridgeSetup',1024,{MaxLength=1000})
  h.objects.CBridgeSetup={b,special,default};h.notifies['/Script/Cove.CBridgeSetup']();h:advance(1000)
  eq(b.MaxLength,90000);eq(special.MaxLength,0);eq(default.MaxLength,1000)
  b.MaxLength=nil;setmetatable(b,{__index=function(_,key)if key=='MaxLength' then return 1000 end end,__newindex=function()end})
  h.hooks.key();h:advance(2);eq(h:status().BridgesState,'Error')
end)
test('warehouse exact identity and baseline flow through native configuration',function()
  local h=fixture(config({WarehouseEnabled=1,WarehouseTypes=6}))
  local path='/Game/Structures/DataAssets/BuildingDataAssets/Building_Logistics_Storage.Building_Logistics_Storage'
  h.warehouseAsset=object('CBuildingDataAsset '..path,800,{})
  local configAsset=object('CStructureWarehouseDataConfig '..path..':WarehouseConfig',808,{MaxStorageSlots=15,InitialStorageSlotsPerResource=5})
  h.objects.CStructureWarehouseDataConfig={configAsset,object('Unrelated config',816,{MaxStorageSlots=99})}
  h:advance(2000);eq(h.native.WarehouseTypes,'6');eq(h.native.WarehouseAssetAddress,'800');eq(h.native.WarehouseBaseSlots,'15')
  eq(configAsset.MaxStorageSlots,15);eq(h.economy.MaxResourcesPerStorageBuilding,5);eq(h:status().WarehouseState,'Applied')
  h.warehousePending=true;h:advance(3000);eq(h:status().WarehouseState,'Waiting');eq(h:status().Status,'Partial')
  h.warehousePending=false;h.warehouseError=true;h:advance(3000);eq(h:status().WarehouseState,'Error')
  h.warehouseError=false;h:set({WarehouseEnabled=1,WarehouseTypes=9});h:advance(3000);eq(h.native.WarehouseTypes,'9')
  h:set({WarehouseEnabled=0,WarehouseTypes=9});h:advance(3000);eq(h.native.WarehouseTypes,'3');eq(h:status().WarehouseState,'Applied')
end)
test('invalid and incomplete warehouse/bridge settings retain last configuration',function()
  local h=fixture(config({WarehouseEnabled=1,WarehouseTypes=9,BridgesEnabled=1,BridgesSteps=30}));h:advance(2000)
  for _,bad in ipairs({{WarehouseEnabled=1,WarehouseTypes=5},{WarehouseEnabled=1},{WarehouseTypes=6},{BridgesEnabled=1},{BridgesSteps=30}}) do
    h:set(bad);h:advance(3000);eq(h:status().Status,'ConfigError');eq(h.native.WarehouseTypes,'9')
  end
end)
test('long-running warehouse polling and reloads use only bounded game-thread timers',function()
  local h=fixture(config({WarehouseEnabled=1,WarehouseTypes=9}))
  h:advance(600000)
  eq(#h.tasks,2,'only two persistent poll actions after ten minutes')
  for i=1,20 do
    h.hooks.map();h.hooks.game();h.notifies['/Script/Cove.CBridgeSetup']()
    h:advance(8000)
    eq(#h.tasks,2,'reload and asset callbacks drain without growing the timer queue')
  end
  h:set({WarehouseEnabled=0,WarehouseTypes=9,TransportEnabled=0,Revision='after-stress'})
  h:advance(3000)
  eq(h:status().Revision,'after-stress');eq(h.native.WarehouseTypes,'3')
end)
test('timer callbacks survive recoverable UI errors and settings still update',function()
  local h=fixture(config({WarehouseEnabled=1,WarehouseTypes=9}));h:advance(2000)
  h.throwUi=true;h:advance(2000);eq(h:status().WarehouseUiErrors,'1')
  h.throwUi=false
  h:set({WarehouseEnabled=0,WarehouseTypes=9,Revision='recovered'});h:advance(3000)
  eq(h:status().Revision,'recovered');eq(h:status().WarehouseUiErrors,'0');eq(#h.tasks,2)
end)
print('Backend: '..passed..' tests passed')
