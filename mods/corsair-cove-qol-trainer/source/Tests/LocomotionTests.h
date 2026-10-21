// Exercise the four real final-speed hooks in an isolated process. In addition
// to instruction/ABI checks, model the game's speed-ratio clamp on each path
// type: a boosted job cannot be followed if a nonzero slot retains its cap.
extern "C" void LocomotionDefaultFixture(),LocomotionOverrideFixture();
extern "C" void LocomotionIndexedDefaultFixture(),LocomotionIndexedOverrideFixture();
struct LocomotionResult {
    double speed;unsigned long long upper;
    unsigned long long flags,expectedFlags,rax,rbx,rcx,rdx,r8,r9;
    unsigned long long xmm1[2];
};
extern "C" void TestLocomotionRead(void(*)(),const void*,const void*,LocomotionResult*);
static void RunLocomotionTests() {
    struct Site {void(*fixture)();void(*hook)();void** resume;const char* prefix;int skip;bool overrideValue,indexed;};
    const Site sites[]={
        {LocomotionDefaultFixture,LocomotionDefaultHook,&locomotionDefaultResume,"f20f1004c3488b5c2440",5,false,false},
        {LocomotionOverrideFixture,LocomotionOverrideHook,&locomotionOverrideResume,"f20f1000488b5c2440",9,true,false},
        {LocomotionIndexedDefaultFixture,LocomotionIndexedDefaultHook,&locomotionIndexedDefaultResume,"f20f1004c3488b5c2448",5,false,true},
        {LocomotionIndexedOverrideFixture,LocomotionIndexedOverrideHook,&locomotionIndexedOverrideResume,"f20f1000488b5c2448",9,true,true}
    };
    std::array<double,32> worker{},other{};
    const double caps[]={1000,400,200,600};
    for(size_t i=0;i<4;++i)worker[12+i*2]=other[12+i*2]=caps[i];
    const auto workerBefore=worker,otherBefore=other;
    double overrideSpeed=250;
    workerMovementAddress=reinterpret_cast<unsigned long long>(worker.data());
    Require(MH_Initialize()==MH_OK,"Locomotion fixture hook engine");
    for(const auto& s:sites) {
        auto address=reinterpret_cast<unsigned char*>(s.fixture);void* original=nullptr;
        *s.resume=address+s.skip;
        Require(Fingerprint(address,s.prefix),"Locomotion fixture matches final getter read and epilogue");
        Require(MH_CreateHook(address,reinterpret_cast<void*>(s.hook),&original)==MH_OK,"Locomotion fixture trampoline");
        Require(MH_EnableHook(address)==MH_OK,"Locomotion fixture enabled");
        for(float factor:{1.0f,2.0f,5.0f,10.0f,1.0f})for(size_t network=0;network<4;++network)for(bool isWorker:{true,false}) {
            walkMultiplier=factor;locomotionMultiplier=factor;
            const auto asset=isWorker?worker.data():other.data();
            const auto readArg=s.overrideValue?static_cast<const void*>(&overrideSpeed):reinterpret_cast<const void*>(12+network*2);
            const double vanilla=s.overrideValue?overrideSpeed:caps[network];
            LocomotionResult got{};TestLocomotionRead(s.fixture,asset,readArg,&got);
            Require(got.speed==vanilla*(isWorker?factor:1),"All network types and per-agent overrides scale exactly once for worker only");
            Require(got.upper==0&&got.xmm1[0]==~0ULL&&got.xmm1[1]==~0ULL,"MOVSD upper lane and other SIMD registers preserved");
            Require(got.flags==got.expectedFlags,"Asset filter and counters preserve flags");
            Require(got.rax==reinterpret_cast<unsigned long long>(readArg)&&got.rbx==(s.indexed?0x55667788ULL:0x11223344ULL),"Source and replayed RBX restoration preserved");
            Require(got.rcx==reinterpret_cast<unsigned long long>(s.fixture)&&got.rdx==reinterpret_cast<unsigned long long>(asset)&&
                got.r8==reinterpret_cast<unsigned long long>(readArg)&&got.r9==reinterpret_cast<unsigned long long>(&got),"Argument registers preserved");
            Require(worker==workerBefore&&other==otherBefore&&overrideSpeed==250,"No asset, path or override memory writes");
            if(isWorker) {
                const double desired=vanilla*0.75*factor;
                const double newVisible=got.speed*std::min(1.0,desired/got.speed);
                Require(std::abs(newVisible-desired)<1e-8,"Actual segment cap allows synchronized arrival after ratio clamp");
                if(factor>=2&&network>0&&!s.overrideValue) {
                    const double oldVisible=vanilla*std::min(1.0,desired/vanilla);
                    Require(oldVisible<desired,"Regression reproduces v0.10 nonzero-network lag despite scaled movement input");
                }
            }
        }
        // A perk/upgrade can change the game's current selected value while
        // the trainer is enabled. Read the new value each time, never retain a
        // baseline or erase the bonus when returning to x1.
        for(double bonus:{1.0,1.25,1.5,2.0}) {
            worker[14]=caps[1]*bonus;overrideSpeed=250*bonus;
            auto selected=s.overrideValue?static_cast<void*>(&overrideSpeed):reinterpret_cast<void*>(14);
            const double gameSpeed=s.overrideValue?overrideSpeed:worker[14];
            for(float factor:{5.0f,10.0f,1.0f}) {
                walkMultiplier=factor;locomotionMultiplier=factor;
                LocomotionResult got{};TestLocomotionRead(s.fixture,worker.data(),selected,&got);
                Require(got.speed==gameSpeed*factor,"Existing and newly unlocked bonuses compose multiplicatively with trainer factor");
                Require(worker[14]==caps[1]*bonus&&overrideSpeed==250*bonus,"Disabling trainer preserves current perk-adjusted values");
            }
        }
        worker=workerBefore;overrideSpeed=250;
        // Missing/stale worker identity cannot accelerate unrelated assets.
        workerMovementAddress=0;walkMultiplier=5;locomotionMultiplier=5;
        LocomotionResult missing{};
        TestLocomotionRead(s.fixture,worker.data(),s.overrideValue?static_cast<void*>(&overrideSpeed):reinterpret_cast<void*>(14),&missing);
        Require(missing.speed==(s.overrideValue?overrideSpeed:caps[1]),"Unknown worker identity bypasses native scaling");
        workerMovementAddress=reinterpret_cast<unsigned long long>(worker.data());
        walkMultiplier=1;locomotionMultiplier=1;
        LocomotionResult disabled{},unpatched{};
        const auto readArg=s.overrideValue?static_cast<void*>(&overrideSpeed):reinterpret_cast<void*>(14);
        TestLocomotionRead(s.fixture,worker.data(),readArg,&disabled);
        Require(MH_DisableHook(address)==MH_OK,"Locomotion fixture disabled");
        TestLocomotionRead(s.fixture,worker.data(),readArg,&unpatched);
        Require(disabled.speed==unpatched.speed&&disabled.upper==unpatched.upper&&disabled.flags==unpatched.flags,"Disabled getter exactly matches original");
        Require(MH_RemoveHook(address)==MH_OK,"Locomotion fixture removed");
        *s.resume=nullptr;
    }
    Require(locomotionDefaultCalls>0&&locomotionOverrideCalls>0,"Default and override worker execution diagnostics");
    Require(MH_Uninitialize()==MH_OK,"Locomotion fixture cleanup");
    workerMovementAddress=0;walkMultiplier=1;locomotionMultiplier=1;
    locomotionDefaultCalls=locomotionOverrideCalls=0;
}

