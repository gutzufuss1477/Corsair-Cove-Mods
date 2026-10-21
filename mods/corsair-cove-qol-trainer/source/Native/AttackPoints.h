#pragma once
#include <cstdint>
#include <cstring>
#include <cmath>
#include <limits>

// Audited CModel and CIslandAttackPointData fields. Never retain/dereference a
// model outside its own native callback. Cached addresses are identity keys only.
template<class T> static T AttackRead(const void* p,size_t offset) {
    T value;std::memcpy(&value,static_cast<const unsigned char*>(p)+offset,sizeof(value));return value;
}
// Select only among the current model's existing coastal attack points. Camp
// coordinates are the same double-precision XY values selected by the original
// routine. No retained pointers, allocations, radius writes or live-object scans.
// Strict < keeps the first point in engine order on ties, including coincident
// points. Several camps can therefore share one attack point.
static bool NearestCoast(const void* model,const void* point,const void* campXY) {
    if(!model||!point||!campXY)return false;
    const auto list=AttackRead<const unsigned char*>(model,0x3bd0);
    const int count=AttackRead<int>(model,0x3bd8);
    if(count<=0||count>8192||!list)return false;
    const double x=AttackRead<double>(campXY,0),y=AttackRead<double>(campXY,8);
    if(!std::isfinite(x)||!std::isfinite(y))return false;
    double best=std::numeric_limits<double>::infinity();
    const void* nearest=nullptr;
    for(int i=0;i<count;++i) {
        const auto candidate=AttackRead<const void*>(list,i*16);
        const auto control=AttackRead<const unsigned char*>(list,i*16+8);
        if(!candidate||!control||!(control[0]&1))return false;
        const double dx=AttackRead<double>(candidate,0x70)-x;
        const double dy=AttackRead<double>(candidate,0x78)-y;
        const double distance=dx*dx+dy*dy;
        if(std::isfinite(distance)&&distance<best) {best=distance;nearest=candidate;}
    }
    return nearest==point;
}
using AttackPointFn=void(*)(void*,void*);
struct AttackRefreshState {
    uint64_t requested=0,applied=0,refreshes=0;
    const void* lastModel=nullptr;
    const void* lastPoints=nullptr;
    int lastCount=-1,points=0,eligible=0;
    bool busy=false,invalid=false;

    bool Pending() const {return requested!=applied;}
    void Invalidate() {++requested;invalid=false;}
    void Update(void* model,AttackPointFn camps,AttackPointFn towers) {
        if(!requested||!model||!camps||!towers||busy)return;
        auto list=AttackRead<unsigned char*>(model,0x3bd0);
        int count=AttackRead<int>(model,0x3bd8);
        // Do not interpret allocator-specific capacity flags; game traversal
        // uses only the pointer and count for this array of 16-byte handles.
        if(count<0||count>8192||(count>0&&!list)) {invalid=true;return;}
        if(!invalid&&!Pending()&&model==lastModel&&list==lastPoints&&count==lastCount)return;
        // Validate every handle before touching any cached membership. Empty
        // arrays are valid; engine lifecycle callbacks will supply new points.
        for(int i=0;i<count;++i) {
            auto point=AttackRead<void*>(list,i*16);
            auto handle=AttackRead<unsigned char*>(list,i*16+8);
            if(!point||!handle||!(handle[0]&1)) {invalid=true;return;}
        }
        busy=true;const auto generation=requested;
        int covered=0;
        for(int i=0;i<count;++i) {
            void* point=AttackRead<void*>(list,i*16);
            camps(model,point); // original routine releases/rebuilds camp handles
            towers(model,point); // original dependent tower coverage calculation
            if(AttackRead<int>(point,0xb8)>0)++covered;
        }
        // Same fortification invalidation flag used after the game's own range
        // refresh. No construction/logistics dirty flag and no global recalc.
        static_cast<unsigned char*>(model)[0x3c90]=1;
        lastModel=model;lastPoints=list;lastCount=count;
        points=count;eligible=covered;applied=generation;++refreshes;
        invalid=false;busy=false;
    }
};
