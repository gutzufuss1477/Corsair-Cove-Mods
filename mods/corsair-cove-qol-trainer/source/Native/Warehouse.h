#pragma once
#include "HousingTooltip.h"
#include <algorithm>
#include <map>

using WarehouseResolveFn=void*(*)(void*);
// Build 26091248 moved storage into CItemStorage handles. Mirror the game's
// GetStorage selector (RVA 5d8bd50), borrowing only during this game-thread call:
// use the live override at +550, otherwise the primary at +540. Never retain a
// dereferenceable handle or increment/decrement the engine's reference counts.
static unsigned char* WarehouseStorage(unsigned char* structure,void*& control) {
    auto handle=structure+0x550;
    auto storage=HousingHandle(handle);
    if(!storage) {handle=structure+0x540;storage=HousingHandle(handle);}
    control=storage?AttackRead<void*>(handle,8):nullptr;
    return static_cast<unsigned char*>(storage);
}
// Only scalar capacity limits are changed. Storage entries, amounts, reservations,
// fetchers and allocations remain engine-owned, including when lowering the limit.
struct WarehouseState {
    unsigned types=3,baseSlots=15;
    uint64_t assetAddress=0,changes=0;
    int warehouses=0;
    bool selected=false;
    int selectedResources=0,selectedSlots=0;
    bool configured=false,pending=true,invalid=false;
    WarehouseResolveFn resolveAsset=nullptr;
    struct Original {
        void* storage;void* control;void* storageControl;
        int warehouse,capacity,lastWarehouse,lastCapacity;
        uint64_t seen;
    };
    std::map<void*,Original> originals;
    void* lastModel=nullptr;uint64_t tick=0;
    void Configure(unsigned value,unsigned base,uint64_t asset) {
        if(!configured||types!=value||baseSlots!=base||assetAddress!=asset)pending=true;
        types=value;baseSlots=base;assetAddress=asset;configured=true;
    }
    void Update(void* model) {
        selected=false;selectedResources=selectedSlots=0;
        if(!configured||!model||!resolveAsset||!assetAddress)return;
        if(lastModel!=model){originals.clear();lastModel=model;}
        ++tick;
        auto list=AttackRead<unsigned char*>(model,0x17b0);
        const int count=AttackRead<int>(model,0x17b8);
        invalid=count<0||count>65536||(count&&!list);
        if(invalid)return;
        int found=0;
        for(int i=0;i<count;++i) {
            auto s=static_cast<unsigned char*>(HousingHandle(list+16*i));
            if(!s)continue;
            auto warehouse=AttackRead<unsigned char*>(s,0x268);
            void* storageControl=nullptr;
            auto storage=WarehouseStorage(s,storageControl);
            if(!warehouse||reinterpret_cast<uint64_t>(resolveAsset(s+0x118))!=assetAddress)continue;
            if(!storage){invalid=true;continue;}
            const int initial=AttackRead<int>(warehouse,4);
            const int current=AttackRead<int>(warehouse,0);
            const int storageMax=AttackRead<int>(storage,0);
            const int entries=AttackRead<int>(storage,0x30);
            if(initial<1||initial>100||current<1||current>4096||storageMax<1||storageMax>4096||
               storage[4]!=1||entries<0||entries>4096||baseSlots<1||baseSlots>4096||
               (types!=3&&types!=6&&types!=9)) {invalid=true;continue;}
            ++found;
            if(s==HousingHandle(static_cast<unsigned char*>(model)+0x20b8)) {
                selected=true;selectedResources=entries;
            }
            auto control=AttackRead<void*>(list+16*i,8);
            auto previous=originals.find(s);
            if(previous!=originals.end()&&(previous->second.storage!=storage||previous->second.control!=control||previous->second.storageControl!=storageControl)) {
                originals.erase(previous);previous=originals.end();
            }
            if(previous==originals.end()&&types!=3) {
                previous=originals.emplace(s,Original{storage,control,storageControl,current,storageMax,current,storageMax,tick}).first;
            }
            int target=current,capacity=storageMax;
            if(previous!=originals.end()) {
                auto& old=previous->second;old.seen=tick;
                // A game recalculation or another mod owns its new value. Capture
                // that baseline instead of restoring a stale pre-upgrade limit.
                if(current!=old.lastWarehouse)old.warehouse=current;
                if(storageMax!=old.lastCapacity)old.capacity=storageMax;
                target=types==3?old.warehouse:std::max({int(baseSlots),old.warehouse,initial*int(types)});
                capacity=types==3?old.capacity:std::max({int(baseSlots),old.capacity,initial*int(types)});
                old.lastWarehouse=target;old.lastCapacity=capacity;
            }
            if(selected&&s==HousingHandle(static_cast<unsigned char*>(model)+0x20b8))selectedSlots=target;
            if(current!=target||storageMax!=capacity) {
                std::memcpy(warehouse,&target,sizeof(target));
                std::memcpy(storage,&capacity,sizeof(capacity));
                ++changes;
            }
            if(types==3&&previous!=originals.end())originals.erase(previous);
        }
        for(auto it=originals.begin();it!=originals.end();) {
            if(!invalid&&it->second.seen!=tick)it=originals.erase(it);else ++it;
        }
        warehouses=found;pending=invalid;
    }
};
