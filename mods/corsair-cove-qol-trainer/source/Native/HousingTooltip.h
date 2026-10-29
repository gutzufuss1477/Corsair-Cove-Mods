#pragma once
#include "AttackPoints.h"

using HousingModelFn=void*(*)(void*);
using HousingEligibilityFn=bool(*)(void*);
using HousingPopulationFn=int(*)(void*,void*);

// Read the same selected/associated camp as CGameObjectStatics::GetHousing.
// All handles are borrowed only during this synchronous game-thread call.
static void* HousingHandle(const void* handle) {
    auto object=AttackRead<void*>(handle,0);
    auto control=AttackRead<const unsigned char*>(handle,8);
    return object&&control&&(control[0]&1)?object:nullptr;
}
static bool HousingCampContribution(void* model,unsigned long steps,
    HousingEligibilityFn operational,HousingEligibilityFn excluded,int& result) {
    if(!model||!operational||!excluded||steps<10||steps>1000)return false;
    auto selected=HousingHandle(static_cast<unsigned char*>(model)+0x20b8);
    if(!selected)return false;
    auto link=AttackRead<unsigned char*>(selected,0x2f8);
    auto camp=link?HousingHandle(link+0x10):selected;
    if(!camp)return false;
    auto data=AttackRead<unsigned char*>(camp,0x2e8);
    if(!data)return false;
    result=0;
    if(!AttackRead<void*>(data,0x190))return true; // same empty WorkerPool gate
    auto houses=AttackRead<unsigned char*>(data,0x230);
    int count=AttackRead<int>(data,0x238);
    if(count<0||count>65536||(count&&!houses))return false;
    int64_t beds=0;
    for(int i=0;i<count;++i) {
        auto structure=HousingHandle(houses+i*16);
        if(!structure)continue;
        auto house=AttackRead<const int*>(structure,0x308);
        if(!house||!AttackRead<void*>(structure,0x2e8))continue;
        if(!operational(structure)||excluded(structure))continue;
        // Use current base/bonuses; never a cached value or hardcoded25.
        if(*house<0)return false; // unrecognised sentinel: preserve vanilla UI
        beds+=int64_t(*house)*steps/10;
        if(beds>INT32_MAX)beds=INT32_MAX;
    }
    result=static_cast<int>(beds);
    return true;
}

struct HousingTooltipState {
    // Identity only, never dereference a cached class pointer. Lua resolves the
    // exact tooltip UClass again on every bridge refresh and clears it if absent.
    uint64_t classAddress=0,updates=0,fallbacks=0;
    int lastCampBeds=0;
    HousingModelFn modelForWorld=nullptr;
    HousingEligibilityFn operational=nullptr,excluded=nullptr;

    int Value(void* context,void* asset,unsigned long steps,HousingPopulationFn original) {
        if(!classAddress||!context||!asset||
           AttackRead<uint64_t>(context,0x10)!=classAddress)return original(context,asset);
        if(!modelForWorld||!operational||!excluded){++fallbacks;return original(context,asset);}
        auto vtable=AttackRead<unsigned char*>(context,0);
        if(!vtable){++fallbacks;return original(context,asset);}
        auto getWorld=AttackRead<HousingModelFn>(vtable,0x180);
        if(!getWorld){++fallbacks;return original(context,asset);}
        auto world=getWorld(context);
        int beds=0;
        if(!world||!HousingCampContribution(modelForWorld(world),steps,operational,excluded,beds)) {
            ++fallbacks;return original(context,asset);
        }
        ++updates;lastCampBeds=beds;
        return beds;
    }
};
