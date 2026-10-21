#pragma once
#include "AttackPoints.h"

using SetCampRadiusFn=void(*)(void*,void*,float);
// CModel.PirateCamps, audited handle layout. The original setter updates the
// radius view, coastal coverage and the logistics dirty flag, only on a change.
// DefaultRange is the unmodified base; the game's range perk adds to that base.
struct CampRadiusState {
    float factor=1;
    bool configured=false,pending=true,invalid=false;
    uint64_t changes=0;
    int camps=0;
    void Configure(float value) {if(!configured||factor!=value)pending=true;factor=value;configured=true;}
    void Update(void* model,SetCampRadiusFn setRadius) {
        if(!configured||!model||!setRadius)return;
        auto list=AttackRead<unsigned char*>(model,0x1898);
        int count=AttackRead<int>(model,0x18a0);
        auto coast=AttackRead<unsigned char*>(model,0x3bd0);
        int points=AttackRead<int>(model,0x3bd8);
        invalid=count<0||count>4096||(count&&!list)||points<0||points>8192||(points&&!coast);
        if(invalid)return;
        for(int i=0;i<points;++i) {
            auto control=AttackRead<unsigned char*>(coast,i*16+8);
            if(!AttackRead<void*>(coast,i*16)||!control||!(control[0]&1)){invalid=true;return;}
        }
        // Validate before modifying any camp; do not keep world pointers between ticks.
        for(int i=0;i<count;++i) {
            auto camp=AttackRead<void*>(list,i*16);
            auto control=AttackRead<unsigned char*>(list,i*16+8);
            if(!camp||!control||!(control[0]&1)){invalid=true;return;}
            auto data=AttackRead<void*>(camp,0x2e8);
            if(!data){invalid=true;return;}
            float base=AttackRead<float>(data,0x328),current=AttackRead<float>(data,0x32c);
            if(!std::isfinite(base)||!std::isfinite(current)||base<=0||current<=0||base>2000000||current>3000000){invalid=true;return;}
        }
        const float target=3000.0f*factor;
        for(int i=0;i<count;++i) {
            auto camp=AttackRead<void*>(list,i*16);
            auto data=AttackRead<void*>(camp,0x2e8);
            float base=AttackRead<float>(data,0x328);
            if(std::abs(base-target)<0.01f)continue;
            float current=AttackRead<float>(data,0x32c);
            // Preserve additive unlock bonuses, including while toggling back to x1.
            float next=target+(current-base);
            if(next<=0||next>3000000){invalid=true;return;}
            std::memcpy(static_cast<unsigned char*>(data)+0x328,&target,sizeof(target));
            setRadius(model,camp,next);
            ++changes;
        }
        camps=count;pending=false;
    }
};
