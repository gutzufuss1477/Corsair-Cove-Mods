// Version-locked, in-process QoL hooks for the audited build.
// Entry points are Lua C functions returning no Lua values: no Lua ABI imports.
// Loaded by package.loadlib, pinned for process lifetime; no worker/subprocess/UI.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <vector>
#include <mutex>
#include <iomanip>
#include "MinHook.h"
#include <cmath>
#include "BattleProtection.h"
#include "AttackPoints.h"
#include "CampRadius.h"
#include "HousingTooltip.h"
#include "Warehouse.h"
#pragma comment(lib,"bcrypt.lib")

extern "C" {
    alignas(4) unsigned long campHousingSteps=10;
    alignas(8) volatile LONG64 campHousingReads=0;
    void *campHousingResume=nullptr,*campHousingPendingResume=nullptr;
    void CampHousingHook();void CampHousingPendingHook();
    alignas(8) float walkMultiplier=1;
    // Exact MT_Worker asset identity supplied by Lua discovery. Compared only;
    // never dereferenced. All other agent types keep their original speeds.
    alignas(8) unsigned long long workerMovementAddress=0;
    alignas(8) double locomotionMultiplier=1;
    alignas(8) volatile LONG64 locomotionDefaultCalls=0,locomotionOverrideCalls=0;
    void *locomotionDefaultResume=nullptr,*locomotionOverrideResume=nullptr;
    void *locomotionIndexedDefaultResume=nullptr,*locomotionIndexedOverrideResume=nullptr;
    void LocomotionDefaultHook();void LocomotionOverrideHook();
    void LocomotionIndexedDefaultHook();void LocomotionIndexedOverrideHook();
    alignas(8) float constructionMultiplier=1;
    alignas(8) float shipMultiplier=1;
    alignas(8) volatile LONG64 shipCalls=0;
    void* shipResume=nullptr;
    void ShipSpeedHook();
    void *stepResume=nullptr,*durationResume=nullptr,*remainingResume=nullptr,*visualResume=nullptr;
    void *visualTimeResume=nullptr,*planResume=nullptr,*arrivalResume=nullptr,*routeResume=nullptr,*routeAltResume=nullptr;
    void* constructionResume=nullptr;
    alignas(8) volatile LONG64 walkCalls=0,visualCalls=0;
    alignas(8) volatile LONG64 visualTimeCalls=0,transportPlanCalls=0;
    alignas(8) volatile LONG64 constructionCalls=0;
    alignas(4) volatile LONG campOverlapEnabled=0;
    alignas(8) volatile LONG64 campOverlapChecks=0,campOverlapBypasses=0;
    void *campGateContinue=nullptr,*campGateReject=nullptr;
    alignas(4) volatile LONG nearestCoastEnabled=0;
    alignas(8) volatile LONG64 nearestCoastChecks=0,nearestCoastSelected=0;
    void *nearestCoastAccept=nullptr,*nearestCoastReject=nullptr,*attackTickOriginal=nullptr;
    void StepHook(); void DurationHook(); void RemainingHook(); void VisualHook();
    void VisualTimeHook();void TransportPlanHook();void TransportArrivalHook();
    void TransportRouteHook();void TransportRouteAltHook();
    void ConstructionHook();
    void CampGateHook();
    void NearestCoastHook();void AttackTickHook();
    alignas(4) volatile LONG keepRevealedEnabled=0;
    alignas(8) volatile LONG64 fogKeepChecks=0,fogKeepOverrides=0,fogTransitionChecks=0,fogCoversBlocked=0;
    void *fogKeepResume=nullptr,*fogTransitionResume=nullptr;
    void FogKeepHook();void FogTransitionHook();
}
using CampRangeFn=bool(*)(void*,void*,void*);
static CampRangeFn campRangeOriginal=nullptr;
static bool attempted=false,ready=false;
static std::string error="NotInitialized",revision;
static std::wstring folder;
static std::mutex bridgeMutex;
static std::vector<void*> ownedHooks;
static AttackRefreshState attackRefresh;
static CampRadiusState campRadius;
static SetCampRadiusFn setCampRadius=nullptr;
static AttackPointFn updateAttackCamps=nullptr,updateAttackTowers=nullptr;
static unsigned long attackRefreshToken=0;
static HousingTooltipState housingTooltip;
static WarehouseState warehouseState;
static HousingPopulationFn housingPopulationOriginal=nullptr;
static int HousingPopulationHook(void* context,void* asset) {
    return housingTooltip.Value(context,asset,campHousingSteps,housingPopulationOriginal);
}
extern "C" bool SelectNearestCoast(void* model,void* point,const void* campXY) {
    const bool selected=NearestCoast(model,point,campXY);
    if(selected)InterlockedIncrement64(&nearestCoastSelected);
    return selected;
}
extern "C" void RefreshAttackPoints(void* model) {
    warehouseState.Update(model);
    campRadius.Update(model,setCampRadius);
    attackRefresh.Update(model,updateAttackCamps,updateAttackTowers);
}

