extern "C" int GameHousingPopulationFixture(void*,void*);
static void* populationContext=nullptr;
static void* populationAsset=nullptr;
extern "C" int FakeHousingPopulation(void* context,void* asset) {
    populationContext=context;populationAsset=asset;
    return asset?*static_cast<int*>(asset):0;
}
static void* FakeHousingWorld(void* context){return AttackRead<void*>(context,0x20);}
static void* FakeHousingModel(void* world){return world;}
static bool FakeHousingOperational(void* structure){return AttackRead<unsigned char>(structure,0x11)==0;}
static bool FakeHousingExcluded(void* structure){return AttackRead<unsigned char>(structure,0x12)!=0;}
template<class T,size_t N> static void HousingPut(std::array<unsigned char,N>& a,size_t at,T value) {
    std::memcpy(a.data()+at,&value,sizeof(value));
}
static void RunHousingTooltipTests() {
    std::array<unsigned char,0x20d0> model{};
    std::array<unsigned char,0x320> camp{},house{},second{},building{};
    std::array<unsigned char,0x240> data{};
    std::array<unsigned char,0x30> link{},context{},otherContext{};
    std::array<unsigned char,0x188> vtable{};
    unsigned char live=1,dead=0;
    struct Handle{void* object;unsigned char* control;};
    std::array<Handle,4> handles{{{house.data(),&live},{camp.data(),&live},{second.data(),&live},{nullptr,nullptr}}};
    int campBeds=25,houseBeds=308,secondBeds=40,vanillaPopulation=2;
    HousingPut(model,0x20b8,Handle{camp.data(),&live});
    HousingPut(camp,0x2e8,data.data());HousingPut(camp,0x308,&campBeds);
    HousingPut(house,0x308,&houseBeds);
    HousingPut(second,0x2e8,data.data());HousingPut(second,0x308,&secondBeds);
    HousingPut(data,0x190,data.data());HousingPut(data,0x230,handles.data());HousingPut(data,0x238,2);
    HousingPut(vtable,0x180,&FakeHousingWorld);
    HousingPut(context,0,vtable.data());HousingPut(context,0x10,uint64_t(800));HousingPut(context,0x20,model.data());
    otherContext=context;HousingPut(otherContext,0x10,uint64_t(1600));
    const auto originalModel=model;
    const auto originalCamp=camp,originalHouse=house;
    const auto originalData=data;
    Require(MH_Initialize()==MH_OK,"Tooltip fixture initializes hooks in its own process");
    auto site=reinterpret_cast<unsigned char*>(&GameHousingPopulationFixture);
    Require(Fingerprint(site,"48896c241848897c242041564883ec20"),"Tooltip fixture has the exact native population entry prologue");
    Require(MH_CreateHook(site,reinterpret_cast<void*>(&HousingPopulationHook),reinterpret_cast<void**>(&housingPopulationOriginal))==MH_OK&&MH_EnableHook(site)==MH_OK,"Actual selective tooltip hook enabled");
    housingTooltip={};housingTooltip.classAddress=800;
    housingTooltip.modelForWorld=&FakeHousingModel;housingTooltip.operational=&FakeHousingOperational;housingTooltip.excluded=&FakeHousingExcluded;
    auto value=[&](){return GameHousingPopulationFixture(context.data(),&vanillaPopulation);};
    campHousingSteps=100;
    Require(value()==250,"Camp row receives250 beds instead of two resident workers");
    Require(558-value()==308,"Observed558 total splits into308 houses plus250 camp beds");
    campHousingSteps=10;
    Require(value()==25&&333-value()==308,"Disabled factor still displays truthful25 camp beds and308 houses");
    campHousingSteps=200;Require(value()==500,"x20 changes only camp attribution; no cached scaled values");
    campHousingSteps=15;Require(value()==37,"Tooltip rounds the camp exactly like the simulation hook");
    campHousingSteps=100;campBeds=40;Require(value()==400,"Live bonuses/base capacity are read anew");campBeds=25;
    Require(GameHousingPopulationFixture(otherContext.data(),&vanillaPopulation)==2&&populationContext==otherContext.data()&&populationAsset==&vanillaPopulation,"Other widgets receive original population and both arguments unchanged");
    Require(GameHousingPopulationFixture(nullptr,&vanillaPopulation)==2,"Null contexts preserve the population API");
    Require(GameHousingPopulationFixture(context.data(),nullptr)==0,"Null asset preserves original result");
    housingTooltip.classAddress=0;Require(value()==2,"Unresolved class disables the display correction");housingTooltip.classAddress=800;
    HousingPut(data,0x238,3);Require(value()==650,"Multiple eligible camp contributions are summed independently");HousingPut(data,0x238,2);
    camp[0x11]=1;Require(value()==0,"Under-construction camp stays out of built housing");camp[0x11]=0;
    camp[0x12]=1;Require(value()==0,"Original exclusion predicate is retained");camp[0x12]=0;
    handles[1].control=&dead;Require(value()==0,"Invalid handles do not supply housing");handles[1].control=&live;
    HousingPut(data,0x190,static_cast<void*>(nullptr));Require(value()==0,"No WorkerPool matches vanilla zero housing");HousingPut(data,0x190,data.data());
    campBeds=0;Require(value()==0,"Zero capacity stays zero");campBeds=-1;Require(value()==2,"Unknown sentinel uses original UI instead of inventing beds");campBeds=INT_MAX;Require(value()==INT_MAX,"Very large camp capacity saturates safely");campBeds=25;
    HousingPut(data,0x238,-1);Require(value()==2,"Invalid array count falls back safely");HousingPut(data,0x238,2);
    HousingPut(model,0x20b8,Handle{building.data(),&live});HousingPut(building,0x2f8,link.data());HousingPut(link,0x10,Handle{camp.data(),&live});
    Require(value()==250,"Selecting an attached building resolves its connected camp");
    HousingPut(link,0x10,Handle{second.data(),&live});
    HousingPut(model,0x20b8,Handle{second.data(),&live});
    std::array<Handle,1> secondList{{{second.data(),&live}}};
    HousingPut(data,0x230,secondList.data());HousingPut(data,0x238,1);
    Require(value()==400,"Camp switching reads current selection without retaining pointers");
    HousingPut(model,0x20b8,Handle{nullptr,nullptr});Require(value()==2,"Missing selection restores original result");
    HousingPut(model,0x20b8,Handle{camp.data(),&live});HousingPut(data,0x230,handles.data());HousingPut(data,0x238,2);
    const auto updates=housingTooltip.updates;Require(value()==250&&housingTooltip.updates==updates+1&&housingTooltip.lastCampBeds==250,"Status counts actual corrected UI reads");
    Require(model==originalModel&&camp==originalCamp&&house==originalHouse&&data==originalData,"Tooltip leaves model, capacities, housing and save data byte-identical");
    Require(MH_DisableHook(site)==MH_OK&&value()==2,"Removing tooltip hook restores vanilla presentation");
    Require(MH_Uninitialize()==MH_OK,"Tooltip test hook removed cleanly");
    housingTooltip={};housingPopulationOriginal=nullptr;campHousingSteps=10;
}
static void RunHousingTooltipConfigTests() {
    auto write=[&](const std::string& identity,const char* rev) {
        std::ofstream f(folder+L"native-request.ini");
        f<<"Revision="<<rev<<"\nWorkerMovementAddress=2\nTransportFactor=2\nShipFactor=2\nConstructionFactor=2\n"
          "CampRadiusFactor=1\nCampHousingSteps=100\nHousingTooltipClassAddress="<<identity<<"\nCampOverlapEnabled=0\n"
          "NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\n";
        f.close();Refresh();
    };
    write("800","tooltip-good");Require(error.empty()&&housingTooltip.classAddress==800,"Native bridge accepts exact tooltip identity");
    for(const char* bad:{"","-8","801","1.5","NaN","800junk","140737488355328","99999999999999999999999999"}) {
        write(bad,"tooltip-bad");Require(error=="NativeRequestInvalid"&&housingTooltip.classAddress==800&&revision=="tooltip-good","Bad tooltip identities reject the entire request atomically");
    }
    write("0","tooltip-clear");Require(error.empty()&&housingTooltip.classAddress==0,"Unloaded tooltip clears identity");
}
