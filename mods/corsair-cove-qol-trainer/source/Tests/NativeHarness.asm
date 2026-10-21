EXTERN StepHook:PROC
EXTERN DurationHook:PROC
EXTERN RemainingHook:PROC
EXTERN VisualHook:PROC
EXTERN stepResume:QWORD
EXTERN durationResume:QWORD
EXTERN remainingResume:QWORD
EXTERN visualResume:QWORD
EXTERN ConstructionHook:PROC
EXTERN AttackTickHook:PROC
EXTERN NearestCoastHook:PROC
EXTERN FakeHousingPopulation:PROC
.code
GameHousingPopulationFixture PROC
    mov QWORD PTR [rsp+18h],rbp
    mov QWORD PTR [rsp+20h],rdi
    push r14
    sub rsp,20h
    call FakeHousingPopulation
    mov rbp,QWORD PTR [rsp+40h]
    mov rdi,QWORD PTR [rsp+48h]
    add rsp,20h
    pop r14
    ret
GameHousingPopulationFixture ENDP
; Same load, addition and iterator as each real housing sum. The original
; iterator remains an independent branch destination outside the patched span.
HousingReadFixture MACRO name
name PROC
    mov rcx,QWORD PTR [rdx+308h]
    add edi,DWORD PTR [rcx]
    add rbx,10h
    mov DWORD PTR [r8],edi
    mov QWORD PTR [r8+8],rbx
    mov QWORD PTR [r8+16],rax
    mov QWORD PTR [r8+24],rdx
    mov QWORD PTR [r8+32],rcx
    pushfq
    pop QWORD PTR [r8+40]
    movups XMMWORD PTR [r8+48],xmm0
    ret
name ENDP
ENDM
HousingReadFixture GameHousingReadFixture
HousingReadFixture GameHousingPendingFixture
HousingReadWrapper MACRO name,fixture
name PROC FRAME
    push rbx
    .pushreg rbx
    push rdi
    .pushreg rdi
    sub rsp,40
    .allocstack 40
    .endprolog
    mov edi,r9d
    mov rbx,123456789abcde00h
    mov rax,1122334455667788h
    pcmpeqd xmm0,xmm0
    call fixture
    add rsp,40
    pop rdi
    pop rbx
    ret
name ENDP
ENDM
HousingReadWrapper TestPatchedHousingRead,GameHousingReadFixture
HousingReadWrapper TestPatchedHousingPendingRead,GameHousingPendingFixture
TestSkippedHousingRead PROC FRAME
    push rbx
    .pushreg rbx
    push rdi
    .pushreg rdi
    sub rsp,40
    .allocstack 40
    .endprolog
    mov r11,rcx
    mov edi,r9d
    mov rbx,123456789abcde00h
    xor ecx,ecx
    xor edx,edx
    call r11
    add rsp,40
    pop rdi
    pop rbx
    ret
TestSkippedHousingRead ENDP
; Isolated replay sites for every transport speed reader. Each first instruction
; is byte-identical to the audited executable. The continuation records both
; SSE registers, flags and source registers, so wrong ABI/upper lanes are caught.
CarrierReadRecord PROC
    movups XMMWORD PTR [rdx],xmm0
    movups XMMWORD PTR [rdx+16],xmm1
    pushfq
    pop QWORD PTR [rdx+32]
    mov QWORD PTR [rdx+40],rax
    mov QWORD PTR [rdx+48],rbx
    mov QWORD PTR [rdx+56],rsi
    ret
CarrierReadRecord ENDP
CarrierPathX1 PROC
    movss xmm1,DWORD PTR [rbx+8]
    jmp CarrierReadRecord
CarrierPathX1 ENDP
CarrierPathX0 PROC
    movss xmm0,DWORD PTR [rbx+8]
    jmp CarrierReadRecord
CarrierPathX0 ENDP
CarrierGlobalAX0 PROC
    movss xmm0,DWORD PTR [rax+300h]
    jmp CarrierReadRecord
CarrierGlobalAX0 ENDP
CarrierGlobalBX1 PROC
    movss xmm1,DWORD PTR [rbx+300h]
    jmp CarrierReadRecord