static void TestWorkerConfiguration() {
    auto request=[](const char* identity,int factor) {
        std::ofstream f(folder+L"native-request.ini");
        f<<"Revision=worker\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor="<<factor<<"\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nShipFactor=1\nConstructionFactor=1\n"
            "CampOverlapEnabled=0\nNearestCoastEnabled=0\nAttackRefreshToken=2\nKeepRevealedEnabled=0\n";
        if(identity)f<<"WorkerMovementAddress="<<identity<<"\n";
    };
    request("123456789012",5);Refresh();
    Require(error.empty()&&workerMovementAddress==123456789012ULL&&walkMultiplier==5&&locomotionMultiplier==5,"Worker identity and both speed factors accepted together");
    const char* invalidIdentities[]={nullptr,"","-1","+2","2junk","nan","1.5","140737488355328","18446744073709551616","0"};
    for(const char* bad:invalidIdentities) {
        request(bad,2);Refresh();
        Require(error=="NativeRequestInvalid"&&workerMovementAddress==123456789012ULL&&walkMultiplier==5&&locomotionMultiplier==5,"Invalid or missing identity cannot leave simulation and locomotion with different factors");
    }
    request("0",1);Refresh();
    Require(error.empty()&&workerMovementAddress==0&&walkMultiplier==1&&locomotionMultiplier==1,"Unloaded worker may wait safely at vanilla transport speed");
    request("987654321000",2);Refresh();
    Require(error.empty()&&workerMovementAddress==987654321000ULL&&walkMultiplier==2&&locomotionMultiplier==2,"Map-reloaded worker identity replaces old pointer without dereference");
    Status();
    std::ifstream f(folder+L"native-status.ini");std::string status((std::istreambuf_iterator<char>(f)),{});
    Require(status.find("WorkerMovementAddress=987654321000\n")!=std::string::npos&&status.find("LocomotionDefaultCalls=")!=std::string::npos&&
        status.find("LocomotionOverrideCalls=")!=std::string::npos,"Worker identity and both getter counters exported");
}
