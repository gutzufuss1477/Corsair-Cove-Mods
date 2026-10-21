extern "C" bool GameBattleStatFixture(void*,const void*,int);
extern "C" bool GameBattleSupplyFixture(void*,void*,int,bool);
struct BattleTag {unsigned char source,kind;};
static unsigned char FakeBattleSource(const void* p){return static_cast<const BattleTag*>(p)->source;}
static unsigned char FakeBattleType(const void* p){return static_cast<const BattleTag*>(p)->kind;}
static bool FakeEncounterActive(const void* p){return *static_cast<const bool*>(p);}
static int statForwarded=0,statCalls=0,supplyForwarded=0,supplyCalls=0;
static void *supplyContext=nullptr,*supplyEvent=nullptr;
static bool supplyPlayer=false;
extern "C" bool FakeBattleStat(void* p,const void* raw,int value) {
    ++statCalls;statForwarded=value;
    auto tag=static_cast<const BattleTag*>(raw);
    if(tag->source>1||tag->kind>=3)return false;
    auto pair=reinterpret_cast<int*>(static_cast<unsigned char*>(p)+(tag->source?0x84:0x2c)+tag->kind*8);
    pair[1]=std::max(0,std::min(pair[0],value));return true;
}
extern "C" bool FakeBattleSupply(void* context,void* event,int amount,bool player) {
    ++supplyCalls;supplyContext=context;supplyEvent=event;supplyForwarded=amount;supplyPlayer=player;
    return amount>=0;
}
static void RunBattleTests() {
    Require(MH_Initialize()==MH_OK,"Battle test hook engine initialized");
    auto stat=reinterpret_cast<unsigned char*>(&GameBattleStatFixture);
    auto supply=reinterpret_cast<unsigned char*>(&GameBattleSupplyFixture);
    Require(Fingerprint(stat,"48895c240848896c24104889742418574883ec20"),"Battle stat fixture matches audited prologue");
    Require(Fingerprint(supply,"48895c240848896c2410488974241848897c2420"),"Supply fixture matches audited prologue");
    Require(MH_CreateHook(stat,reinterpret_cast<void*>(&BattleStatHook),reinterpret_cast<void**>(&battleStatOriginal))==MH_OK&&
        MH_CreateHook(supply,reinterpret_cast<void*>(&BattleSupplyHook),reinterpret_cast<void**>(&battleSupplyOriginal))==MH_OK,
        "Battle wrappers have real test-process trampolines");
    Require(MH_EnableHook(stat)==MH_OK&&MH_EnableHook(supply)==MH_OK,"Battle fixtures enabled");
    battleStatSource=FakeBattleSource;battleStatType=FakeBattleType;battleEncounterActive=FakeEncounterActive;
    for(LONG mask=0;mask<8;++mask)for(unsigned source:{0u,1u,2u,3u})for(unsigned kind:{0u,1u,2u,3u,8u,9u})for(int value:{-10,0,5,20,23,30}) {
        battleProtectionMask=mask;BattleTag tag={static_cast<unsigned char>(source),static_cast<unsigned char>(kind)};
        std::vector<unsigned char> stats(0x470,0);
        for(size_t base:{size_t(0x2c),size_t(0x84)})for(size_t i=0;i<3;++i) {
            auto pair=reinterpret_cast<int*>(stats.data()+base+i*8);pair[0]=25;pair[1]=20;
        }
        const auto before=stats;
        const int expected=source==0&&kind<3&&(mask&(1L<<kind))?std::max(20,value):value;
        const int calls=statCalls;
        const bool valid=source<2&&kind<3;
        Require(GameBattleStatFixture(stats.data(),&tag,value)==valid,"Original stat result forwarded");
        Require(statCalls==calls+1&&statForwarded==expected,"Only the individually selected player stats are protected for every switch combination");
        auto wanted=before;
        if(valid)*reinterpret_cast<int*>(wanted.data()+(source?0x84:0x2c)+kind*8+4)=std::max(0,std::min(25,expected));
        Require(stats==wanted,"Enemy damage, gains, maxima and unrelated data retain original semantics");
    }
    for(LONG mask=0;mask<8;++mask)for(bool player:{false,true})for(bool active:{false,true})for(int amount:{-5,0,1,50}) {
        battleProtectionMask=mask;int context=11;bool event=active;
        const int expected=(mask&4)&&player&&active&&amount>0?0:amount;int calls=supplyCalls;
        Require(GameBattleSupplyFixture(&context,&event,amount,player)==(expected>=0),"Supply result remains original");
        Require(supplyCalls==calls+1&&supplyForwarded==expected&&supplyContext==&context&&supplyEvent==&event&&supplyPlayer==player,
            "Supply ABI forwards all arguments; outside encounters, enemy and non-positive costs unchanged");
    }
    battleProtectionMask=7;
    bool active=true;battleEncounterActive=nullptr;
    Require(GameBattleSupplyFixture(nullptr,&active,7,true)&&supplyForwarded==7,"Missing encounter predicate cannot suppress a cost");
    battleEncounterActive=FakeEncounterActive;
    Require(GameBattleSupplyFixture(nullptr,nullptr,7,true)&&supplyForwarded==7,"Missing encounter does not suppress a cost or call the predicate");
    Require(MH_DisableHook(supply)==MH_OK&&GameBattleSupplyFixture(nullptr,nullptr,7,true)&&supplyForwarded==7,
        "Removing protection restores supply loss");
    Require(MH_DisableHook(stat)==MH_OK,"Stat fixture hook removed");
    std::vector<unsigned char> stats(0x470,0);*reinterpret_cast<int*>(stats.data()+0x2c)=25;BattleTag tag={0,0};
    Require(GameBattleStatFixture(stats.data(),&tag,4)&&statForwarded==4,"Removing protection restores player stat loss");
    MH_RemoveHook(stat);MH_RemoveHook(supply);
    MH_Uninitialize();battleProtectionMask=0;
}
static void TestBattleConfiguration() {
    auto request=[](const char* hull,const char* crew,const char* supplies,const char* rev) {
        std::ofstream f(folder+L"native-request.ini");
        f<<"Revision="<<rev<<"\nWorkerMovementAddress=2\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nShipFactor=2\nConstructionFactor=3\n"
            "CampOverlapEnabled=0\nNearestCoastEnabled=0\nAttackRefreshToken=2\nKeepRevealedEnabled=0\n";
        if(hull)f<<"BattleHullEnabled="<<hull<<"\n";
        if(crew)f<<"BattleCrewEnabled="<<crew<<"\n";
        if(supplies)f<<"BattleSuppliesEnabled="<<supplies<<"\n";
    };
    for(LONG mask=0;mask<8;++mask) {
        request(mask&1?"1":"0",mask&2?"1":"0",mask&4?"1":"0","battle-combination");Refresh();Status();
        Require(error.empty()&&battleProtectionMask==mask&&walkMultiplier==5&&shipMultiplier==2&&constructionMultiplier==3,"Every battle switch combination applies independently");
        std::ifstream f(folder+L"native-status.ini");std::string raw((std::istreambuf_iterator<char>(f)),{});
        Require(raw.find(std::string("BattleHullEnabled=")+(mask&1?"1":"0"))!=std::string::npos&&
            raw.find(std::string("BattleCrewEnabled=")+(mask&2?"1":"0"))!=std::string::npos&&
            raw.find(std::string("BattleSuppliesEnabled=")+(mask&4?"1":"0"))!=std::string::npos,"Status confirms all three actual native switches");
    }
    request("1","0","1","battle-on");Refresh();
    for(int key=0;key<3;++key)for(const char* bad:{"2","-1","true","1junk","",static_cast<const char*>(nullptr)}) {
        const char* flags[]={"0","1","0"};flags[key]=bad;
        request(flags[0],flags[1],flags[2],"bad-battle");Refresh();
        Require(error=="NativeRequestInvalid"&&revision=="battle-on"&&battleProtectionMask==5,"Any invalid or missing battle flag retains all three previous switches atomically");
    }
    request("0","0","0","battle-off");Refresh();Status();
    Require(error.empty()&&battleProtectionMask==0&&revision=="battle-off","Protection can be disabled without resetting speed");
    std::ifstream f(folder+L"native-status.ini");std::string text((std::istreambuf_iterator<char>(f)),{});
    Require(text.find("BattleHullEnabled=0\n")!=std::string::npos&&text.find("BattleStatBlocks=")!=std::string::npos&&text.find("BattleProtectionEnabled")==std::string::npos&&text.find("Carry")==std::string::npos,
        "Status exports protection evidence and no retired cargo fields");
}
