; Verified scalar-speed/construction instructions and a camp placement gate.
; No game state writes.
; Scalar SSE instructions preserve RFLAGS. The counters preserve flags explicitly.
EXTERN walkMultiplier:DWORD
EXTERN stepResume:QWORD
EXTERN durationResume:QWORD
EXTERN remainingResume:QWORD
EXTERN visualResume:QWORD
EXTERN visualTimeResume:QWORD
EXTERN planResume:QWORD
EXTERN arrivalResume:QWORD
EXTERN routeResume:QWORD
EXTERN routeAltResume:QWORD
EXTERN walkCalls:QWORD
EXTERN visualCalls:QWORD
EXTERN visualTimeCalls:QWORD
EXTERN transportPlanCalls:QWORD
EXTERN workerMovementAddress:QWORD
EXTERN locomotionMultiplier:QWORD
EXTERN locomotionDefaultCalls:QWORD
EXTERN locomotionOverrideCalls:QWORD
EXTERN locomotionDefaultResume:QWORD
EXTERN locomotionOverrideResume:QWORD
EXTERN locomotionIndexedDefaultResume:QWORD
EXTERN locomotionIndexedOverrideResume:QWORD
EXTERN constructionMultiplier:DWORD
EXTERN constructionResume:QWORD
EXTERN constructionCalls:QWORD
EXTERN shipMultiplier:DWORD
EXTERN shipCalls:QWORD
EXTERN shipResume:QWORD
EXTERN campOverlapEnabled:DWORD
EXTERN campOverlapChecks:QWORD
EXTERN campOverlapBypasses:QWORD
EXTERN campGateContinue:QWORD
EXTERN campGateReject:QWORD
EXTERN nearestCoastEnabled:DWORD
EXTERN nearestCoastChecks:QWORD
EXTERN nearestCoastAccept:QWORD
EXTERN nearestCoastReject:QWORD
EXTERN SelectNearestCoast:PROC
EXTERN attackTickOriginal:QWORD
EXTERN RefreshAttackPoints:PROC
EXTERN keepRevealedEnabled:DWORD
EXTERN fogKeepChecks:QWORD
EXTERN fogKeepOverrides:QWORD
EXTERN fogTransitionChecks:QWORD
EXTERN fogCoversBlocked:QWORD
EXTERN fogKeepResume:QWORD
EXTERN fogTransitionResume:QWORD
EXTERN campHousingSteps:DWORD
EXTERN campHousingReads:QWORD
EXTERN campHousingResume:QWORD
EXTERN campHousingPendingResume:QWORD
.code
; CStructurePirateCampData::GetHousing sums eligible ConnectedHouses.
; At this exact read RDX is the structure, RCX its HouseData and EDI the sum.
; A pirate camp also has HouseData. Scale ONLY entries with PirateCampData;
; ordinary houses and all original completion/shutdown checks stay untouched.
; Integer tenths avoid float rounding and preserve map/upgrade-derived capacity.
; No stored capacity is changed, so disabling or reloading cannot compound it.
ScaleCampHousing MACRO resume
    LOCAL housingOriginal,housingNext
    ; Hook the seven-byte pointer load, not the following ADD pair: the game's
    ; eligibility branches jump directly to the iterator ADD and must stay valid.
    mov rcx,QWORD PTR [rdx+308h]
    cmp DWORD PTR [campHousingSteps],10
    je housingOriginal
    cmp QWORD PTR [rdx+2e8h],0
    je housingOriginal
    cmp DWORD PTR [rcx],0
    jle housingOriginal
    test edi,edi
    js housingOriginal
    push rax
    push rdx
    push r8
    mov eax,DWORD PTR [rcx]
    mov r8d,DWORD PTR [campHousingSteps]
    imul rax,r8
    xor edx,edx
    mov r8d,10
    div r8
    mov edx,edi
    add rax,rdx
    mov r8d,7fffffffh
    cmp rax,r8
    cmova rax,r8
    mov edi,eax
    lock inc QWORD PTR [campHousingReads]
    pop r8
    pop rdx
    pop rax
    jmp housingNext
housingOriginal:
    add edi,DWORD PTR [rcx]
housingNext:
    ; Also replay the next two instructions and resume after them. The original
    ; iterator remains intact for eligibility branches that bypass our hook.
    add rbx,10h
    jmp QWORD PTR [resume]
