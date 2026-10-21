// Offline regression: execute the real read hooks through MinHook on matching
// instructions in this test executable. Never opens or runs Corsair Cove.
#include <array>
#include <cstring>
extern "C" void CarrierPathX1(),CarrierPathX0(),CarrierGlobalAX0(),CarrierGlobalBX1(),CarrierGlobalSX1(),CarrierGlobalAX1();
struct CarrierReadResult {
    unsigned int xmm[2][4];
    unsigned long long flags,rax,rbx,rsi,expectedFlags;
};
extern "C" void TestCarrierRead(void(*)(),const void*,CarrierReadResult*);
static void RunCarrierTests() {
    struct Site {void(*fixture)();void(*hook)();void** resume;const char* bytes;int skip,lane;};
    Site sites[]={
        {CarrierPathX1,StepHook,&stepResume,"f30f104b08",5,1},
        {CarrierPathX0,DurationHook,&durationResume,"f30f104308",5,0},
        {CarrierPathX1,RemainingHook,&remainingResume,"f30f104b08",5,1},
        {CarrierPathX1,VisualHook,&visualResume,"f30f104b08",5,1},
        {CarrierPathX1,VisualTimeHook,&visualTimeResume,"f30f104b08",5,1},
        {CarrierGlobalAX0,TransportPlanHook,&planResume,"f30f108000030000",8,0},
        {CarrierGlobalBX1,TransportArrivalHook,&arrivalResume,"f30f108b00030000",8,1},
        {CarrierGlobalSX1,TransportRouteHook,&routeResume,"f30f108e00030000",8,1},
        {CarrierGlobalAX1,TransportRouteAltHook,&routeAltResume,"f30f108800030000",8,1}
    };
    std::array<unsigned char,0x310> source{};
    const float base=300;
    memcpy(source.data()+8,&base,4);memcpy(source.data()+0x300,&base,4);
    const auto before=source;
    std::array<std::array<float,4>,9> speeds{};
    const float factors[]={1,2.5f,5,10};
    Require(MH_Initialize()==MH_OK,"Carrier hook engine init");
    for(size_t i=0;i<std::size(sites);++i) {
        auto& s=sites[i];auto address=reinterpret_cast<unsigned char*>(s.fixture);
        void* original=nullptr;*s.resume=address+s.skip;
        Require(Fingerprint(address,s.bytes),"Carrier fixture matches actual speed instruction");
        Require(MH_CreateHook(address,reinterpret_cast<void*>(s.hook),&original)==MH_OK,"Carrier read trampoline");
        Require(MH_EnableHook(address)==MH_OK,"Carrier read hook enabled");
        for(size_t j=0;j<std::size(factors);++j) {
            walkMultiplier=factors[j];CarrierReadResult got{};
            TestCarrierRead(s.fixture,source.data(),&got);
            memcpy(&speeds[i][j],&got.xmm[s.lane][0],4);
            Require(speeds[i][j]==base*factors[j],"Simulation, visible movement and planning use identical effective speed");
            Require(got.xmm[s.lane][1]==0&&got.xmm[s.lane][2]==0&&got.xmm[s.lane][3]==0,"MOVSS upper lanes preserved");
            Require(got.xmm[1-s.lane][0]==0xffffffff&&got.xmm[1-s.lane][3]==0xffffffff,"Unrelated SSE value unchanged");
            Require(got.flags==got.expectedFlags,"Carrier counters preserve all flags");
            auto ptr=reinterpret_cast<unsigned long long>(source.data());
            Require(got.rax==ptr&&got.rbx==ptr&&got.rsi==ptr,"Carrier source registers unchanged");
            Require(source==before,"No global/path writes or repeated scaling");
        }
        for(float bonus:{1.25f,1.5f,2.0f}) {
            const float boosted=base*bonus;
            memcpy(source.data()+8,&boosted,4);memcpy(source.data()+0x300,&boosted,4);
            walkMultiplier=5;CarrierReadResult got{};
            TestCarrierRead(s.fixture,source.data(),&got);
            float effective=0;memcpy(&effective,&got.xmm[s.lane][0],4);
            Require(effective==boosted*5,"Current game bonuses in cached or global speed survive trainer multiplication");
        }
        source=before;
        walkMultiplier=1;CarrierReadResult disabled{},unpatched{};
        TestCarrierRead(s.fixture,source.data(),&disabled);
        Require(MH_DisableHook(address)==MH_OK,"Carrier hook removable in fixture");
        TestCarrierRead(s.fixture,source.data(),&unpatched);
        Require(memcmp(disabled.xmm,unpatched.xmm,sizeof(disabled.xmm))==0,"Disable matches vanilla reads exactly");
        Require(MH_RemoveHook(address)==MH_OK,"Carrier fixture hook removed");
        *s.resume=nullptr;
    }
    Require(MH_Uninitialize()==MH_OK,"Carrier hook engine cleanup");
    // Regression for the reported x5 mismatch: previously simulation completed
    // a 3000-unit leg in 2s while the visible/estimated leg still took 10s.
    for(size_t j=0;j<std::size(factors);++j) {
        const double length=3000,progress=0.4;
        const double simulationDuration=length/speeds[0][j];
        Require(simulationDuration==length/speeds[1][j],"Total time agrees with job movement");
        Require((1-progress)*simulationDuration==(1-progress)*length/speeds[2][j],"Remaining time agrees with progress");
        Require(simulationDuration==length/speeds[3][j]&&simulationDuration==length/speeds[4][j],"Requested carrier speed and transition duration agree with job (actual cap tested separately)");
        for(size_t i=5;i<speeds.size();++i)
            Require(simulationDuration==length/speeds[i][j],"Travel projections do not retain vanilla duration");
    }
    // Exercise a factor change mid-route using actual hook outputs. Progress is
    // retained: only future distance/time changes, and return to x1 is exact.
    double model=0,view=0;
    for(size_t j:{size_t(0),size_t(2),size_t(3),size_t(0)}) {
        model+=0.1*speeds[0][j];view+=0.1*speeds[3][j];
        Require(model==view,"Changing and disabling speed keeps ongoing movement synchronized");
    }
    walkMultiplier=1;walkCalls=visualCalls=visualTimeCalls=transportPlanCalls=0;
}
