#include <climits>
extern "C" void GameHousingReadFixture(),GameHousingPendingFixture();
extern "C" void TestPatchedHousingRead(int*,void*,void*,int),TestPatchedHousingPendingRead(int*,void*,void*,int);
extern "C" void TestSkippedHousingRead(void*,void*,void*,int);

static void RunHousingReadTests(bool pending) {
    Require(MH_Initialize()==MH_OK,"Housing fixture initializes private hooks");
    auto site=reinterpret_cast<unsigned char*>(pending?&GameHousingPendingFixture:&GameHousingReadFixture);
    auto reader=pending?&TestPatchedHousingPendingRead:&TestPatchedHousingRead;
    Require(Fingerprint(site,"488b8a0803000003394883c310"),"Housing fixture matches original pointer load, sum and iterator byte for byte");
    std::array<unsigned char,0x320> camp{},house{};
    void* marker=camp.data();std::memcpy(camp.data()+0x2e8,&marker,sizeof(marker));
    std::array<uint64_t,8> vanilla{},result{};
    int beds=25;
    int* capacity=&beds;
    std::memcpy(camp.data()+0x308,&capacity,sizeof(capacity));std::memcpy(house.data()+0x308,&capacity,sizeof(capacity));
    const auto unchangedCamp=camp,unchangedHouse=house;
    reader(&beds,camp.data(),vanilla.data(),35);
    Require(vanilla[0]==60,"Original camp plus existing houses gives 25 + 35 beds");
    if(pending)campHousingPendingResume=site+13;else campHousingResume=site+13;
    void* original=nullptr;
    Require(MH_CreateHook(site,reinterpret_cast<void*>(pending?&CampHousingPendingHook:&CampHousingHook),&original)==MH_OK&&MH_EnableHook(site)==MH_OK,
        "Actual housing hook is enabled in isolated fixture process");
    Require(Fingerprint(site+7,"03394883c310"),"Eligibility skip target and both following instructions remain unmodified");
    TestSkippedHousingRead(site+9,nullptr,result.data(),35);
    Require(result[0]==35&&result[1]==0x123456789abcde10ULL,
        "Original skip branch still bypasses ineligible houses and advances iterator without dereferencing pointers");
    auto read=[&](int capacity,void* structure,int current) {
        beds=capacity;result.fill(0);
        reader(&beds,structure,result.data(),current);
        Require(beds==capacity,"Housing hook never writes persistent capacity");
        Require(result[1]==0x123456789abcde10ULL&&result[2]==0x1122334455667788ULL&&
            result[3]==reinterpret_cast<uint64_t>(structure)&&result[4]==reinterpret_cast<uint64_t>(&beds),
            "Housing hook preserves source registers and advances iterator exactly once");
        Require(result[5]==vanilla[5]&&result[6]==UINT64_MAX&&result[7]==UINT64_MAX,
            "Housing continuation retains original flags and SSE contents");
        return static_cast<int>(result[0]);
    };
    campHousingSteps=10;
    Require(read(25,camp.data(),35)==60,"Disabled/x1 housing follows original sum");
    campHousingSteps=100;
    Require(read(25,camp.data(),35)==285,"x10 changes only camp contribution: 250 + 35");
    Require(read(35,house.data(),250)==285,"Ordinary houses are never multiplied");
    Require(read(25,camp.data(),35)==285,"Repeated reads cannot compound capacity");
    Require(read(40,camp.data(),35)==435,"Current game bonuses and map-derived camp capacity are respected");
    campHousingSteps=15;
    Require(read(25,camp.data(),35)==72,"Fractional multiplier rounds camp beds down, not the house total");
    Require(read(0,camp.data(),35)==35,"Zero-capacity camps gain no invented housing");
    Require(read(-1,camp.data(),35)==34,"Negative/sentinel capacities preserve original calculation");
    campHousingSteps=1000;
    Require(read(25,camp.data(),35)==2535,"Maximum x100 camp factor remains independent of houses");
    Require(read(INT_MAX,camp.data(),35)==INT_MAX,"Very large camp contribution saturates instead of wrapping negative");
    auto loaded=camp;
    Require(read(25,loaded.data(),35)==2535,"New or loaded camp identities work without cached pointers");
    campHousingSteps=10;
    Require(read(25,camp.data(),35)==60,"Turning housing off immediately restores original computed capacity");
    Require(camp==unchangedCamp&&house==unchangedHouse,"Camp and house structures are byte-identical after all toggles");
    Require(MH_DisableHook(site)==MH_OK,"Housing hook can be removed cleanly");
    campHousingSteps=100;
    Require(read(25,camp.data(),35)==60,"Removing the hook restores vanilla calculation even with an enabled factor");
    Require(MH_Uninitialize()==MH_OK,"Housing fixture tears down private MinHook state");
    campHousingSteps=10;campHousingResume=nullptr;campHousingPendingResume=nullptr;
}

static void RunHousingTests() {RunHousingReadTests(false);RunHousingReadTests(true);}

static void RunHousingConfigTests() {
    auto request=[&](const std::string& steps,const std::string& rev) {
        std::ofstream f(folder+L"native-request.ini");
        f<<"Revision="<<rev<<"\nWorkerMovementAddress=2\nTransportFactor=2\nShipFactor=2\nConstructionFactor=2\n"
          "CampRadiusFactor=1\nCampHousingSteps="<<steps<<"\nCampOverlapEnabled=0\nNearestCoastEnabled=0\n"
          "AttackRefreshToken=1\nKeepRevealedEnabled=0\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\n";
        f.close();Refresh();
    };
    request("100","housing-good");
    Require(error.empty()&&campHousingSteps==100&&revision=="housing-good","Native protocol accepts complete housing configuration");
    for(const char* value:{"","9","1001","-10","100.5","NaN","Infinity","100oops","999999999999999999999999999999"}) {
        request(value,"housing-bad");
        Require(error=="NativeRequestInvalid"&&campHousingSteps==100&&revision=="housing-good"&&walkMultiplier==2,
            "Malformed housing request is rejected atomically without changing active settings");
    }
    request("10","housing-off");
    Require(error.empty()&&campHousingSteps==10,"Native protocol restores x1 on disable");
    Status();
    std::ifstream f(folder+L"native-status.ini");std::string status((std::istreambuf_iterator<char>(f)),std::istreambuf_iterator<char>());
    Require(status.find("Version=1.2.5\n")!=std::string::npos&&status.find("CampHousingSteps=10\n")!=std::string::npos,
        "Native status acknowledges both new version and actual housing setting");
}