ENDM
CampHousingHook PROC
    ScaleCampHousing campHousingResume
CampHousingHook ENDP
CampHousingPendingHook PROC
    ScaleCampHousing campHousingPendingResume
CampHousingPendingHook ENDP
; Both original getters retain the chosen movement asset in RBX until their
; epilogue. Defaults select ConnectionConfigs[network]; overrides use [RAX].
; Scale only the final read, including nonzero network indices and overrides.
; No asset writes, no scratch registers, and x1 bypasses multiplication exactly.
ScaleWorkerLocomotion MACRO counter
    LOCAL done
    pushfq
    cmp rbx,QWORD PTR [workerMovementAddress]
    jne done
    lock inc QWORD PTR [counter]
    cmp DWORD PTR [walkMultiplier],3f800000h
    je done
    mulsd xmm0,QWORD PTR [locomotionMultiplier]
done:
    popfq
ENDM
LocomotionDefaultHook PROC
    movsd xmm0,QWORD PTR [rbx+rax*8]
    ScaleWorkerLocomotion locomotionDefaultCalls
    jmp QWORD PTR [locomotionDefaultResume]
LocomotionDefaultHook ENDP
LocomotionOverrideHook PROC
    movsd xmm0,QWORD PTR [rax]
    ScaleWorkerLocomotion locomotionOverrideCalls
    mov rbx,QWORD PTR [rsp+40h]
    jmp QWORD PTR [locomotionOverrideResume]
LocomotionOverrideHook ENDP
LocomotionIndexedDefaultHook PROC
    movsd xmm0,QWORD PTR [rbx+rax*8]
    ScaleWorkerLocomotion locomotionDefaultCalls
    jmp QWORD PTR [locomotionIndexedDefaultResume]
LocomotionIndexedDefaultHook ENDP
LocomotionIndexedOverrideHook PROC
    movsd xmm0,QWORD PTR [rax]
    ScaleWorkerLocomotion locomotionOverrideCalls
    mov rbx,QWORD PTR [rsp+48h]
    jmp QWORD PTR [locomotionIndexedOverrideResume]
LocomotionIndexedOverrideHook ENDP
; Return the scaled effective sailing speed. Preserve the original source XMM6,
; all other lanes/registers/flags and the stack-cookie load before the epilogue.
ShipSpeedHook PROC
    movaps xmm0,xmm6
    mulss xmm0,DWORD PTR [shipMultiplier]
    mov rcx,QWORD PTR [rsp+30h]
    pushfq
    lock inc QWORD PTR [shipCalls]
    popfq
    jmp QWORD PTR [shipResume]
ShipSpeedHook ENDP
StepHook PROC
    movss xmm1, DWORD PTR [rbx+8]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [walkCalls]
    popfq
    jmp QWORD PTR [stepResume]
StepHook ENDP
DurationHook PROC
    movss xmm0, DWORD PTR [rbx+8]
    mulss xmm0, DWORD PTR [walkMultiplier]
    jmp QWORD PTR [durationResume]
DurationHook ENDP
RemainingHook PROC
    movss xmm1, DWORD PTR [rbx+8]
    mulss xmm1, DWORD PTR [walkMultiplier]
    jmp QWORD PTR [remainingResume]
RemainingHook ENDP
VisualHook PROC
    movss xmm1, DWORD PTR [rbx+8]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [visualCalls]
    popfq
    jmp QWORD PTR [visualResume]
VisualHook ENDP
; The actual carrier controller has a second cached-speed read for its remaining
; travel-time/animation transition. Both must agree with the job's progress.
VisualTimeHook PROC
    movss xmm1, DWORD PTR [rbx+8]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [visualTimeCalls]
    popfq
    jmp QWORD PTR [visualTimeResume]
VisualTimeHook ENDP
; Economy travel estimates use AgentBaseSpeed directly, not the job's cached
; speed. Scale these reads as well; never scale the global or stored path speed,
; which would compound the job/visual read hooks or persist across disable/save.
TransportPlanHook PROC
    movss xmm0, DWORD PTR [rax+300h]
    mulss xmm0, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [transportPlanCalls]
    popfq
    jmp QWORD PTR [planResume]
TransportPlanHook ENDP
TransportArrivalHook PROC
    movss xmm1, DWORD PTR [rbx+300h]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [transportPlanCalls]
    popfq
    jmp QWORD PTR [arrivalResume]