CarrierGlobalBX1 ENDP
CarrierGlobalSX1 PROC
    movss xmm1,DWORD PTR [rsi+300h]
    jmp CarrierReadRecord
CarrierGlobalSX1 ENDP
CarrierGlobalAX1 PROC
    movss xmm1,DWORD PTR [rax+300h]
    jmp CarrierReadRecord
CarrierGlobalAX1 ENDP
TestCarrierRead PROC FRAME
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    sub rsp,40
    .allocstack 40
    .endprolog
    mov r11,rcx
    mov rax,rdx
    mov rbx,rdx
    mov rsi,rdx
    mov rdx,r8
    pcmpeqd xmm0,xmm0
    pcmpeqd xmm1,xmm1
    stc
    pushfq
    pop QWORD PTR [rdx+64]
    call r11
    add rsp,40
    pop rsi
    pop rbx
    ret
TestCarrierRead ENDP
GameShipSpeedFixture PROC
    movaps xmm0,xmm6
    mov rcx,QWORD PTR [rsp+30h]
    movss DWORD PTR [rdx],xmm0
    mov QWORD PTR [rdx+8],rcx
    pushfq
    pop rax
    mov QWORD PTR [rdx+16],rax
    movss DWORD PTR [rdx+24],xmm6
    ret
GameShipSpeedFixture ENDP
TestPatchedShipSpeed PROC FRAME
    push rdi
    .pushreg rdi
    sub rsp,96
    .allocstack 96
    movaps XMMWORD PTR [rsp+48],xmm6
    .savexmm128 xmm6,48
    .endprolog
    mov rax,123456789abcdef0h
    mov QWORD PTR [rsp+40],rax
    movaps xmm6,xmm0
    stc
    call GameShipSpeedFixture
    movaps xmm6,XMMWORD PTR [rsp+48]
    add rsp,96
    pop rdi
    ret
TestPatchedShipSpeed ENDP
GameStepFixture PROC
    movss xmm1,DWORD PTR [rbx+8]
    movss xmm0,xmm1
    ret
GameStepFixture ENDP
TestPatchedStep PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp,48
    .allocstack 48
    .endprolog
    movss DWORD PTR [rsp+40],xmm0
    lea rbx,[rsp+32]
    call GameStepFixture
    add rsp,48
    pop rbx
    ret
TestPatchedStep ENDP
ReturnXmm1 PROC
    movss xmm0,xmm1
    ret
ReturnXmm1 ENDP
ReturnXmm0 PROC
    ret
ReturnXmm0 ENDP
ReturnXmm12 PROC
    movss xmm0,xmm12
    ret
ReturnXmm12 ENDP
TestStep PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp,48
    .allocstack 48
    .endprolog
    movss DWORD PTR [rsp+40],xmm0
    lea rbx,[rsp+32]
    lea rax,ReturnXmm1
    mov QWORD PTR [stepResume],rax
    call StepHook
    add rsp,48
    pop rbx
    ret
TestStep ENDP
TestDuration PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp,48
    .allocstack 48
    .endprolog
    movss DWORD PTR [rsp+40],xmm0
    lea rbx,[rsp+32]
    lea rax,ReturnXmm0
    mov QWORD PTR [durationResume],rax
    call DurationHook
    add rsp,48
    pop rbx
    ret
TestDuration ENDP
TestRemaining PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp,48
    .allocstack 48
    .endprolog
    movss DWORD PTR [rsp+40],xmm0
    lea rbx,[rsp+32]
    lea rax,ReturnXmm1
    mov QWORD PTR [remainingResume],rax
    call RemainingHook
    add rsp,48
    pop rbx
    ret
TestRemaining ENDP
TestVisual PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp,48
    .allocstack 48
    .endprolog
    movss DWORD PTR [rsp+40],xmm0
    lea rbx,[rsp+32]
    lea rax,ReturnXmm1
    mov QWORD PTR [visualResume],rax
    call VisualHook
    add rsp,48
    pop rbx
    ret
TestVisual ENDP
; The first six bytes match the real construction hook site. The surrounding
; math reproduces delta time, existing progress and the game's material cap.
GameConstructionFixture PROC
    movss xmm7,DWORD PTR [r15+8]
    mulss xmm6,xmm0
    movss xmm0,DWORD PTR [r15+8]
    addss xmm0,xmm6
    minss xmm0,xmm3
    ret
