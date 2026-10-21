#include <array>
extern "C" void GameNearestCoastFixture();
extern "C" void NearestCoastFixtureAccept();
extern "C" void NearestCoastFixtureReject();
extern "C" bool TestPatchedNearestCoast(void*,void*,const void*,float,float);
extern "C" void TestNearestCoastRegisters(void*,void*,const void*);
extern "C" void CaptureNearestCoastRegisters();
extern "C" int GameAttackTickFixture(void*);
extern "C" void CaptureAttackTickRegisters();
extern "C" void TestAttackTickRegisters(void*);
template<class T> static void AttackWrite(void* p,size_t off,T v) {
    std::memcpy(static_cast<unsigned char*>(p)+off,&v,sizeof(v));
}
static int campRefreshCalls=0,towerRefreshCalls=0;
static std::vector<void*> refreshOrder;
static void FakeAttackCamps(void* model,void* point) {
    ++campRefreshCalls;refreshOrder.push_back(point);
    // One synthetic camp at (0,0). Real handle/refcount behavior stays in game.
    const double campXY[]={0,0};
    const double distance=AttackRead<double>(point,0x70);
    const bool inRange=nearestCoastEnabled?NearestCoast(model,point,campXY):distance<=150000;
    AttackWrite<int>(point,0xb8,inRange?1:0);
}
static void FakeAttackTowers(void*,void* point) {
    ++towerRefreshCalls;
    Require(!refreshOrder.empty()&&refreshOrder.back()==point,"Tower coverage refreshed after camp membership");
    AttackWrite<int>(point,0xa8,AttackRead<int>(point,0xb8));
}
static void RunAttackTests() {
    Require(MH_Initialize()==MH_OK,"Attack test hook engine initializes");
    std::array<unsigned char,0x3ca0> model{};
    std::array<unsigned char,0xf0> nearPoint{},farPoint{};
    unsigned char live=1;
    struct Handle {void* point;void* control;};
    Handle points[]={{nearPoint.data(),&live},{farPoint.data(),&live}};
    AttackWrite<void*>(model.data(),0x3bd0,points);
    AttackWrite<int>(model.data(),0x3bd8,2);AttackWrite<int>(model.data(),0x3bdc,2);
    AttackWrite<double>(nearPoint.data(),0x70,5000);AttackWrite<double>(farPoint.data(),0x70,50000);
    double campXY[]={0,0};
    Require(NearestCoast(model.data(),nearPoint.data(),campXY)&&!NearestCoast(model.data(),farPoint.data(),campXY),
        "One nearest coastal point selected for camp");
    double secondCamp[]={49000,0},sharedCamp[]={1000,0};
    Require(NearestCoast(model.data(),farPoint.data(),secondCamp),"Second camp can open its own nearest coast");
    Require(NearestCoast(model.data(),nearPoint.data(),sharedCamp),"Two camps may share one coastal attack point");
    AttackWrite<double>(farPoint.data(),0x70,-5000);
    Require(NearestCoast(model.data(),nearPoint.data(),campXY)&&!NearestCoast(model.data(),farPoint.data(),campXY),
        "Equal distance keeps only first point in stable engine order");
    AttackWrite<double>(farPoint.data(),0x70,5000);
    Require(!NearestCoast(model.data(),farPoint.data(),campXY),"Coincident separate points still have a single winner");
    AttackWrite<double>(nearPoint.data(),0x78,10000);
    Require(NearestCoast(model.data(),farPoint.data(),campXY),"XY distance includes the Y coordinate");
    AttackWrite<double>(nearPoint.data(),0x78,0);
    AttackWrite<double>(farPoint.data(),0x70,50000);
    campXY[0]=std::numeric_limits<double>::quiet_NaN();
    Require(!NearestCoast(model.data(),nearPoint.data(),campXY),"Non-finite camp coordinates have no candidate");
    campXY[0]=0;
    AttackWrite<double>(nearPoint.data(),0x70,std::numeric_limits<double>::infinity());
    Require(NearestCoast(model.data(),farPoint.data(),campXY),"Non-finite coast coordinates excluded");
    AttackWrite<double>(nearPoint.data(),0x70,5000);
    live=0;Require(!NearestCoast(model.data(),nearPoint.data(),campXY),"Invalid point handles never selected");live=1;
    AttackWrite<int>(model.data(),0x3bd8,0);
    Require(!NearestCoast(model.data(),nearPoint.data(),campXY),"Empty coast never grants blanket eligibility");
    AttackWrite<int>(model.data(),0x3bd8,9000);
    Require(!NearestCoast(model.data(),nearPoint.data(),campXY),"Invalid coast count bounded before traversal");
    AttackWrite<int>(model.data(),0x3bd8,2);
    std::array<unsigned char,0xf0> outsider{};
    Require(!NearestCoast(model.data(),outsider.data(),campXY),"Point outside current model cannot be selected");

    void* original=nullptr;
    auto gateFixture=reinterpret_cast<unsigned char*>(&GameNearestCoastFixture);
    Require(Fingerprint(gateFixture,"0f2fc87752"),"Coastal gate fixture matches exact audited comparison and short branch");
    nearestCoastAccept=reinterpret_cast<void*>(&NearestCoastFixtureAccept);
    nearestCoastReject=reinterpret_cast<void*>(&NearestCoastFixtureReject);
    Require(MH_CreateHook(gateFixture,reinterpret_cast<void*>(&NearestCoastHook),&original)==MH_OK&&MH_EnableHook(gateFixture)==MH_OK,
        "Real five-byte coastal selection hook activated");
    nearestCoastEnabled=1;
    Require(TestPatchedNearestCoast(model.data(),nearPoint.data(),campXY,1,25000000),
        "Nearest point accepted even beyond original radius");
    Require(!TestPatchedNearestCoast(model.data(),farPoint.data(),campXY,150000.0f*150000,50000.0f*50000),
        "Farther point rejected inside expanded build radius");
    Require(TestPatchedNearestCoast(model.data(),farPoint.data(),secondCamp,1,1000000),
        "Real hook forwards model, candidate and per-camp coordinates correctly");
    nearestCoastEnabled=0;
    Require(TestPatchedNearestCoast(model.data(),farPoint.data(),campXY,150000.0f*150000,50000.0f*50000),
        "Disabled gate restores original island-wide radius membership");
    Require(!TestPatchedNearestCoast(model.data(),nearPoint.data(),campXY,1,25000000),
        "Disabled gate restores original out-of-radius rejection");
    Require(TestPatchedNearestCoast(model.data(),nearPoint.data(),campXY,25000000,25000000),
        "Original comparison includes exact radius boundary");
    Require(nearestCoastChecks==6&&nearestCoastSelected==2,"Gate counters distinguish enabled selections");
    nearestCoastEnabled=1;
    Require(MH_DisableHook(gateFixture)==MH_OK&&TestPatchedNearestCoast(model.data(),farPoint.data(),campXY,150000.0f*150000,50000.0f*50000),
        "Removing coastal gate restores original comparison");
    MH_RemoveHook(gateFixture);
    nearestCoastAccept=nearestCoastReject=reinterpret_cast<void*>(&CaptureNearestCoastRegisters);
    for(auto candidate:{nearPoint.data(),farPoint.data()}) {
        TestNearestCoastRegisters(model.data(),candidate,campXY);
        const uint64_t registers[]={0x11,reinterpret_cast<uint64_t>(campXY),0x22,0x33,0x44,0x55,0x66};
        for(int i=0;i<7;++i)Require(AttackRead<uint64_t>(model.data(),i*8)==registers[i],
            "Nearest gate preserves every volatile GPR on accept and reject");
        for(int i=0;i<6;++i)Require(AttackRead<uint32_t>(model.data(),64+i*16)==static_cast<uint32_t>(i+1)&&
            AttackRead<uint64_t>(model.data(),72+i*16)==0,"Nearest gate preserves all six volatile SSE registers");
    }
    const auto modelSnapshot=model;
    const auto nearSnapshot=nearPoint,farSnapshot=farPoint;
    NearestCoast(model.data(),nearPoint.data(),campXY);
    Require(model==modelSnapshot&&nearPoint==nearSnapshot&&farPoint==farSnapshot,
        "Selection helper does not write game state or live attack references");
    // Existing attack/quest references must survive refresh and disabling.
    AttackWrite<uint64_t>(farPoint.data(),0xc0,0x1234);AttackWrite<uint64_t>(farPoint.data(),0xd0,0x5678);
    updateAttackCamps=FakeAttackCamps;updateAttackTowers=FakeAttackTowers;
    attackRefresh=AttackRefreshState{};
    RefreshAttackPoints(model.data());Require(campRefreshCalls==0,"No game access before first validated configuration");
    attackRefresh.Invalidate();Require(attackRefresh.Pending(),"Changed configuration waits for game-thread refresh");
    auto tickFixture=reinterpret_cast<unsigned char*>(&GameAttackTickFixture);
    Require(Fingerprint(tickFixture,"405556488dac2438ffffff4881ecc8010000"),"Attack tick fixture matches complete audited prologue");
    Require(MH_CreateHook(tickFixture,reinterpret_cast<void*>(&AttackTickHook),&attackTickOriginal)==MH_OK&&MH_EnableHook(tickFixture)==MH_OK,
        "Actual attack tick entry and trampoline activated");
    Require(GameAttackTickFixture(model.data())==1&&!attackRefresh.Pending(),"Cached membership rebuilt before original attack tick");
    Require(attackRefresh.points==2&&attackRefresh.eligible==1&&campRefreshCalls==2&&towerRefreshCalls==2,
        "Both camp and dependent tower lists updated for every coast point");
    Require(AttackRead<int>(farPoint.data(),0xb8)==0&&AttackRead<int>(farPoint.data(),0xa8)==0&&model[0x3c90]==1,
        "Distant eligibility removed and fortification invalidation signaled");
    for(int i=0;i<100;++i)GameAttackTickFixture(model.data());
    Require(campRefreshCalls==2&&attackRefresh.refreshes==1,"Idle ticks do not repeat coastal recalculation");
    nearestCoastEnabled=0;attackRefresh.Invalidate();GameAttackTickFixture(model.data());
    Require(attackRefresh.eligible==2&&AttackRead<int>(farPoint.data(),0xb8)==1,"Disable rebuild restores previously excluded points");
    Require(AttackRead<uint64_t>(farPoint.data(),0xc0)==0x1234&&AttackRead<uint64_t>(farPoint.data(),0xd0)==0x5678,
        "Existing scripted attack and fleet references remain unchanged");
    auto before=attackRefresh.refreshes;
    attackRefresh.Invalidate();GameAttackTickFixture(model.data());
    Require(attackRefresh.refreshes==before+1,"Map token forces refresh even when model address is reused");
    AttackWrite<int>(model.data(),0x3bd8,1);GameAttackTickFixture(model.data());
    Require(attackRefresh.points==1,"Changed point array shape rebuilds with live model context");
    attackRefresh.Invalidate();live=0;GameAttackTickFixture(model.data());
    Require(attackRefresh.invalid&&attackRefresh.Pending(),"Invalid handle rejects refresh without acknowledging completion");
    live=1;GameAttackTickFixture(model.data());Require(!attackRefresh.invalid&&!attackRefresh.Pending(),"Refresh recovers on valid lifecycle data");
    AttackWrite<int>(model.data(),0x3bd8,9000);before=attackRefresh.refreshes;RefreshAttackPoints(model.data());
    Require(attackRefresh.invalid&&attackRefresh.refreshes==before,"Unexpected array size never traversed");
    AttackWrite<int>(model.data(),0x3bd8,0);AttackWrite<void*>(model.data(),0x3bd0,nullptr);RefreshAttackPoints(model.data());
    Require(!attackRefresh.invalid&&attackRefresh.points==0&&attackRefresh.eligible==0,"Empty coast preserves normal no-candidate behavior");
    AttackWrite<void*>(model.data(),0x3bd0,points);AttackWrite<int>(model.data(),0x3bd8,2);
    nearestCoastEnabled=1;attackRefresh.Invalidate();GameAttackTickFixture(model.data());
    Require(attackRefresh.eligible==1,"Nearest mode rebuilds to exactly one point for one eligible camp");
    // The game's camp-change paths call the same membership function directly.
    // No cached selection may prevent a changed location/order from taking effect.
    AttackWrite<double>(nearPoint.data(),0x70,60000);
    FakeAttackCamps(model.data(),nearPoint.data());FakeAttackCamps(model.data(),farPoint.data());
    Require(AttackRead<int>(nearPoint.data(),0xb8)==0&&AttackRead<int>(farPoint.data(),0xb8)==1,
        "Engine-driven recomputation sees changed coordinates without stale cached pointers");
    AttackWrite<double>(nearPoint.data(),0x70,5000);
    Require(MH_DisableHook(tickFixture)==MH_OK,"Attack tick hook disabled");MH_RemoveHook(tickFixture);MH_Uninitialize();
    attackTickOriginal=reinterpret_cast<void*>(&CaptureAttackTickRegisters);
    attackRefresh.Invalidate();TestAttackTickRegisters(model.data());
    const uint64_t expected[]={0x11,reinterpret_cast<uint64_t>(model.data()),0x22,0x33,0x44,0x55,0x66};
    for(int i=0;i<7;++i)Require(AttackRead<uint64_t>(model.data(),i*8)==expected[i],"Attack entry preserves every volatile general register");
    Require((AttackRead<uint64_t>(model.data(),56)&1)==1,"Attack entry preserves incoming carry flag");
    for(int i=0;i<6;++i) {
        Require(AttackRead<uint32_t>(model.data(),64+i*16)==static_cast<uint32_t>(i+1)&&AttackRead<uint64_t>(model.data(),72+i*16)==0,
            "Attack entry preserves all six volatile SSE arguments");
    }
    attackRefresh=AttackRefreshState{};updateAttackCamps=updateAttackTowers=nullptr;
    nearestCoastEnabled=0;attackRefreshToken=0;
}