TransportArrivalHook ENDP
TransportRouteHook PROC
    movss xmm1, DWORD PTR [rsi+300h]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [transportPlanCalls]
    popfq
    jmp QWORD PTR [routeResume]
TransportRouteHook ENDP
TransportRouteAltHook PROC
    movss xmm1, DWORD PTR [rax+300h]
    mulss xmm1, DWORD PTR [walkMultiplier]
    pushfq
    lock inc QWORD PTR [transportPlanCalls]
    popfq
    jmp QWORD PTR [routeAltResume]
TransportRouteAltHook ENDP
; Original construction progress is replayed into XMM7 unchanged. Only the
; worker/duration rate in XMM6 changes. Delta time, resource caps, phase changes
; and completion notifications remain in the original construction routine.
ConstructionHook PROC
    movss xmm7, DWORD PTR [r15+8]
    mulss xmm6, DWORD PTR [constructionMultiplier]
    pushfq
    lock inc QWORD PTR [constructionCalls]
    popfq
    jmp QWORD PTR [constructionResume]
ConstructionHook ENDP
; The original six bytes test the returned camp handle and branch if invalid.
; When enabled, a valid camp also follows the normal no-conflict path. That path
; releases the handle and checks required structures. No registers/handles change.
CampGateHook PROC
    pushfq
    lock inc QWORD PTR [campOverlapChecks]
    cmp DWORD PTR [campOverlapEnabled],0
    je ReplayCampGate
    test BYTE PTR [r9],1
    jz ReplayCampGate
    lock inc QWORD PTR [campOverlapBypasses]
    popfq
    jmp QWORD PTR [campGateContinue]
ReplayCampGate:
    popfq
    test BYTE PTR [r9],1
    jz ContinueCampGate
    jmp QWORD PTR [campGateReject]
ContinueCampGate:
    jmp QWORD PTR [campGateContinue]
CampGateHook ENDP
; Mid-function gate replaces COMISS XMM1,XMM0 / JA skip. At this audited
; site RSP is 16-byte aligned, R15=model, R13=point, RCX=selected camp XY.
; Preserve every volatile register and all six SSE registers across the helper.
; Original camp eligibility, handle ownership and tower calculations stay intact.
NearestCoastHook PROC FRAME
    lea rsp,[rsp-0c0h]
    .allocstack 0c0h
    .endprolog
    pushfq
    lock inc QWORD PTR [nearestCoastChecks]
    cmp DWORD PTR [nearestCoastEnabled],0
    je NearestCoastOriginal
    popfq
    mov QWORD PTR [rsp+20h],rax
    mov QWORD PTR [rsp+28h],rcx
    mov QWORD PTR [rsp+30h],rdx
    mov QWORD PTR [rsp+38h],r8
    mov QWORD PTR [rsp+40h],r9
    mov QWORD PTR [rsp+48h],r10
    mov QWORD PTR [rsp+50h],r11
    movaps XMMWORD PTR [rsp+60h],xmm0
    movaps XMMWORD PTR [rsp+70h],xmm1
    movaps XMMWORD PTR [rsp+80h],xmm2
    movaps XMMWORD PTR [rsp+90h],xmm3
    movaps XMMWORD PTR [rsp+0a0h],xmm4
    movaps XMMWORD PTR [rsp+0b0h],xmm5
    mov r8,rcx
    mov rcx,r15
    mov rdx,r13
    call SelectNearestCoast
    mov BYTE PTR [rsp+58h],al
    movaps xmm0,XMMWORD PTR [rsp+60h]
    movaps xmm1,XMMWORD PTR [rsp+70h]
    movaps xmm2,XMMWORD PTR [rsp+80h]
    movaps xmm3,XMMWORD PTR [rsp+90h]
    movaps xmm4,XMMWORD PTR [rsp+0a0h]
    movaps xmm5,XMMWORD PTR [rsp+0b0h]
    mov rax,QWORD PTR [rsp+20h]
    mov rcx,QWORD PTR [rsp+28h]
    mov rdx,QWORD PTR [rsp+30h]
    mov r8,QWORD PTR [rsp+38h]
    mov r9,QWORD PTR [rsp+40h]
    mov r10,QWORD PTR [rsp+48h]
    mov r11,QWORD PTR [rsp+50h]
    cmp BYTE PTR [rsp+58h],0
    lea rsp,[rsp+0c0h]
    je NearestCoastSkip
    jmp QWORD PTR [nearestCoastAccept]
