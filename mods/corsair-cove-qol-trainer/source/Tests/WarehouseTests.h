#pragma once
static void* WarehouseFakeResolve(void* weak){return AttackRead<void*>(weak,0);}
static void RunWarehouseTests(){
    std::array<unsigned char,0x2200> model{};
    std::array<unsigned char,0x400> building{},other{},dead{};
    std::array<unsigned char,0x50> data{},otherData{};
    std::array<unsigned char,0x80> storage{},otherStorage{};
    std::array<unsigned char,0x78*9> entries{};entries.fill(0x5a);
    unsigned char alive=1,notAlive=0;
    struct Handle{void* object;unsigned char* control;};
    std::array<Handle,3> list{{{building.data(),&alive},{other.data(),&alive},{dead.data(),&notAlive}}};
    auto put=[](auto& a,size_t at,auto value){std::memcpy(a.data()+at,&value,sizeof(value));};
    put(model,0x1798,list.data());put(model,0x17a0,3);put(model,0x2090,list[0]);
    put(building,0x118,reinterpret_cast<void*>(0x8000));put(other,0x118,reinterpret_cast<void*>(0x9000));
    put(building,0x268,data.data());put(building,0x208,storage.data());
    put(other,0x268,otherData.data());put(other,0x208,otherStorage.data());
    put(data,0,15);put(data,4,5);put(otherData,0,15);put(otherData,4,5);
    put(storage,0,entries.data());put(storage,8,9);put(storage,0x10,15);storage[0x14]=1;
    put(otherStorage,0x10,15);otherStorage[0x14]=1;
    auto originalEntries=entries;auto originalBuilding=building;
    auto originalOtherData=otherData;auto originalOtherStorage=otherStorage;
    WarehouseState state;state.resolveAsset=&WarehouseFakeResolve;
    put(data,0,60);put(storage,0x10,60);state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==60&&AttackRead<int>(storage.data(),0x10)==60,"An untouched disabled option never changes existing capacity");
    put(data,0,15);put(storage,0x10,15);
    state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==45&&AttackRead<int>(storage.data(),0x10)==45,"Nine standard goods allocations receive45 slots");
    Require(state.warehouses==1&&state.selected&&state.selectedResources==9&&state.selectedSlots==45&&!state.pending&&!state.invalid,"Warehouse selection and completed configuration are reported");
    Require(otherData==originalOtherData&&otherStorage==originalOtherStorage,"Trading posts and unrelated warehouses are excluded by exact asset identity");
    auto changes=state.changes;state.Update(model.data());Require(changes==state.changes,"Repeated warehouse ticks are idempotent");
    state.Configure(6,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==30&&AttackRead<int>(storage.data(),0x10)==30,"Six standard allocations receive30 slots");
    state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==15&&AttackRead<int>(storage.data(),0x10)==15,"Disabling restores both original capacity limits");
    Require(entries==originalEntries&&building==originalBuilding&&AttackRead<int>(storage.data(),8)==9,"Reducing capacity never rewrites stock, allocations, reservations or structure records");
    put(data,0,52);put(storage,0x10,53);state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==52&&AttackRead<int>(storage.data(),0x10)==53,"Pre-existing capacities above the requested size remain independent");
    put(data,0,54);put(storage,0x10,55);state.Update(model.data());state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==54&&AttackRead<int>(storage.data(),0x10)==55,"Game capacity recalculations become the new restore baseline");
    put(data,0,15);put(storage,0x10,15);
    state.Configure(9,60,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==60,"Higher original warehouse limits are retained");
    put(data,4,7);state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==63,"Actual initial allocation determines enlarged capacity");
    for(int bad:{0,-1,101}){put(data,4,bad);auto before=storage;state.Update(model.data());Require(state.invalid&&state.pending&&storage==before,"Malformed allocations fail without storage writes");}
    put(data,4,5);storage[0x14]=0;auto before=storage;state.Update(model.data());Require(state.invalid&&storage==before,"Unlimited or absent storage capacity is never reinterpreted as a finite slot limit");
    storage[0x14]=1;put(model,0x2090,list[1]);state.Update(model.data());Require(!state.selected&&state.selectedResources==0,"Selecting another building clears warehouse UI context");
    put(model,0x17a0,65537);before=storage;state.Update(model.data());Require(state.invalid&&storage==before,"Malformed structure arrays are rejected before iteration");
    put(model,0x17a0,0);state.Update(model.data());Require(!state.invalid&&state.warehouses==0,"Empty maps require no special warehouses");
    put(model,0x17a0,3);state.Configure(6,15,0);before=storage;state.Update(model.data());Require(state.pending&&storage==before,"Unloaded exact asset keeps configuration pending without writes");
}
