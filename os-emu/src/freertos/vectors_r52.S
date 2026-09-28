/* vectors_r52.S -- bang vector (A32) + boot cho FreeRTOS tren QEMU mps3-an536.
 *
 * Thay start_r52.S cua demOS khi chay FreeRTOS: port ARM_CRx_No_GIC can
 *   - SVC -> FreeRTOS_SVC_Handler (vPortYield: "svc 0")
 *   - IRQ -> FreeRTOS_IRQ_Handler (tick)
 * va bang vector phai nam o dia chi 0 (toolchain/link-r52.ld: .text @ 0x0),
 * dung 8 entry, moi entry 4 byte.
 *
 * VI SAO PHAI HA XUONG EL1:
 *   Cortex-R52 co EL2 (HYP) va QEMU bat CPU o EL2.  Nhung port nay duoc
 *   viet cho ngu canh EL1: vPortYield dung "svc 0" (o EL2 la UNDEFINED),
 *   FreeRTOS_IRQ_Handler dung "cps #svc_mode"/"cps #irq_mode" va
 *   "msr spsr_cxsf" (o EL2 khong hop le), IRQ o EL2 se vao bang HVBAR chu
 *   khong phai VBAR.  Vi vay boot code duoi day:
 *     1. thay CPSR dang o HYP mode: dat ELR_hyp = nhan duoi EL1,
 *        SPSR_hyp = SVC mode + IRQ/FIQ mask, roi ERET -> chay o EL1/SVC.
 *     2. da o EL1: dat SP cho SVC mode, dat VBAR, dat SP rieng cho IRQ
 *        mode (portASM.S vao IRQ mode va PUSH {LR, SPSR} o do) roi nhay
 *        vao k_os_entry.
 *
 * ERET / MSR ELR_hyp / SPSR_hyp nam sau .arch_extension virt; cac lenh
 * CP15 con lai (VBAR, CNTHCTL, ICC_*, CNTP_*) khong can extension.
 *
 * TRANG THAI CPU KHI QEMU KHOI DONG (target/arm/cpu.c: arm_cpu_reset_hold):
 *   - mode: EL2/HYP, vi R52 co EL2 ma khong co EL3 ("AArch32 will start in
 *     Hyp mode").
 *   - instruction set: ARM (A32), khong phai Thumb.  Chi nhanh M-profile moi
 *     lay env->thumb tu vector table (dong "env->thumb = initial_pc & 1");
 *     nhanh A/R khong doi env->thumb, va ELF entry _start = 0x0 (bit0 = 0).
 *     => bang vector duoi day phai la A32, va vi cac file .c/.S khac cua
 *     profile r52 duoc assemble bang "-mthumb" (config.sh: thumb-r52) nen o
 *     day PHAI co ".arm" (neu khong clang se assemble Thumb -> bang vector
 *     thanh rac).
 */
    .syntax unified
    .arch armv7-a
    .arch_extension virt
    .arm                                /* bang vector + handler: A32        */

    .set  SVC_MODE,   0x13
    .set  IRQ_MODE,   0x12
    .set  HYP_MODE,   0x1A
    .set  MODE_MASK,  0x1F
    .set  CPSR_T,     0x20
    .set  CPSR_F,     0x40
    .set  CPSR_I,     0x80
    .set  STACK_SVC,  0x10020000        /* = stacktop-r52 trong config.sh      */
    .set  STACK_IRQ,  0x1001F000        /* 4 KiB duoi do, danh cho IRQ mode    */
    .set  VECTORS,    0x00000000        /* = _start (link-r52.ld .text @ 0x0)  */

    .section .text
    .align 5                            /* bang vector: 32-byte aligned        */
    .global _start
    .global reset_r52
    .global hang_r52

/* ---------- 8 entry (A32), _start = entry 0 = reset ---------- */
_start:                                 /* 0x00 reset                 */
    b       reset_r52
    b       hang_r52                    /* 0x04 undefined instruction */
    b       FreeRTOS_SVC_Handler        /* 0x08 SVC   (vPortYield)    */
    b       hang_r52                    /* 0x0C prefetch abort        */
    b       hang_r52                    /* 0x10 data abort            */
    b       hang_r52                    /* 0x14 reserved / HVC        */
    b       FreeRTOS_IRQ_Handler        /* 0x18 IRQ   (tick)          */
    b       hang_r52                    /* 0x1C FIQ                   */

/* ---------- reset: chay duoc o ca EL2 (QEMU) va EL1 ---------- */
reset_r52:
    mrs     r0, cpsr
    and     r1, r0, #MODE_MASK
    cmp     r1, #HYP_MODE
    bne     el1_entry

    /* --- dang o EL2: ERET ve EL1/SVC (ERET: PC = ELR_hyp, CPSR = SPSR_hyp) --- */
    adr     r0, el1_entry               /* nhan sau ERET (A32, bit0 = 0)       */
    msr     elr_hyp, r0
    mrs     r0, cpsr
    bic     r0, r0, #( MODE_MASK | CPSR_T )         /* xoa mode + T bit        */
    orr     r0, r0, #( SVC_MODE | CPSR_I | CPSR_F ) /* SVC, A32, mask I/F      */
    msr     spsr_hyp, r0
    /* Cho EL1 dung FPU + timer: CPTR_EL2 = 0 (TFP/TTA = 0 -> khong trap FP),
     * CNTHCTL_EL2 = EL1PCTEN | EL1PCEN (cho EL1 doc/ghi CP15 c14: CNTFRQ,
     * CNTP_*).  Khong lam thi lan doc CNTFRQ_EL0 dau tien trong tick driver
     * se trap ra EL2 (khong co handler -> treo).
     * CP15: CPTR_EL2 = c1,c1,2 ; CNTHCTL_EL2 = c14,c1,0 (opcode p15,4,...) */
    mov     r0, #0
    mcr     p15, 4, r0, c1, c1, 2       /* CPTR_EL2    = 0                 */
    mov     r0, #3                      /* EL1PCTEN(1) | EL1PCEN(2)        */
    mcr     p15, 4, r0, c14, c1, 0      /* CNTHCTL_EL2 = 3                 */
    isb
    eret                                /* -> EL1, SVC mode                    */

/* ---------- da o EL1: stack + bang vector roi vao FreeRTOS ---------- */
el1_entry:
    cps     #SVC_MODE                   /* tu EL2 xuong thi da la SVC mode     */
    ldr     sp, =STACK_SVC              /* stack cua SVC mode                  */
    ldr     r0, =VECTORS
    mcr     p15, 0, r0, c12, c0, 0      /* VBAR: bang vector cho EL1           */
    cps     #IRQ_MODE                   /* stack rieng cho IRQ mode            */
    ldr     sp, =STACK_IRQ              /* (portASM.S vao IRQ mode va PUSH)    */
    cps     #SVC_MODE
    isb
    b       k_os_entry                  /* -> code C (app_main.c)              */

hang_r52:
    b       hang_r52
