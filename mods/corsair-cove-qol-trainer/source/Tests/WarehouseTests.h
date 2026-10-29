#pragma once
static void* WarehouseFakeResolve(void* weak){return AttackRead<void*>(weak,0);}
static void RunWarehouseTests(){
    std::array<unsigned char,0x2200> model{};
    std::array<unsigned char,0x600> building{},other{},dead{};
    std::array<unsigned char,0x50> data{},otherData{};
    std::array<unsigned char,0x80> storage{},otherStorage{};
    std::array<unsigned char,0x78*9> entries{};entries.fill(0x5a);
    unsigned char alive=1,notAlive=0;
    struct Handle{void* object;unsigned char* control;};
    std::array<Handle,3> list{{{building.data(),&alive},{other.data(),&alive},{dead.data(),&notAlive}}};
    auto put=[](auto& a,size_t at,auto value){std::memcpy(a.data()+at,&value,sizeof(value));};
    put(model,0x17b0,list.data());put(model,0x17b8,3);put(model,0x20b8,list[0]);
    put(building,0x118,reinterpret_cast<void*>(0x8000));put(other,0x118,reinterpret_cast<void*>(0x9000));
    put(building,0x268,data.data());put(building,0x540,Handle{storage.data(),&alive});
    put(other,0x268,otherData.data());put(other,0x540,Handle{otherStorage.data(),&alive});
    put(data,0,15);put(data,4,5);put(otherData,0,15);put(otherData,4,5);
    put(storage,0x28,entries.data());put(storage,0x30,9);put(storage,0,15);storage[4]=1;
    put(otherStorage,0,15);otherStorage[4]=1;
    auto originalEntries=entries;auto originalBuilding=building;
    auto originalOtherData=otherData;auto originalOtherStorage=otherStorage;
    WarehouseState state;state.resolveAsset=&WarehouseFakeResolve;
    put(data,0,60);put(storage,0,60);state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==60&&AttackRead<int>(storage.data(),0)==60,"An untouched disabled option never changes existing capacity");
    put(data,0,15);put(storage,0,15);
    state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==45&&AttackRead<int>(storage.data(),0)==45,"Nine standard goods allocations receive45 slots");
    Require(state.warehouses==1&&state.selected&&state.selectedResources==9&&state.selectedSlots==45&&!state.pending&&!state.invalid,"Warehouse selection and completed configuration are reported");
    Require(otherData==originalOtherData&&otherStorage==originalOtherStorage,"Trading posts and unrelated warehouses are excluded by exact asset identity");
    auto changes=state.changes;state.Update(model.data());Require(changes==state.changes,"Repeated warehouse ticks are idempotent");
    state.Configure(6,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==30&&AttackRead<int>(storage.data(),0)==30,"Six standard allocations receive30 slots");
    state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==15&&AttackRead<int>(storage.data(),0)==15,"Disabling restores both original capacity limits");
    Require(entries==originalEntries&&building==originalBuilding&&AttackRead<int>(storage.data(),0x30)==9,"Reducing capacity never rewrites stock, allocations, reservations or structure records");
    put(data,0,52);put(storage,0,53);state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==52&&AttackRead<int>(storage.data(),0)==53,"Pre-existing capacities above the requested size remain independent");
    put(data,0,54);put(storage,0,55);state.Update(model.data());state.Configure(3,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==54&&AttackRead<int>(storage.data(),0)==55,"Game capacity recalculations become the new restore baseline");
    put(data,0,15);put(storage,0,15);
    state.Configure(9,60,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==60,"Higher original warehouse limits are retained");
    put(data,4,7);state.Configure(9,15,0x8000);state.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==63,"Actual initial allocation determines enlarged capacity");
    for(int bad:{0,-1,101}){put(data,4,bad);auto before=storage;state.Update(model.data());Require(state.invalid&&state.pending&&storage==before,"Malformed allocations fail without storage writes");}
    put(data,4,5);storage[4]=0;auto before=storage;state.Update(model.data());Require(state.invalid&&storage==before,"Unlimited or absent storage capacity is never reinterpreted as a finite slot limit");
    storage[4]=1;put(model,0x20b8,list[1]);state.Update(model.data());Require(!state.selected&&state.selectedResources==0,"Selecting another building clears warehouse UI context");
    put(model,0x17b8,65537);before=storage;state.Update(model.data());Require(state.invalid&&storage==before,"Malformed structure arrays are rejected before iteration");
    put(model,0x17b8,0);state.Update(model.data());Require(!state.invalid&&state.warehouses==0,"Empty maps require no special warehouses");
    put(model,0x17b8,3);state.Configure(6,15,0);before=storage;state.Update(model.data());Require(state.pending&&storage==before,"Unloaded exact asset keeps configuration pending without writes");

    // The updated game's getter selects a live override before its primary.
    // Poison obsolete fields so the fixture detects old-layout accesses.
    put(building,0x208,reinterpret_cast<void*>(1));put(storage,8,-99);
    std::array<unsigned char,0x80> overrideStorage{};
    unsigned char overrideAlive=1,secondControl=1;
    put(overrideStorage,0,18);overrideStorage[4]=1;put(overrideStorage,0x30,4);
    put(building,0x550,Handle{overrideStorage.data(),&overrideAlive});
    put(model,0x20b8,list[0]);put(data,0,15);put(storage,0,15);
    WarehouseState fresh;fresh.resolveAsset=&WarehouseFakeResolve;fresh.Configure(9,15,0x8000);
    const auto primaryBefore=storage;fresh.Update(model.data());
    Require(!fresh.invalid&&fresh.selectedResources==4&&AttackRead<int>(overrideStorage.data(),0)==45,
        "Current game storage getter selects override and reads the new entry-count field");
    Require(storage==primaryBefore,"Override selection never changes the inactive primary storage");
    fresh.Configure(3,15,0x8000);fresh.Update(model.data());
    Require(AttackRead<int>(overrideStorage.data(),0)==18&&AttackRead<int>(data.data(),0)==15,
        "Override capacity and warehouse capacity restore independently");
    overrideAlive=0;fresh.Configure(6,15,0x8000);fresh.Update(model.data());
    Require(!fresh.invalid&&fresh.selectedResources==9&&AttackRead<int>(storage.data(),0)==30,
        "Expired override falls back to live primary without dereferencing its storage");
    Require(AttackRead<int>(overrideStorage.data(),0)==18,"Expired override is untouched");
    fresh.Configure(3,15,0x8000);fresh.Update(model.data());
    // A recycled storage address with a new control block is a new identity.
    fresh.Configure(9,15,0x8000);fresh.Update(model.data());
    put(building,0x540,Handle{storage.data(),&secondControl});put(data,0,21);put(storage,0,22);
    fresh.Update(model.data());fresh.Configure(3,15,0x8000);fresh.Update(model.data());
    Require(AttackRead<int>(data.data(),0)==21&&AttackRead<int>(storage.data(),0)==22,
        "Recycled storage pointer cannot restore an old object's capacity baseline");
    put(building,0x540,Handle{reinterpret_cast<void*>(1),&notAlive});
    before=storage;fresh.Configure(9,15,0x8000);fresh.Update(model.data());
    Require(fresh.invalid&&fresh.pending&&storage==before,"No valid current storage fails closed without dereference or writes");
}
