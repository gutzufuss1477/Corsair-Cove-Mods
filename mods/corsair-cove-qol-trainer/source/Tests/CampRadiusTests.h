#include <array>
static int radiusCalls=0;
static void FakeSetRadius(void* model,void* camp,float value) {
    ++radiusCalls;
    auto data=AttackRead<void*>(camp,0x2e8);
    AttackWrite<float>(data,0x32c,value);
    static_cast<unsigned char*>(model)[0x2f48]=1;
}
static void RunCampRadiusTests() {
    std::array<unsigned char,0x3d00> model{};
    std::array<unsigned char,0x400> camp{},data{};
    unsigned char live=1;
    struct Handle {void* pointer;void* control;} camps[]={{camp.data(),&live}};
    AttackWrite<void*>(model.data(),0x18b0,camps);AttackWrite<int>(model.data(),0x18b8,1);
    AttackWrite<void*>(camp.data(),0x2e8,data.data());
    AttackWrite<float>(data.data(),0x328,3000);AttackWrite<float>(data.data(),0x32c,3750);
    CampRadiusState state;state.Configure(50);state.Update(model.data(),FakeSetRadius);
    Require(!state.pending&&!state.invalid&&radiusCalls==1,"Existing camp uses original range setter once");
    Require(AttackRead<float>(data.data(),0x328)==150000&&AttackRead<float>(data.data(),0x32c)==150750,"Range multiplier preserves additive unlocked bonus");
    Require(model[0x2f48]==1,"Original setter owns logistics invalidation");
    for(int i=0;i<1000;++i)state.Update(model.data(),FakeSetRadius);
    Require(radiusCalls==1,"No repeated game recalculations for unchanged range");
    state.Configure(1);state.Update(model.data(),FakeSetRadius);
    Require(AttackRead<float>(data.data(),0x32c)==3750&&radiusCalls==2,"Disable restores vanilla base while retaining bonuses");
    AttackWrite<float>(data.data(),0x328,150000);AttackWrite<float>(data.data(),0x32c,150500);
    CampRadiusState reload;reload.Configure(1);reload.Update(model.data(),FakeSetRadius);
    Require(AttackRead<float>(data.data(),0x32c)==3500,"Saved expanded camps normalize after restarting with switch off");
    reload.Configure(500);live=0;reload.Update(model.data(),FakeSetRadius);
    Require(reload.invalid&&radiusCalls==3,"Stale camp handles cause no writes");
    live=1;reload.Update(model.data(),FakeSetRadius);
    Require(!reload.invalid&&AttackRead<float>(data.data(),0x32c)==1500500,"Maximum factor and recovered live model");
    AttackWrite<float>(data.data(),0x328,std::numeric_limits<float>::quiet_NaN());
    reload.Configure(2);reload.Update(model.data(),FakeSetRadius);
    Require(reload.invalid&&radiusCalls==4,"Invalid radius data fails closed");
}