GameConstructionFixture ENDP
; rate, existing progress, delta time, material progress cap
TestPatchedConstruction PROC FRAME
    push r15
    .pushreg r15
    sub rsp,80
    .allocstack 80
    movaps XMMWORD PTR [rsp+32],xmm6
    .savexmm128 xmm6,32
    movaps XMMWORD PTR [rsp+48],xmm7
    .savexmm128 xmm7,48
    .endprolog
    movss DWORD PTR [rsp+72],xmm1
    lea r15,[rsp+64]
    movaps xmm6,xmm0
    movaps xmm0,xmm2
    call GameConstructionFixture
    movaps xmm6,XMMWORD PTR [rsp+32]
    movaps xmm7,XMMWORD PTR [rsp+48]
    add rsp,80
    pop r15
    ret
TestPatchedConstruction ENDP
; Same audited entry sequence; read all three forwarded arguments.
GameCampRangeFixture PROC
    mov QWORD PTR [rsp+8],rbx
    push rdi
    sub rsp,70h
    movaps XMMWORD PTR [rsp+60h],xmm6
    movzx eax,BYTE PTR [r8]
    and al,BYTE PTR [rdx]
    and al,BYTE PTR [rcx]
    add rsp,70h
    pop rdi
    ret
GameCampRangeFixture ENDP
; Exact six-byte gate and status-23 write from the game. Both branches retain
; their reference release; the continue branch can still fail a later rule.
GameCampGateFixture PROC
    test BYTE PTR [r9],1
    jz CampFixtureContinue
    mov BYTE PTR [r15],17h
    dec WORD PTR [r9+2]
    xor al,al
    ret
    DB (50h-($-GameCampGateFixture)) DUP (90h)
CampFixtureContinue:
    dec WORD PTR [r9+2]
    mov BYTE PTR [r15],dl
    test edx,edx
    sete al
    ret
GameCampGateFixture ENDP
; reference handle, output status, later error (0=valid; e.g. 24=required structure)
TestPatchedCampGate PROC FRAME
    push r15
    .pushreg r15
    sub rsp,32
    .allocstack 32
    .endprolog
    mov r9,rcx
    mov r15,rdx
    mov edx,r8d
    call GameCampGateFixture
    add rsp,32
    pop r15
    ret
TestPatchedCampGate ENDP
; Reproduce the audited in-function alignment and RCX/R13/R15 context.
; C signature: (model, point, campXY, originalThresholdSquared, distanceSquared).
PUBLIC GameNearestCoastFixture, NearestCoastFixtureAccept, NearestCoastFixtureReject
TestPatchedNearestCoast PROC FRAME
    push r13
    .pushreg r13
    push r15
    .pushreg r15
    sub rsp,40
    .allocstack 40
    .endprolog
    mov r15,rcx
    mov r13,rdx
    mov rcx,r8
    movaps xmm0,xmm3
    movss xmm1,DWORD PTR [rsp+60h]
GameNearestCoastFixture LABEL NEAR
    comiss xmm1,xmm0
    ja SHORT NearestCoastFixtureReject
NearestCoastFixtureAccept LABEL NEAR
    mov al,1
    jmp SHORT NearestCoastFixtureReturn
    DB 78 dup(90h)
NearestCoastFixtureReject LABEL NEAR
    xor eax,eax
NearestCoastFixtureReturn:
    add rsp,40
    pop r15
    pop r13
    ret
TestPatchedNearestCoast ENDP
; Exercise every volatile register around the new mid-function helper call.
; Capture into the model's otherwise unused fixture prefix, before unwinding
; the frame established by TestNearestCoastRegisters.
CaptureNearestCoastRegisters PROC
    mov QWORD PTR [r15],rax
    mov QWORD PTR [r15+8],rcx
    mov QWORD PTR [r15+16],rdx
    mov QWORD PTR [r15+24],r8
    mov QWORD PTR [r15+32],r9
    mov QWORD PTR [r15+40],r10
    mov QWORD PTR [r15+48],r11
    movdqu XMMWORD PTR [r15+64],xmm0
    movdqu XMMWORD PTR [r15+80],xmm1
    movdqu XMMWORD PTR [r15+96],xmm2
    movdqu XMMWORD PTR [r15+112],xmm3
    movdqu XMMWORD PTR [r15+128],xmm4
    movdqu XMMWORD PTR [r15+144],xmm5
    add rsp,40
    pop r15
    pop r13
    ret
