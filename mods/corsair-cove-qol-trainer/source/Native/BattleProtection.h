#pragma once
// Audited Caribbean event stat setter and choice-supply debit. No polling,
// post-damage healing, dice manipulation, or persistent asset edits.
// Bits follow the audited stat order: hull=1, crew=2, supplies=4.
alignas(4) static LONG battleProtectionMask=0;
static LONG64 battleStatChecks=0,battleStatBlocks=0,battleSupplyChecks=0,battleSupplyBlocks=0;
using BattleTagFn=unsigned char(*)(const void*);
using BattleStatFn=bool(*)(void*,const void*,int);
using BattleSupplyFn=bool(*)(void*,void*,int,bool);
using BattleEncounterFn=bool(*)(const void*);
static BattleEncounterFn battleEncounterActive=nullptr;
static BattleTagFn battleStatSource=nullptr,battleStatType=nullptr;
static BattleStatFn battleStatOriginal=nullptr;
static BattleSupplyFn battleSupplyOriginal=nullptr;
static bool BattleStatHook(void* stats,const void* tag,int value) {
    InterlockedIncrement64(&battleStatChecks);
    const LONG mask=battleProtectionMask;
    if(mask&&stats&&tag&&battleStatSource&&battleStatType&&battleStatSource(tag)==0) {
        const unsigned kind=battleStatType(tag);
        // CurrentPlayerStats +2c; pairs {maximum,current} for hull, crew,
        // and Cargo (the game's supplies stat). Event/opponent stats are +84.
        if(kind<3&&(mask&(1L<<kind))) {
            const int current=*reinterpret_cast<const int*>(static_cast<const unsigned char*>(stats)+0x30+kind*8);
            if(current>=0&&value<current) {value=current;InterlockedIncrement64(&battleStatBlocks);}
        }
    }
    // Retain the game's validation and maximum clamp, and forward gains intact.
    return battleStatOriginal(stats,tag,value);
}
static bool BattleSupplyHook(void* context,void* event,int amount,bool player) {
    InterlockedIncrement64(&battleSupplyChecks);
    // Use the game's own predicate for the live encounter-stat branch.
    // Costs that would instead be charged to the ship outside it stay normal.
    if((battleProtectionMask&4)&&player&&amount>0&&event&&battleEncounterActive&&battleEncounterActive(event)) {
        amount=0;InterlockedIncrement64(&battleSupplyBlocks);
    }
    return battleSupplyOriginal(context,event,amount,player);
}
