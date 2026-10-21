extern "C" void GameFogKeepFixture(),GameFogTransitionFixture();
extern "C" unsigned TestPatchedFogKeep(void*);
extern "C" unsigned TestPatchedFogTransition(void*,unsigned char);
static void RunFogTests() {
    Require(MH_Initialize()==MH_OK,"Fog fixture initializes private hooks");
    void *originalKeep=nullptr,*originalTransition=nullptr;
    auto keep=reinterpret_cast<unsigned char*>(&GameFogKeepFixture);
    auto transition=reinterpret_cast<unsigned char*>(&GameFogTransitionFixture);
    Require(Fingerprint(keep,"440fb67058"),"Fog keep fixture matches complete audited MOVZX");
    Require(Fingerprint(transition,"3882900000000f8482020000"),"Fog visibility fixture matches original CMP/JE and target distance");
    fogKeepResume=keep+5;fogTransitionResume=transition+6;
    Require(MH_CreateHook(keep,reinterpret_cast<void*>(&FogKeepHook),&originalKeep)==MH_OK&&MH_EnableHook(keep)==MH_OK,
        "Actual keep-discovered hook activated in test process");
    Require(MH_CreateHook(transition,reinterpret_cast<void*>(&FogTransitionHook),&originalTransition)==MH_OK&&MH_EnableHook(transition)==MH_OK,
        "Actual region visibility hook activated in test process");
    std::array<unsigned char,0xb0> region{};
    keepRevealedEnabled=0;
    Require(TestPatchedFogKeep(region.data())==0x100,"Disabled keep read retains false and incoming carry flag");
    region[0x58]=1;
    Require(TestPatchedFogKeep(region.data())==0x101,"Original permanently discovered flag retained");
    region[0x58]=0;keepRevealedEnabled=1;
    Require(TestPatchedFogKeep(region.data())==0x101&&region[0x58]==0,"Enabled keep read stops original timer without changing persistent flag");
    Require(region[0x90]==0,"Reading keep flag never discovers an unknown region");
    region[0x58]=1;
    Require(TestPatchedFogKeep(region.data())==0x101,"Enabled mode preserves originally permanent regions");
    Require(fogKeepChecks==4&&fogKeepOverrides==1,"Keep diagnostics distinguish natural and overridden flags");

    Require(TestPatchedFogTransition(region.data(),0)==0&&region[0x91]==0,"Unknown region stays hidden with no visibility notification");
    Require(TestPatchedFogTransition(region.data(),1)==1&&region[0x91]==1,"Normal discovery still reveals region and performs original side effects");
    Require(TestPatchedFogTransition(region.data(),1)==1&&region[0x91]==1,"Already visible discovery does not duplicate rewards or notifications");
    Require(TestPatchedFogTransition(region.data(),0)==1&&region[0x91]==1,"Queued or expired-timer cover takes unchanged path without hiding or notification");
    // Simulate save/load by reconstructing the live region from saved bytes.
    auto loaded=region;
    Require(TestPatchedFogTransition(loaded.data(),0)==1&&loaded[0x91]==1,"Loaded visible region is protected without cached object identity");
    std::array<unsigned char,0xb0> hiddenBeforeActivation{};
    Require(TestPatchedFogTransition(hiddenBeforeActivation.data(),0)==0,"Previously covered region is not automatically rediscovered");
    Require(fogCoversBlocked==2,"Cover counter counts only prevented visible-to-hidden transitions");
    Require(TestPatchedFogTransition(region.data(),2)==2&&region[0x91]==2,"Unknown requested state uses original branch");
    Require(TestPatchedFogTransition(region.data(),0)==0&&region[0x91]==3,"Unknown old state is not treated as discovered");
    keepRevealedEnabled=0;region[0x90]=1;region[0x58]=0;
    Require(TestPatchedFogTransition(region.data(),0)==0&&region[0x91]==4,"Disabling immediately restores original cover transition");
    Require(TestPatchedFogKeep(region.data())==0x100,"Disabling restores original timer-policy read");
    region[0x58]=1;
    Require(TestPatchedFogKeep(region.data())==0x101,"Disabling retains vanilla permanently discovered regions");
    keepRevealedEnabled=1;region[0x58]=0;region[0x90]=1;
    Require(MH_DisableHook(keep)==MH_OK&&TestPatchedFogKeep(region.data())==0x100,"Removing keep hook restores original code");
    Require(MH_DisableHook(transition)==MH_OK&&TestPatchedFogTransition(region.data(),0)==0,"Removing visibility hook restores original code");
    MH_RemoveHook(keep);MH_RemoveHook(transition);MH_Uninitialize();
    keepRevealedEnabled=0;
}
static void TestFogConfiguration() {
    const auto generation=attackRefresh.requested;
    auto request=[](const char* value,const char* rev,int walk=5) {
        std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";
        f<<"ShipFactor=1\n"<<"Revision="<<rev<<"\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor="<<walk<<"\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\nNearestCoastEnabled=0\nAttackRefreshToken=2\n";
        if(value)f<<"KeepRevealedEnabled="<<value<<"\n";
    };
    request("1","fog-on");Refresh();
    Require(keepRevealedEnabled==1&&error.empty()&&revision=="fog-on","Native fog option accepts validated enabled revision");
    Require(walkMultiplier==5&&constructionMultiplier==1&&nearestCoastEnabled==0&&attackRefresh.requested==generation,
        "Fog switch independent of other features and coastal cache refresh");
    for(const char* invalid:{"2","true","nan","-1","1junk",""}) {
        request(invalid,"bad-fog",2);Refresh();
        Require(keepRevealedEnabled==1&&walkMultiplier==5&&revision=="fog-on"&&error=="NativeRequestInvalid",
            "Malformed fog option rejects entire request without partial feature changes");
    }
    request(nullptr,"missing-fog",2);Refresh();
    Require(keepRevealedEnabled==1&&walkMultiplier==5&&revision=="fog-on"&&error=="NativeRequestInvalid","Missing native fog field rejected atomically");
    request("0","fog-off");Refresh();Status();
    Require(keepRevealedEnabled==0&&error.empty()&&revision=="fog-off","Native fog option can be disabled independently");
    std::ifstream f(folder+L"native-status.ini");std::string status((std::istreambuf_iterator<char>(f)),{});
    Require(status.find("KeepRevealedEnabled=0\n")!=std::string::npos&&status.find("FogCoversBlocked=2\n")!=std::string::npos,
        "Native status exports actual fog switch and prevented transition count");
}