CaptureNearestCoastRegisters ENDP
TestNearestCoastRegisters PROC FRAME
    push r13
    .pushreg r13
    push r15
    .pushreg r15
    sub rsp,40
    .allocstack 40
    .endprolog
    mov r15,rcx
    mov r13,rdx
    mov rcx,r8
    mov eax,1
    movd xmm0,eax
    mov eax,2
    movd xmm1,eax
    mov eax,3
    movd xmm2,eax
    mov eax,4
    movd xmm3,eax
    mov eax,5
    movd xmm4,eax
    mov eax,6
    movd xmm5,eax
    mov rax,11h
    mov rdx,22h
    mov r8,33h
    mov r9,44h
    mov r10,55h
    mov r11,66h
    jmp NearestCoastHook
TestNearestCoastRegisters ENDP
; Same entry prologue as FCFortification_HandleIdleWaitAttacks. Return the
; first point's membership to verify refresh happens BEFORE the original tick.
GameAttackTickFixture PROC FRAME
    DB 40h
    push rbp
    .pushreg rbp
    push rsi
    .pushreg rsi
    lea rbp,[rsp-0c8h]
    sub rsp,1c8h
    .allocstack 1c8h
    .endprolog
    mov rax,QWORD PTR [rcx+3bd0h]
    mov rax,QWORD PTR [rax]
    mov eax,DWORD PTR [rax+0b8h]
    add rsp,1c8h
    pop rsi
    pop rbp
    ret
GameAttackTickFixture ENDP
CaptureAttackTickRegisters PROC
    mov QWORD PTR [rcx],rax
    mov QWORD PTR [rcx+8],rcx
    mov QWORD PTR [rcx+16],rdx
    mov QWORD PTR [rcx+24],r8
    mov QWORD PTR [rcx+32],r9
    mov QWORD PTR [rcx+40],r10
    mov QWORD PTR [rcx+48],r11
    pushfq
    pop rax
    mov QWORD PTR [rcx+56],rax
    movdqu XMMWORD PTR [rcx+64],xmm0
    movdqu XMMWORD PTR [rcx+80],xmm1
    movdqu XMMWORD PTR [rcx+96],xmm2
    movdqu XMMWORD PTR [rcx+112],xmm3
    movdqu XMMWORD PTR [rcx+128],xmm4
    movdqu XMMWORD PTR [rcx+144],xmm5
    ret
CaptureAttackTickRegisters ENDP
TestAttackTickRegisters PROC FRAME
    sub rsp,40
    .allocstack 40
    .endprolog
    mov eax,1
    movd xmm0,eax
    mov eax,2
    movd xmm1,eax
    mov eax,3
    movd xmm2,eax
    mov eax,4
    movd xmm3,eax
    mov eax,5
    movd xmm4,eax
    mov eax,6
    movd xmm5,eax
    mov rax,11h
    mov rdx,22h
    mov r8,33h
    mov r9,44h
    mov r10,55h
    mov r11,66h
    stc
    call AttackTickHook
    add rsp,40
    ret
TestAttackTickRegisters ENDP
; Exact five-byte region keep-discovered read. Pack the incoming carry flag in
; bit8 to check that the hook's counter/switch code preserves original flags.
GameFogKeepFixture PROC
    movzx r14d,BYTE PTR [rax+58h]
    mov eax,r14d
    pushfq
    pop rdx
    and edx,1
    shl edx,8
    or eax,edx
    ret
GameFogKeepFixture ENDP
TestPatchedFogKeep PROC FRAME
    push r14
    .pushreg r14
    sub rsp,32
    .allocstack 32
    .endprolog
    mov rax,rcx
    stc
    call GameFogKeepFixture
    add rsp,32
    pop r14
    ret