NearestCoastOriginal:
    popfq
    lea rsp,[rsp+0c0h]
    comiss xmm1,xmm0
    ja NearestCoastSkip
    jmp QWORD PTR [nearestCoastAccept]
NearestCoastSkip:
    jmp QWORD PTR [nearestCoastReject]
NearestCoastHook ENDP
; Prepend one lazy refresh to the game's own fortification update. Preserve all
; volatile GPRs, XMM arguments and RFLAGS, including any unknown caller context.
AttackTickHook PROC FRAME
    lea rsp,[rsp-0c8h]
    .allocstack 0c8h
    .endprolog
    mov QWORD PTR [rsp+20h],rax
    mov QWORD PTR [rsp+28h],rcx
    mov QWORD PTR [rsp+30h],rdx
    mov QWORD PTR [rsp+38h],r8
    mov QWORD PTR [rsp+40h],r9
    mov QWORD PTR [rsp+48h],r10
    mov QWORD PTR [rsp+50h],r11
    pushfq
    pop QWORD PTR [rsp+58h]
    movaps XMMWORD PTR [rsp+60h],xmm0
    movaps XMMWORD PTR [rsp+70h],xmm1
    movaps XMMWORD PTR [rsp+80h],xmm2
    movaps XMMWORD PTR [rsp+90h],xmm3
    movaps XMMWORD PTR [rsp+0a0h],xmm4
    movaps XMMWORD PTR [rsp+0b0h],xmm5
    call RefreshAttackPoints
    movaps xmm0,XMMWORD PTR [rsp+60h]
    movaps xmm1,XMMWORD PTR [rsp+70h]
    movaps xmm2,XMMWORD PTR [rsp+80h]
    movaps xmm3,XMMWORD PTR [rsp+90h]
    movaps xmm4,XMMWORD PTR [rsp+0a0h]
    movaps xmm5,XMMWORD PTR [rsp+0b0h]
    mov rax,QWORD PTR [rsp+20h]
    mov rcx,QWORD PTR [rsp+28h]
    mov rdx,QWORD PTR [rsp+30h]
    mov r8,QWORD PTR [rsp+38h]
    mov r9,QWORD PTR [rsp+40h]
    mov r10,QWORD PTR [rsp+48h]
    mov r11,QWORD PTR [rsp+50h]
    push QWORD PTR [rsp+58h]
    popfq
    lea rsp,[rsp+0c8h] ; do not change restored flags
    jmp QWORD PTR [attackTickOriginal]
AttackTickHook ENDP
; Replay MOVZX R14D,[RAX+58h] (region.bKeepDiscovered), optionally treating
; this read as true. The original controller then disables/resets its own cover
; timer. No model/asset/save flag is overwritten, so disabling is reversible.
FogKeepHook PROC
    movzx r14d,BYTE PTR [rax+58h]
    pushfq
    lock inc QWORD PTR [fogKeepChecks]
    cmp DWORD PTR [keepRevealedEnabled],0
    je FogKeepDone
    test r14d,r14d
    jnz FogKeepDone
    mov r14d,1
    lock inc QWORD PTR [fogKeepOverrides]
FogKeepDone:
    popfq
    jmp QWORD PTR [fogKeepResume]
FogKeepHook ENDP
; The game's original CMP is followed by JE unchanged. Suppress only 1 -> 0
; visibility transitions by returning equality to that branch. All discovery
; requests, undiscovered regions and unknown state values use the original CMP.
; The game's unchanged path still drains the queued request and releases handles.
FogTransitionHook PROC
    pushfq
    lock inc QWORD PTR [fogTransitionChecks]
    cmp DWORD PTR [keepRevealedEnabled],0
    je FogTransitionOriginal
    test al,al
    jnz FogTransitionOriginal
    cmp BYTE PTR [rdx+90h],1
    jne FogTransitionOriginal
    lock inc QWORD PTR [fogCoversBlocked]
    popfq
    cmp al,al
    jmp QWORD PTR [fogTransitionResume]
FogTransitionOriginal:
    popfq
    cmp BYTE PTR [rdx+90h],al
    jmp QWORD PTR [fogTransitionResume]
FogTransitionHook ENDP
END