// Only the pirate-camp placement proximity helper. Its third argument is the
// placer; forwarding just the first two arguments would corrupt the calculation.
static bool CampRangeHook(void* campData,void* model,void* placer) {
    const bool conflict=campRangeOriginal(campData,model,placer);
    InterlockedIncrement64(&campOverlapChecks);
    if(conflict && campOverlapEnabled) {
        InterlockedIncrement64(&campOverlapBypasses);
        return false;
    }
    return conflict;
}
static std::string Sha256(const wchar_t* path) {
    BCRYPT_ALG_HANDLE alg=nullptr; BCRYPT_HASH_HANDLE hash=nullptr;
    if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) return "";
    if(BCryptCreateHash(alg,&hash,nullptr,0,nullptr,0,0)<0) { BCryptCloseAlgorithmProvider(alg,0);return ""; }
    std::ifstream in(path,std::ios::binary);
    std::vector<char> buffer(1024*1024);bool ok=in.good();
    while(in) {
        in.read(buffer.data(),buffer.size());
        if(in.gcount() && BCryptHashData(hash,reinterpret_cast<PUCHAR>(buffer.data()),static_cast<ULONG>(in.gcount()),0)<0) {ok=false;break;}
    }
    if(in.bad())ok=false;
    unsigned char digest[32];
    if(BCryptFinishHash(hash,digest,sizeof(digest),0)<0)ok=false;
    BCryptDestroyHash(hash);BCryptCloseAlgorithmProvider(alg,0);
    if(!ok)return "";
    std::ostringstream out;out<<std::hex<<std::setfill('0');
    for(auto x:digest)out<<std::setw(2)<<unsigned(x);
    return out.str();
}
static void Status() {
    std::ofstream out(folder+L"native-status.ini.tmp",std::ios::trunc);
    out<<"Version=1.2.5\nReady="<<(ready?1:0)<<"\nError="<<error<<"\nRevision="<<revision
       <<"\nWarehouseTypes="<<warehouseState.types<<"\nWarehouseBaseSlots="<<warehouseState.baseSlots
       <<"\nWarehouseAssetAddress="<<warehouseState.assetAddress<<"\nWarehouseChanges="<<warehouseState.changes
       <<"\nWarehouseCount="<<warehouseState.warehouses<<"\nWarehousePending="<<(warehouseState.pending?1:0)
       <<"\nWarehouseError="<<(warehouseState.invalid?1:0)
       <<"\nWarehouseSelected="<<(warehouseState.selected?1:0)<<"\nWarehouseSelectedResources="<<warehouseState.selectedResources<<"\nWarehouseSelectedSlots="<<warehouseState.selectedSlots
       <<"\nCampHousingSteps="<<campHousingSteps<<"\nCampHousingReads="<<campHousingReads
       <<"\nHousingTooltipClassAddress="<<housingTooltip.classAddress
       <<"\nHousingTooltipUpdates="<<housingTooltip.updates<<"\nHousingTooltipFallbacks="<<housingTooltip.fallbacks
       <<"\nHousingTooltipCampBeds="<<housingTooltip.lastCampBeds
       <<"\nTransportFactor="<<walkMultiplier
       <<"\nConstructionFactor="<<constructionMultiplier
       <<"\nShipFactor="<<shipMultiplier<<"\nShipCalls="<<InterlockedCompareExchange64(&shipCalls,0,0)
       <<"\nTransportCalls="<<InterlockedCompareExchange64(&walkCalls,0,0)
       <<"\nVisualCalls="<<InterlockedCompareExchange64(&visualCalls,0,0)
       <<"\nVisualTimeCalls="<<InterlockedCompareExchange64(&visualTimeCalls,0,0)
       <<"\nTransportPlanCalls="<<InterlockedCompareExchange64(&transportPlanCalls,0,0)
       <<"\nWorkerMovementAddress="<<workerMovementAddress
       <<"\nLocomotionDefaultCalls="<<InterlockedCompareExchange64(&locomotionDefaultCalls,0,0)
       <<"\nLocomotionOverrideCalls="<<InterlockedCompareExchange64(&locomotionOverrideCalls,0,0)
       <<"\nConstructionCalls="<<InterlockedCompareExchange64(&constructionCalls,0,0)
       <<"\nCampRadiusFactor="<<campRadius.factor<<"\nCampRadiusPending="<<(campRadius.pending?1:0)
       <<"\nCampRadiusError="<<(campRadius.invalid?1:0)<<"\nCampRadiusChanges="<<campRadius.changes<<"\nCampRadiusCamps="<<campRadius.camps
       <<"\nCampOverlapEnabled="<<campOverlapEnabled
       <<"\nCampOverlapChecks="<<InterlockedCompareExchange64(&campOverlapChecks,0,0)
       <<"\nCampOverlapBypasses="<<InterlockedCompareExchange64(&campOverlapBypasses,0,0)
       <<"\nNearestCoastEnabled="<<nearestCoastEnabled
       <<"\nAttackRefreshToken="<<attackRefreshToken
       <<"\nAttackPending="<<(attackRefresh.Pending()?1:0)<<"\nAttackRefreshError="<<(attackRefresh.invalid?1:0)
       <<"\nAttackRefreshes="<<attackRefresh.refreshes<<"\nAttackPoints="<<attackRefresh.points
       <<"\nAttackEligiblePoints="<<attackRefresh.eligible
       <<"\nNearestCoastChecks="<<InterlockedCompareExchange64(&nearestCoastChecks,0,0)
       <<"\nNearestCoastSelected="<<InterlockedCompareExchange64(&nearestCoastSelected,0,0)
       <<"\nKeepRevealedEnabled="<<keepRevealedEnabled
       <<"\nFogKeepChecks="<<InterlockedCompareExchange64(&fogKeepChecks,0,0)
       <<"\nFogKeepOverrides="<<InterlockedCompareExchange64(&fogKeepOverrides,0,0)
       <<"\nFogTransitionChecks="<<InterlockedCompareExchange64(&fogTransitionChecks,0,0)
       <<"\nFogCoversBlocked="<<InterlockedCompareExchange64(&fogCoversBlocked,0,0)
       <<"\nBattleHullEnabled="<<((battleProtectionMask&1)?1:0)
       <<"\nBattleCrewEnabled="<<((battleProtectionMask&2)?1:0)
       <<"\nBattleSuppliesEnabled="<<((battleProtectionMask&4)?1:0)
       <<"\nBattleStatChecks="<<battleStatChecks<<"\nBattleStatBlocks="<<battleStatBlocks
       <<"\nBattleSupplyChecks="<<battleSupplyChecks<<"\nBattleSupplyBlocks="<<battleSupplyBlocks<<"\n";
    out.close();
    if(out)MoveFileExW((folder+L"native-status.ini.tmp").c_str(),(folder+L"native-status.ini").c_str(),MOVEFILE_REPLACE_EXISTING);
}
static bool Fingerprint(const unsigned char* at,const char* hex) {
    for(size_t i=0;hex[i];i+=2) {
        auto digit=[](char c){return c<='9'?c-'0':c-'a'+10;};
        if(at[i/2]!=((digit(hex[i])<<4)|digit(hex[i+1])))return false;
    }
    return true;
}
static void Initialize() {
    attempted=true;
    wchar_t local[32768],exe[32768];
    if(!GetEnvironmentVariableW(L"LOCALAPPDATA",local,32768)) {error="NoDataDirectory";return;}
    folder=std::wstring(local)+L"\\CorsairCoveQoL\\";CreateDirectoryW(folder.c_str(),nullptr);
    if(!GetModuleFileNameW(nullptr,exe,32768) ||
       Sha256(exe)!="86a0430db6bcba963a97a36b5d9e4bc0366989e65ff8ce6735e0cfe0aec42f32") {
        error="UnsupportedGameBuild";return;
    }
    // Never let a Lua reload unload executable code while a hook points into it.
    HMODULE pinned=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(&Initialize),&pinned)) {error="ModulePinFailed";return;}
    auto base=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
    struct Hook {size_t rva;const char* bytes;void* replacement;void** original;size_t skip;};
    void* unusedStep=nullptr;void* unusedDuration=nullptr;void* unusedRemaining=nullptr;void* unusedVisual=nullptr;
    void *unusedVisualTime=nullptr,*unusedPlan=nullptr,*unusedArrival=nullptr,*unusedRoute=nullptr,*unusedRouteAlt=nullptr;
    void* unusedConstruction=nullptr;void* unusedCampGate=nullptr;
    void* unusedNearestCoast=nullptr;
    void *unusedFogKeep=nullptr,*unusedFogTransition=nullptr;
    void* unusedShip=nullptr;
    void *unusedHousing=nullptr,*unusedPendingHousing=nullptr;
    void *unusedLocomotionDefault=nullptr,*unusedLocomotionOverride=nullptr;
    void *unusedLocomotionIndexedDefault=nullptr,*unusedLocomotionIndexedOverride=nullptr;
    Hook hooks[]={
        // Only the identified housing tooltip needs beds instead of the stock
        // population count. Other callers retain the original population API.
        {0x5def7a0,"48896c241848897c242041564883ec20",reinterpret_cast<void*>(&HousingPopulationHook),reinterpret_cast<void**>(&housingPopulationOriginal),0},
        {0x5db0856,"488b8a0803000003394883c310483bde7598",reinterpret_cast<void*>(&CampHousingHook),&unusedHousing,7},
        {0x5db0916,"488b8a0803000003394883c310483bde7598",reinterpret_cast<void*>(&CampHousingPendingHook),&unusedPendingHousing,7},
        {0x5ceb3f0,"48895c240848896c24104889742418574883ec20",reinterpret_cast<void*>(&BattleStatHook),reinterpret_cast<void**>(&battleStatOriginal),0},
        {0x5cee200,"48895c240848896c241048897424185741564157",reinterpret_cast<void*>(&BattleSupplyHook),reinterpret_cast<void**>(&battleSupplyOriginal),0},
        // Final effective speed returned to sailing, path and travel-time code.
        // Covers cached/live ships, original modifiers are already included.
        {0x5d61947,"0f28c6488b4c24304833cce8",reinterpret_cast<void*>(&ShipSpeedHook),&unusedShip,8},
        {0x5d04dbd,"f30f104b08488d4b50",reinterpret_cast<void*>(&StepHook),&unusedStep,5},
        {0x5cfda79,"f30f1043080f5ac0",reinterpret_cast<void*>(&DurationHook),&unusedDuration,5},
        {0x5cff4b2,"f30f104b08f20f1015",reinterpret_cast<void*>(&RemainingHook),&unusedRemaining,5},
        // Carrier view controller: movement input and remaining-time transition.
        // The old 5cf941a hook was a different path-following implementation.
        {0x5ad93ac,"f30f104b084d8bcef20f1003",reinterpret_cast<void*>(&VisualHook),&unusedVisual,5},
        {0x5ad9420,"f30f104b08f30f1015f3ee9502",reinterpret_cast<void*>(&VisualTimeHook),&unusedVisualTime,5},
        // Both movement-speed getters choose by path connection type, with an
        // optional per-agent override. Scale their final read for MT_Worker.
        // Changing only ConnectionConfigs[0] misses roads/other connection types.
        {0x5ab02af,"f20f1004c3488b5c24404883c430",reinterpret_cast<void*>(&LocomotionDefaultHook),&unusedLocomotionDefault,5},
        {0x5ab02d9,"f20f1000488b5c24404883c430",reinterpret_cast<void*>(&LocomotionOverrideHook),&unusedLocomotionOverride,9},
        {0x5ab0d22,"f20f1004c3488b5c24484883c430",reinterpret_cast<void*>(&LocomotionIndexedDefaultHook),&unusedLocomotionIndexedDefault,5},
        {0x5ab0d4c,"f20f1000488b5c24484883c430",reinterpret_cast<void*>(&LocomotionIndexedOverrideHook),&unusedLocomotionIndexedOverride,9},
        // Travel estimates read the global base speed directly. Cached path
        // creation/load remain vanilla so these read hooks never double-scale.
        {0x5b4f23e,"f30f108000030000488d459f",reinterpret_cast<void*>(&TransportPlanHook),&unusedPlan,8},
        {0x5b6edc1,"f30f108b000300004d8d466c",reinterpret_cast<void*>(&TransportArrivalHook),&unusedArrival,8},
        {0x5b75a3e,"f30f108e000300004c8d8e78020000",reinterpret_cast<void*>(&TransportRouteHook),&unusedRoute,8},
        {0x5b75d9c,"f30f1088000300004c8d8878020000",reinterpret_cast<void*>(&TransportRouteAltHook),&unusedRouteAlt,8},
        // XMM6 already holds worker contribution / construction duration. Scale
        // before the original delta-time multiplication and resource progress cap.
        {0x5c8ee84,"f3410f107f08f30f59f04885d2",reinterpret_cast<void*>(&ConstructionHook),&unusedConstruction,6},
        {0x5d36ce0,"48895c2408574883ec700f29742460",reinterpret_cast<void*>(&CampRangeHook),reinterpret_cast<void**>(&campRangeOriginal),0},
        // Second overlap rejection: continue through the original reference
        // release and required-structure checks, never return blanket success.
        {0x5d27b04,"41f60101744a41c60717",reinterpret_cast<void*>(&CampGateHook),&unusedCampGate,6},
        {0x5b834d4,"0f2fc877528b47083b4500",reinterpret_cast<void*>(&NearestCoastHook),&unusedNearestCoast,5},
        // FCFortification_HandleIdleWaitAttacks receives the current CModel.
        // The assembly entry wrapper preserves every volatile argument/register.
        {0x5b914c0,"405556488dac2438ffffff4881ecc8010000",reinterpret_cast<void*>(&AttackTickHook),&attackTickOriginal,0},
        // bKeepDiscovered read in the Caribbean region cover-timer controller.
        // Override only the read: original region/save/asset flag is untouched.
        {0x5ab9085,"440fb67058498bcde81e890300",reinterpret_cast<void*>(&FogKeepHook),&unusedFogKeep,5},
        // Existing visible -> hidden requests become the original unchanged path.
        // This also catches an already expired timer or a queued cover request.
        {0x5ab9678,"3882900000000f8482020000",reinterpret_cast<void*>(&FogTransitionHook),&unusedFogTransition,6}
    };
    for(auto& h:hooks)if(!Fingerprint(base+h.rva,h.bytes)){error="CodeMismatch";return;}
    if(!Fingerprint(base+0x5b83360,"48895c242055574155415641574883ec70")||
       !Fingerprint(base+0x5b83040,"40555356415441554157488dac24e8feffff")) {error="AttackRefreshCodeMismatch";return;}
    if(!Fingerprint(base+0x5cddd30,"48895c241848896c2420565741564883ec20") ||
       !Fingerprint(base+0x5cdd260,"4c8bdc415641574883ec68") ||
       !Fingerprint(base+0x5affa90,"40534883ec20488bd9e8a29a1a003c02")) {error="BattleHelperCodeMismatch";return;}
    if(!Fingerprint(base+0x5dbd240,"40574883ec30488b82e8020000488bf9")){error="CampRadiusCodeMismatch";return;}
    if(!Fingerprint(base+0x5e5e3d0,"4883ec284885c9750733c04883c428c3")||
       !Fingerprint(base+0x5c84490,"4883b9c801000000751b")||
       !Fingerprint(base+0x5c84470,"488b81d80100004885c0740c")){error="HousingTooltipCodeMismatch";return;}
    housingTooltip.modelForWorld=reinterpret_cast<HousingModelFn>(base+0x5e5e3d0);
    if(!Fingerprint(base+0x169f4e0,"448b49044585c974448b0185c0783e")){error="WarehouseHelperCodeMismatch";return;}
    warehouseState.resolveAsset=reinterpret_cast<WarehouseResolveFn>(base+0x169f4e0);
    housingTooltip.operational=reinterpret_cast<HousingEligibilityFn>(base+0x5c84490);
    housingTooltip.excluded=reinterpret_cast<HousingEligibilityFn>(base+0x5c84470);
    setCampRadius=reinterpret_cast<SetCampRadiusFn>(base+0x5dbd240);
    battleStatSource=reinterpret_cast<BattleTagFn>(base+0x5cddd30);
    battleStatType=reinterpret_cast<BattleTagFn>(base+0x5cdd260);
    battleEncounterActive=reinterpret_cast<BattleEncounterFn>(base+0x5affa90);
    const auto init=MH_Initialize();
    if(init!=MH_OK && init!=MH_ERROR_ALREADY_INITIALIZED){error="HookInitFailed";return;}
    stepResume=base+0x5d04dc2;durationResume=base+0x5cfda7e;
    shipResume=base+0x5d6194f;
    campHousingResume=base+0x5db0863;
    campHousingPendingResume=base+0x5db0923;
    remainingResume=base+0x5cff4b7;visualResume=base+0x5ad93b1;visualTimeResume=base+0x5ad9425;
    planResume=base+0x5b4f246;arrivalResume=base+0x5b6edc9;
    routeResume=base+0x5b75a46;routeAltResume=base+0x5b75da4;
    locomotionDefaultResume=base+0x5ab02b4;locomotionOverrideResume=base+0x5ab02e2;
    locomotionIndexedDefaultResume=base+0x5ab0d27;locomotionIndexedOverrideResume=base+0x5ab0d55;
    constructionResume=base+0x5c8ee8a;
    campGateContinue=base+0x5d27b54;campGateReject=base+0x5d27b0a;
    nearestCoastAccept=base+0x5b834d9;nearestCoastReject=base+0x5b8352b;
    fogKeepResume=base+0x5ab908a;fogTransitionResume=base+0x5ab967e;
    updateAttackCamps=reinterpret_cast<AttackPointFn>(base+0x5b83360);
    updateAttackTowers=reinterpret_cast<AttackPointFn>(base+0x5b83040);
    for(auto& h:hooks) {
        auto result=MH_CreateHook(base+h.rva,h.replacement,h.original);
        if(result!=MH_OK){error=std::string("CreateHook:")+MH_StatusToString(result);goto failed;}
        ownedHooks.push_back(base+h.rva);
    }
    for(auto address:ownedHooks)if(MH_QueueEnableHook(address)!=MH_OK){error="QueueHookFailed";goto failed;}
    if(MH_ApplyQueued()!=MH_OK){error="EnableHookFailed";goto failed;}
    ready=true;error="";return;
