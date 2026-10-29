#include "../Native/CoveQoLNative.cpp"
#include <iostream>
extern "C" float TestStep(float),TestDuration(float),TestRemaining(float),TestVisual(float);
extern "C" void GameStepFixture();
extern "C" float TestPatchedStep(float);
extern "C" void GameConstructionFixture();
extern "C" float TestPatchedConstruction(float,float,float,float);
extern "C" bool GameCampRangeFixture(void*,void*,void*);
extern "C" void GameCampGateFixture();
extern "C" bool TestPatchedCampGate(void*,unsigned char*,int);
static int checks=0;
static void Require(bool ok,const char* reason){++checks;if(!ok)throw std::runtime_error(reason);}
#include "AttackTests.h"
#include "FogTests.h"
#include "ShipTests.h"
#include "CarrierTests.h"
#include "LocomotionTests.h"
#include "BattleTests.h"
#include "CampRadiusTests.h"
#include "HousingTests.h"
#include "HousingTooltipTests.h"
#include "WarehouseTests.h"
int main() {
    try {
        // Flush suite names so a native fault still identifies its fixture.
        #define RUN_SUITE(name) do {std::cerr<<#name<<std::endl;name();} while(false)
        RUN_SUITE(RunAttackTests);RUN_SUITE(RunFogTests);RUN_SUITE(RunShipTests);
        RUN_SUITE(RunCarrierTests);RUN_SUITE(RunLocomotionTests);RUN_SUITE(RunBattleTests);
        RUN_SUITE(RunCampRadiusTests);RUN_SUITE(RunHousingTests);
        RUN_SUITE(RunHousingTooltipTests);RUN_SUITE(RunWarehouseTests);
        #undef RUN_SUITE
        for(float mult:{1.0f,2.5f,5.0f,10.0f}) {
            walkMultiplier=mult;
            Require(TestStep(300)==300*mult,"Actual simulation stub");
            Require(TestDuration(300)==300*mult,"Actual duration stub");
            Require(TestRemaining(300)==300*mult,"Actual remaining-time stub");
            Require(TestVisual(300)==300*mult,"Actual visual stub");
        }
        Require(walkCalls==4&&visualCalls==4,"Hook execution counters");
        // Exercise actual thread-safe code patching only inside this test EXE.
        walkMultiplier=5;void* original=nullptr;
        auto fixture=reinterpret_cast<unsigned char*>(&GameStepFixture);
        stepResume=fixture+5;
        Require(MH_Initialize()==MH_OK,"Test hook engine initialization");
        Require(MH_CreateHook(fixture,reinterpret_cast<void*>(&StepHook),&original)==MH_OK,"Real five-byte hook/trampoline");
        Require(MH_EnableHook(fixture)==MH_OK&&TestPatchedStep(300)==1500,"Patched fixture executes multiplier");
        Require(MH_DisableHook(fixture)==MH_OK&&TestPatchedStep(300)==300,"Removing hook restores fixture");
        MH_RemoveHook(fixture);
        auto buildingFixture=reinterpret_cast<unsigned char*>(&GameConstructionFixture);
        Require(Fingerprint(buildingFixture,"f3410f107f08f30f59f0"),"Construction fixture matches original instructions");
        constructionResume=buildingFixture+6;
        Require(MH_CreateHook(buildingFixture,reinterpret_cast<void*>(&ConstructionHook),&original)==MH_OK,
            "Real six-byte construction hook/trampoline");
        Require(MH_EnableHook(buildingFixture)==MH_OK,"Construction fixture hook activated");
        for(float mult:{1.0f,2.5f,5.0f,20.0f}) {
            constructionMultiplier=mult;
            float got=TestPatchedConstruction(0.01f,0.1f,1.0f,1.0f);
            Require(std::abs(got-(0.1f+0.01f*mult))<0.000001f,"Construction scales only newly earned progress");
        }
        Require(constructionCalls==4,"Construction hook execution counter");
        constructionMultiplier=20;
        Require(TestPatchedConstruction(0.01f,0.5f,1.0f,0.55f)==0.55f,"Material progress cap remains effective");
        Require(TestPatchedConstruction(0.01f,0.99f,1.0f,1.0f)==1.0f,"Completion capped at 100 percent");
        Require(TestPatchedConstruction(0.01f,0.5f,0.0f,1.0f)==0.5f,"Zero delta time cannot advance construction");
        Require(TestPatchedConstruction(0.0f,0.5f,1.0f,1.0f)==0.5f,"Zero worker contribution stays zero");
        Require(TestPatchedConstruction(0.01f,0.0f,1.0f,0.0f)==0.0f,"Missing materials cannot be bypassed");
        constructionMultiplier=1;
        float vanilla=TestPatchedConstruction(0.01f,0.3f,0.1f,1.0f);
        Require(MH_DisableHook(buildingFixture)==MH_OK&&TestPatchedConstruction(0.01f,0.3f,0.1f,1.0f)==vanilla,
            "Disabled construction factor exactly matches unpatched calculation");
        MH_RemoveHook(buildingFixture);
        auto campFixture=reinterpret_cast<unsigned char*>(&GameCampRangeFixture);
        Require(Fingerprint(campFixture,"48895c2408574883ec700f29742460"),"Camp range fixture matches audited prologue");
        Require(MH_CreateHook(campFixture,reinterpret_cast<void*>(&CampRangeHook),reinterpret_cast<void**>(&campRangeOriginal))==MH_OK,
            "Camp proximity trampoline created");
        Require(MH_EnableHook(campFixture)==MH_OK,"Camp proximity hook enabled");
        unsigned char yes=1,no=0;
        campOverlapEnabled=0;
        Require(GameCampRangeFixture(&yes,&yes,&yes),"Disabled overlap preserves original rejection");
        campOverlapEnabled=1;
        Require(!GameCampRangeFixture(&yes,&yes,&yes),"Enabled overlap bypasses proximity conflict");
        campOverlapEnabled=0;
        Require(!GameCampRangeFixture(&no,&yes,&yes)&&!GameCampRangeFixture(&yes,&no,&yes)&&!GameCampRangeFixture(&yes,&yes,&no),
            "All three arguments forwarded through real trampoline; no conflict unchanged");
        Require(campOverlapChecks==5&&campOverlapBypasses==1,"Camp proximity counters count only actual bypasses");
        Require(MH_DisableHook(campFixture)==MH_OK&&GameCampRangeFixture(&yes,&yes,&yes),"Unhook restores camp proximity behavior");
        MH_RemoveHook(campFixture);
        auto gateFixture=reinterpret_cast<unsigned char*>(&GameCampGateFixture);
        Require(Fingerprint(gateFixture,"41f60101744a41c60717"),"Second camp fixture matches both branch and rejection bytes");
        campGateContinue=gateFixture+0x50;campGateReject=gateFixture+6;
        Require(MH_CreateHook(gateFixture,reinterpret_cast<void*>(&CampGateHook),&original)==MH_OK,"Second camp gate hook created");
        Require(MH_EnableHook(gateFixture)==MH_OK,"Second camp gate hook enabled");
        struct Handle {unsigned char live,padding;unsigned short refs;};
        for(LONG enabled:{0L,1L})for(unsigned char live:{static_cast<unsigned char>(0),static_cast<unsigned char>(1)})for(int later:{0,22,24}) {
            campOverlapEnabled=enabled;Handle h={live,0,7};unsigned char status=99;
            const bool rejected=live&&!enabled;
            bool result=TestPatchedCampGate(&h,&status,later);
            Require(result==(!rejected&&later==0)&&status==(rejected?23:later),
                "Camp gate only removes overlap error; downstream failures still reject");
            Require(h.refs==6&&h.live==live&&h.padding==0,"Original reference release runs exactly once; handle preserved");
        }
        Require(campOverlapChecks==17&&campOverlapBypasses==4,"Both overlap checks report actual bypasses");
        campOverlapEnabled=1;Handle h={1,0,7};unsigned char placementStatus=99;
        Require(MH_DisableHook(gateFixture)==MH_OK&&!TestPatchedCampGate(&h,&placementStatus,0)&&placementStatus==23&&h.refs==6,
            "Removing second hook restores rejection and reference release");
        MH_RemoveHook(gateFixture);MH_Uninitialize();
        wchar_t temp[MAX_PATH];GetTempPathW(MAX_PATH,temp);
        std::wstring isolated=std::wstring(temp)+L"CoveNativeTests-"+std::to_wstring(GetCurrentProcessId());
        CreateDirectoryW(isolated.c_str(),nullptr);SetEnvironmentVariableW(L"LOCALAPPDATA",isolated.c_str());
        Initialize();
        Require(!ready&&error=="UnsupportedGameBuild"&&ownedHooks.empty(),"Unknown executable never patched");
        ready=true;folder=isolated+L"\\CorsairCoveQoL\\";
        {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nRevision=test\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=2.5\nCampOverlapEnabled=1\n";}
        Refresh();Require(walkMultiplier==5&&constructionMultiplier==2.5f&&revision=="test","Native control revision");
        Require(campOverlapEnabled==1,"Camp overlap toggle accepted with revision");
        for(const char* bad:{"nan","inf","0","20.1","5junk",""}) {
            {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nRevision=bad\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=2\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor="<<bad<<"\nCampOverlapEnabled=0\n";}
            Refresh();Require(walkMultiplier==5&&constructionMultiplier==2.5f&&revision=="test"&&error=="NativeRequestInvalid",
                "Malformed construction request retains all values");
        }
        for(const char* bad:{"", "true", "2", "-1", "1junk"}) {
            {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nRevision=bad\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=2\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled="<<bad<<"\n";}
            Refresh();Require(campOverlapEnabled==1&&walkMultiplier==5&&constructionMultiplier==2.5f&&revision=="test"&&error=="NativeRequestInvalid",
                "Invalid overlap toggle retains whole previous configuration");
        }
        {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nRevision=bad\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=nan\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\n";}
        Refresh();Require(walkMultiplier==5&&constructionMultiplier==2.5f&&revision=="test","Malformed request retains values");
        {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"NearestCoastEnabled=0\nAttackRefreshToken=1\nKeepRevealedEnabled=0\nRevision=off\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\n";}
        Refresh();Require(walkMultiplier==5&&constructionMultiplier==1&&revision=="off","Construction disables independently");
        Require(campOverlapEnabled==0,"Overlap restriction restored via configuration");
        {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"KeepRevealedEnabled=0\nRevision=attack\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\nNearestCoastEnabled=1\nAttackRefreshToken=2\n";}
        Refresh();Require(nearestCoastEnabled==1&&attackRefreshToken==2&&attackRefresh.Pending()&&revision=="attack",
            "Attack configuration applied with pending cache refresh");
        auto generation=attackRefresh.requested;Refresh();
        Require(attackRefresh.requested==generation,"Identical native polling never triggers another world refresh");
        for(const char* bad:{"2","nan","inf","1junk","0.5","-1",""}) {
            {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"KeepRevealedEnabled=0\nRevision=bad\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=2\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=4\nCampOverlapEnabled=1\nNearestCoastEnabled="<<bad<<"\nAttackRefreshToken=3\n";}
            Refresh();Require(nearestCoastEnabled==1&&attackRefreshToken==2&&walkMultiplier==5&&campOverlapEnabled==0&&
                revision=="attack"&&attackRefresh.requested==generation&&error=="NativeRequestInvalid","Invalid nearest coast switch retains every module and refresh generation");
        }
        for(const char* bad:{"0","-1","2147483648","1junk",""}) {
            {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"KeepRevealedEnabled=0\nRevision=bad\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=2\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=4\nCampOverlapEnabled=1\nNearestCoastEnabled=0\nAttackRefreshToken="<<bad<<"\n";}
            Refresh();Require(revision=="attack"&&attackRefresh.requested==generation&&error=="NativeRequestInvalid","Malformed world refresh token rejected atomically");
        }
        {std::ofstream f(folder+L"native-request.ini");f<<"WorkerMovementAddress=2\n";f<<"ShipFactor=1\n"<<"KeepRevealedEnabled=0\nRevision=attackoff\nCampRadiusFactor=1\nCampHousingSteps=10\nTransportFactor=5\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\nConstructionFactor=1\nCampOverlapEnabled=0\nNearestCoastEnabled=0\nAttackRefreshToken=2\n";}
        Refresh();Require(nearestCoastEnabled==0&&attackRefresh.requested==generation+1&&revision=="attackoff","Disabling nearest coast schedules restore independently");
        Status();
        {std::ifstream f(folder+L"native-status.ini");std::string s((std::istreambuf_iterator<char>(f)),{});
            Require(s.find("ConstructionFactor=1\n")!=std::string::npos&&s.find("ConstructionCalls=")!=std::string::npos,"Construction status exports applied factor and calls");}
        {std::ifstream f(folder+L"native-status.ini");std::string s((std::istreambuf_iterator<char>(f)),{});
            Require(s.find("AttackPending=1\n")!=std::string::npos&&s.find("NearestCoastEnabled=0\n")!=std::string::npos,
                "Native status never acknowledges pending attack refresh");}
        {std::ifstream f(folder+L"native-status.ini");std::string s((std::istreambuf_iterator<char>(f)),{});
            Require(s.find("CampOverlapEnabled=0\n")!=std::string::npos&&s.find("CampOverlapBypasses=4\n")!=std::string::npos&&
                s.find("CampOverlapChecks=17\n")!=std::string::npos,"Camp status exports active switch and both counters");}
        TestFogConfiguration();
        TestShipConfiguration();
        TestWorkerConfiguration();TestBattleConfiguration();
        RunHousingConfigTests();
        RunHousingTooltipConfigTests();
        DeleteFileW((folder+L"native-status.ini").c_str());
        DeleteFileW((folder+L"native-request.ini").c_str());RemoveDirectoryW(folder.c_str());RemoveDirectoryW(isolated.c_str());
        std::cout<<"Native: "<<checks<<" checks passed (no game process accessed)\n";
        return 0;
    }catch(const std::exception& ex){std::cerr<<ex.what()<<"\n";return 1;}
}