TestPatchedFogKeep ENDP
; Exact CMP/JE encoding and target distance from the region reveal controller.
; The accepted path changes visibility and increments a stand-in notification.
; The unchanged path must skip BOTH, not merely rewrite the visibility byte.
GameFogTransitionFixture PROC
    cmp BYTE PTR [rdx+90h],al
    je FogTransitionFixtureDone
    mov BYTE PTR [rdx+90h],al
    inc BYTE PTR [rdx+91h]
    jmp FogTransitionFixtureDone
    DB 625 dup(90h)
FogTransitionFixtureDone:
    movzx eax,BYTE PTR [rdx+90h]
    ret
GameFogTransitionFixture ENDP
TestPatchedFogTransition PROC
    mov eax,edx
    mov rdx,rcx
    jmp GameFogTransitionFixture
TestPatchedFogTransition ENDP
LocomotionDefaultFixture PROC
    movsd xmm0,QWORD PTR [rbx+rax*8]
    mov rbx,QWORD PTR [rsp+40h]
    ret
LocomotionDefaultFixture ENDP
LocomotionOverrideFixture PROC
    movsd xmm0,QWORD PTR [rax]
    mov rbx,QWORD PTR [rsp+40h]
    ret
LocomotionOverrideFixture ENDP
LocomotionIndexedDefaultFixture PROC
    movsd xmm0,QWORD PTR [rbx+rax*8]
    mov rbx,QWORD PTR [rsp+48h]
    ret
LocomotionIndexedDefaultFixture ENDP
LocomotionIndexedOverrideFixture PROC
    movsd xmm0,QWORD PTR [rax]
    mov rbx,QWORD PTR [rsp+48h]
    ret
LocomotionIndexedOverrideFixture ENDP
TestLocomotionRead PROC FRAME
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    sub rsp,70h
    .allocstack 70h
    .endprolog
    mov rdi,rcx
    mov rsi,r9
    mov rbx,rdx
    mov rax,r8
    mov QWORD PTR [rsp+38h],11223344h
    mov QWORD PTR [rsp+40h],55667788h
    pcmpeqd xmm0,xmm0
    pcmpeqd xmm1,xmm1
    stc
    pushfq
    pop QWORD PTR [rsi+24]
    call rdi
    movdqu XMMWORD PTR [rsi],xmm0
    pushfq
    pop QWORD PTR [rsi+16]
    mov QWORD PTR [rsi+32],rax
    mov QWORD PTR [rsi+40],rbx
    mov QWORD PTR [rsi+48],rcx
    mov QWORD PTR [rsi+56],rdx
    mov QWORD PTR [rsi+64],r8
    mov QWORD PTR [rsi+72],r9
    movdqu XMMWORD PTR [rsi+80],xmm1
    add rsp,70h
    pop rdi
    pop rsi
    pop rbx
    ret
TestLocomotionRead ENDP
EXTERN FakeBattleStat:PROC
EXTERN FakeBattleSupply:PROC
PUBLIC GameBattleStatFixture
PUBLIC GameBattleSupplyFixture
GameBattleStatFixture PROC
    mov QWORD PTR [rsp+8],rbx
    mov QWORD PTR [rsp+10h],rbp
    mov QWORD PTR [rsp+18h],rsi
    push rdi
    sub rsp,20h
    call FakeBattleStat
    mov rbx,QWORD PTR [rsp+30h]
    mov rbp,QWORD PTR [rsp+38h]
    mov rsi,QWORD PTR [rsp+40h]
    add rsp,20h
    pop rdi
    ret
GameBattleStatFixture ENDP
GameBattleSupplyFixture PROC
    mov QWORD PTR [rsp+8],rbx
    mov QWORD PTR [rsp+10h],rbp
    mov QWORD PTR [rsp+18h],rsi
    mov QWORD PTR [rsp+20h],rdi
    push r14
    sub rsp,40h
    call FakeBattleSupply
    mov rbx,QWORD PTR [rsp+50h]
    mov rbp,QWORD PTR [rsp+58h]
    mov rsi,QWORD PTR [rsp+60h]
    mov rdi,QWORD PTR [rsp+68h]
    add rsp,40h
    pop r14
    ret
GameBattleSupplyFixture ENDP
END