failed:
    // Only our private MinHook instance and addresses are touched.
    for(auto address:ownedHooks){MH_DisableHook(address);MH_RemoveHook(address);}
    ownedHooks.clear();
}
static void Refresh() {
    if(!ready)return;
    std::ifstream in(folder+L"native-request.ini",std::ios::binary);
    std::string raw((std::istreambuf_iterator<char>(in)),std::istreambuf_iterator<char>());
    if(raw.empty()||raw.size()>1024){error="NativeRequestMissing";return;}
    std::map<std::string,std::string> values;std::istringstream lines(raw);std::string line;
    while(std::getline(lines,line)) {
        if(!line.empty()&&line.back()=='\r')line.pop_back();
        auto split=line.find('=');if(split!=std::string::npos)values[line.substr(0,split)]=line.substr(split+1);
    }
    auto r=values["Revision"];
    if(r.empty()||r.size()>80||r.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=std::string::npos){error="NativeRequestInvalid";return;}
    try {
        const auto& housingText=values.at("CampHousingSteps");
        if(housingText.empty()||housingText.find_first_not_of("0123456789")!=std::string::npos)
            throw std::runtime_error("Invalid camp housing");
        const auto housing=std::stoul(housingText);
        if(housing<10||housing>1000)throw std::runtime_error("Invalid camp housing bounds");
        // Missing discovery is normal until this lazily loaded widget exists.
        const auto tooltipIt=values.find("HousingTooltipClassAddress");
        uint64_t tooltipClass=0;
        if(tooltipIt!=values.end()) {
            const auto& text=tooltipIt->second;
            if(text.empty()||text.find_first_not_of("0123456789")!=std::string::npos)
                throw std::runtime_error("Invalid housing tooltip identity");
            tooltipClass=std::stoull(text);
            if(tooltipClass>0x7fffffffffffULL||(tooltipClass&&tooltipClass%8))
                throw std::runtime_error("Invalid housing tooltip address");
        }
        size_t rangeLength=0;
        float radius=std::stof(values.at("CampRadiusFactor"),&rangeLength);
        if(rangeLength!=values.at("CampRadiusFactor").size()||!std::isfinite(radius)||radius<1||radius>500)throw std::runtime_error("Invalid camp radius");
        size_t a=0,c=0,d=0;float walk=std::stof(values.at("TransportFactor"),&a);
        float ships=std::stof(values.at("ShipFactor"),&d);
        LONG battleMask=0,bit=1;
        for(const char* key:{"BattleHullEnabled","BattleCrewEnabled","BattleSuppliesEnabled"}) {
            const auto& flag=values.at(key);
            if(flag!="0"&&flag!="1")throw std::runtime_error("Invalid battle switch");
            if(flag=="1")battleMask|=bit;
            bit<<=1;
        }
        float construction=std::stof(values.at("ConstructionFactor"),&c);
        const auto& workerText=values.at("WorkerMovementAddress");
        if(workerText.empty()||workerText.find_first_not_of("0123456789")!=std::string::npos)
            throw std::runtime_error("Invalid worker identity");
        const auto worker=std::stoull(workerText);
        if(worker>0x7fffffffffffULL || (walk>1 && !worker))
            throw std::runtime_error("Worker identity unavailable");
        const auto overlap=values.at("CampOverlapEnabled");
        if(overlap!="0" && overlap!="1")throw std::runtime_error("Invalid overlap switch");
        const auto keepRevealed=values.at("KeepRevealedEnabled");
        if(keepRevealed!="0"&&keepRevealed!="1")throw std::runtime_error("Invalid fog switch");
        const auto attackEnabled=values.at("NearestCoastEnabled");
        const auto& tokenText=values.at("AttackRefreshToken");
        if((attackEnabled!="0"&&attackEnabled!="1")||tokenText.empty()||
           tokenText.find_first_not_of("0123456789")!=std::string::npos)
            throw std::runtime_error("Invalid attack configuration");
        const auto token=std::stoul(tokenText);
        if(token<1||token>2147483647)throw std::runtime_error("Invalid attack bounds");
        if(a!=values.at("TransportFactor").size()||
           d!=values.at("ShipFactor").size()||!std::isfinite(ships)||ships<1||ships>10||
           c!=values.at("ConstructionFactor").size()||!std::isfinite(construction)||construction<1||construction>20||
           !std::isfinite(walk)||walk<1||walk>10)
            throw std::runtime_error("Invalid factors");
        // Refresh and the game calculations run on the game thread. Aligned float
        // stores also make the read-only visual stub's loads indivisible on x64.
        unsigned warehouseTypes=3,warehouseBase=15;uint64_t warehouseAsset=0;
        const char* warehouseKeys[]={"WarehouseTypes","WarehouseBaseSlots","WarehouseAssetAddress"};
        uint64_t parsedWarehouse[]={3,15,0};
        for(int i=0;i<3;++i) {
            auto it=values.find(warehouseKeys[i]);
            if(it==values.end())continue;
            const auto& text=it->second;
            if(text.empty()||text.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid warehouse settings");
            parsedWarehouse[i]=std::stoull(text);
        }
        if((parsedWarehouse[0]!=3&&parsedWarehouse[0]!=6&&parsedWarehouse[0]!=9)||parsedWarehouse[1]<1||parsedWarehouse[1]>4096||
           parsedWarehouse[2]>0x7fffffffffffULL||(parsedWarehouse[2]&&parsedWarehouse[2]%8))throw std::runtime_error("Invalid warehouse bounds");
        warehouseTypes=unsigned(parsedWarehouse[0]);warehouseBase=unsigned(parsedWarehouse[1]);warehouseAsset=parsedWarehouse[2];
        warehouseState.Configure(warehouseTypes,warehouseBase,warehouseAsset);
        campRadius.Configure(radius);
        campHousingSteps=housing;
        housingTooltip.classAddress=tooltipClass;
        walkMultiplier=walk;InterlockedExchange(&battleProtectionMask,battleMask);constructionMultiplier=construction;shipMultiplier=ships;
        workerMovementAddress=worker;locomotionMultiplier=walk;
        campOverlapEnabled=overlap=="1"?1:0;revision=r;error="";
        if(!attackRefresh.requested||nearestCoastEnabled!=(attackEnabled=="1"?1:0)||attackRefreshToken!=token)
            attackRefresh.Invalidate();
        nearestCoastEnabled=attackEnabled=="1"?1:0;attackRefreshToken=token;
        keepRevealedEnabled=keepRevealed=="1"?1:0;
    }catch(...){error="NativeRequestInvalid";}
}
extern "C" __declspec(dllexport) int CoveQoL_Initialize(void*) {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    try {if(!attempted)Initialize();if(!folder.empty())Status();}catch(...){error="NativeInitializationException";}
    return 0;
}
extern "C" __declspec(dllexport) int CoveQoL_Refresh(void*) {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    try {Refresh();if(!folder.empty())Status();}catch(...){error="NativeRefreshException";}
    return 0;
}
