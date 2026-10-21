extern "C" void GameShipSpeedFixture();
extern "C" float TestPatchedShipSpeed(float,void*);
struct ShipFixtureResult {float speed;unsigned pad;unsigned long long cookie,flags;float source;};
static void RunShipTests() {
    Require(MH_Initialize()==MH_OK,"Ship fixture hook engine init");
    auto fixture=reinterpret_cast<unsigned char*>(&GameShipSpeedFixture);
    Require(Fingerprint(fixture,"0f28c6488b4c2430"),"Ship fixture matches both original return instructions");
    shipResume=fixture+8;void* original=nullptr;
    Require(MH_CreateHook(fixture,reinterpret_cast<void*>(&ShipSpeedHook),&original)==MH_OK&&MH_EnableHook(fixture)==MH_OK,
        "Real ship-speed return hook enabled only in test process");
    for(float factor:{1.0f,1.5f,5.0f,10.0f}) for(float speed:{0.0f,0.125f,24.0f,120.0f}) {
        shipMultiplier=factor;ShipFixtureResult result{};
        const float actual=TestPatchedShipSpeed(speed,&result);
        Require(actual==speed*factor&&result.speed==actual,"Effective ship speed scales without old stat cap 100");
        Require(result.source==speed,"Original calculated ship speed and source register unchanged");
        Require(result.cookie==0x123456789abcdef0ull&&(result.flags&1),"Cookie load, output pointer and incoming carry flag preserved");
    }
    Require(shipCalls==16,"Actual ship hook invocations counted");
    ShipFixtureResult result{};shipMultiplier=10;
    Require(MH_DisableHook(fixture)==MH_OK&&TestPatchedShipSpeed(24,&result)==24,"Removing ship hook restores original result");
    MH_RemoveHook(fixture);MH_Uninitialize();shipMultiplier=1;
}
static void TestShipConfiguration() {
    const auto generation=attackRefresh.requested;
    auto request=[](const char* value,const char* rev) {
        std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";
        f<<"Revision="<<rev<<"\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\nNearestCoastEnabled=0\nAttackRefreshToken=2\nKeepRevealedEnabled=0\n";
        if(value)f<<"ShipFactor="<<value<<"\n";
    };
    request("5.5","ships-on");Refresh();
    Require(shipMultiplier==5.5f&&error.empty()&&revision=="ships-on","Native ship factor accepts decimals");
    Require(walkMultiplier==5&&constructionMultiplier==1&&attackRefresh.requested==generation,
        "Ship control independent of carriers, building and coastal refresh");
    for(const char* bad:{"nan","inf","0","-1","10.1","5junk",""}) {
        request(bad,"bad-ship");Refresh();
        Require(shipMultiplier==5.5f&&revision=="ships-on"&&error=="NativeRequestInvalid","Invalid ship factor retains previous complete configuration");
    }
    request(nullptr,"missing-ship");Refresh();
    Require(shipMultiplier==5.5f&&revision=="ships-on"&&error=="NativeRequestInvalid","Missing native ship factor rejected");
    request("1","ships-off");Refresh();Status();
    Require(shipMultiplier==1&&error.empty()&&revision=="ships-off","Disabled ships restore original calculation");
    std::ifstream f(folder+L"native-status.ini");std::string status((std::istreambuf_iterator<char>(f)),{});
    Require(status.find("ShipFactor=1\n")!=std::string::npos&&status.find("ShipCalls=16\n")!=std::string::npos,
        "Native ship status exports actual factor and calls");
}
