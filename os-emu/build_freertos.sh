#!/usr/bin/env bash
# build_freertos.sh -- build image FreeRTOS cho os-emu (bare-metal ELF).
#   ./build_freertos.sh [a76|r52|all|clean]   (mac dinh: a76)
#   V=1 ./build_freertos.sh a76               (in chi tiet tung lenh)
# Ket qua: build/<p>/os-<p>-freertos.elf (+ .list). Chay: ./run_freertos_qemu.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"
SRC="$HERE/src"; BUILD="$HERE/build"
FR="$HERE/extern/FreeRTOS-Kernel"; FREEDIR="$SRC/freertos"
V="${V:-0}"
run() { if [ "$V" = 1 ]; then echo "  $ $*"; fi; "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
# ---- FreeRTOSConfig-a76.h (port ARM_AARCH64 GUEST = chay o EL1) ----
gen_config_a76() { cat > "$FREEDIR/FreeRTOSConfig-a76.h" <<'EOF'
/* FreeRTOSConfig-a76.h -- bring-up Cortex-A76 / QEMU virt. */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H
#define configCPU_CLOCK_HZ                   ( 62500000UL )
#define configTICK_RATE_HZ                   ( ( TickType_t ) 100 )
#define configTICK_TYPE_WIDTH_IN_BITS        TICK_TYPE_WIDTH_64_BITS
#define configUSE_PREEMPTION                 1
#define configUSE_TIME_SLICING               1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#define configMAX_PRIORITIES                 ( 5 )
#define configMINIMAL_STACK_SIZE             ( ( unsigned short ) 256 )
#define configMAX_TASK_NAME_LEN              ( 16 )
#define configIDLE_SHOULD_YIELD              1
#define configUSE_TICKLESS_IDLE              0
#define configSUPPORT_STATIC_ALLOCATION      1
#define configSUPPORT_DYNAMIC_ALLOCATION     1
#define configTOTAL_HEAP_SIZE                ( ( size_t ) ( 64 * 1024 ) )
#define configAPPLICATION_ALLOCATED_HEAP     0
#define configSTACK_DEPTH_TYPE               size_t
#define configSTACK_ALLOCATION_FROM_SEPARATE_HEAP 0
/* INCLUDE_* : FreeRTOS.h mac dinh 0, phai bat tuong minh. */
#define INCLUDE_vTaskDelay                   1
#define INCLUDE_vTaskDelayUntil              1
#define INCLUDE_vTaskDelete                  1
#define INCLUDE_vTaskSuspend                 1
#define INCLUDE_vTaskPrioritySet             1
#define INCLUDE_uxTaskPriorityGet            1
#define INCLUDE_xTaskGetSchedulerState       1
#define INCLUDE_xTaskGetCurrentTaskHandle    1
#define INCLUDE_xTaskGetIdleTaskHandle       1
#define INCLUDE_eTaskGetState                1
#define INCLUDE_pcTaskGetTaskName            1
#define INCLUDE_uxTaskGetStackHighWaterMark  1
#define INCLUDE_xQueueGetMutexHolder         1
#define INCLUDE_xTaskAbortDelay              1
#define INCLUDE_uxTaskGetNumberOfTasks       1
#define configUSE_TIMERS                     0
#define configUSE_EVENT_GROUPS               0
#define configUSE_STREAM_BUFFERS             0
#define configUSE_CO_ROUTINES                0
#define configUSE_MUTEXES                    1
#define configUSE_RECURSIVE_MUTEXES          0
#define configUSE_COUNTING_SEMAPHORES        1
#define configUSE_QUEUE_SETS                 0
#define configUSE_TASK_NOTIFICATIONS         1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE            0
#define configENABLE_BACKWARD_COMPATIBILITY  0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0
#define configUSE_MINI_LIST_ITEM             1
#define configMESSAGE_BUFFER_LENGTH_TYPE     size_t
#define configUSE_POSIX_ERRNO                0
#define configCHECK_FOR_STACK_OVERFLOW       2
#define configUSE_MALLOC_FAILED_HOOK         1
#define configUSE_IDLE_HOOK                  0
#define configUSE_TICK_HOOK                  0
#define configGENERATE_RUN_TIME_STATS        0
#define configUSE_TRACE_FACILITY             0
#define configUSE_STATS_FORMATTING_FUNCTIONS 0
/* configASSERT: prototype phai co truoc khi tasks.c dung (ISO C99 tro len). */
void vAssertCalled( const char *pcFile, unsigned long ulLine );
#define configASSERT( x )                    if( ( x ) == 0 ) { vAssertCalled( __FILE__, __LINE__ ); }
#define configINTERRUPT_CONTROLLER_BASE_ADDRESS ( 0x08000000UL )
#define configINTERRUPT_CONTROLLER_CPU_INTERFACE_OFFSET ( 0x10000UL )
#define configUNIQUE_INTERRUPT_PRIORITIES    32
#define configMAX_API_CALL_INTERRUPT_PRIORITY 18
#define configSETUP_TICK_INTERRUPT()         vSetupTickInterruptA76()
#define configCLEAR_TICK_INTERRUPT()         vClearTickInterruptA76()
/* Tick: dinh nghia trong src/freertos/freertos_tick_a76.c (GICv2 + Generic Timer). */
void vSetupTickInterruptA76( void );
void vClearTickInterruptA76( void );
#define configUSE_TASK_FPU_SUPPORT           2
#define GUEST
#define QEMU
#endif
EOF
}
# ---- FreeRTOSConfig-r52.h (port ARM_CRx_No_GIC, khong GIC) ----
gen_config_r52() { cat > "$FREEDIR/FreeRTOSConfig-r52.h" <<'EOF'
/* FreeRTOSConfig-r52.h -- bring-up Cortex-R52 / QEMU mps3-an536. */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H
/* Chi la gia tri DU PHONG: tick driver doc CNTFRQ that tu phan cung (QEMU R52
 * = 62.5 MHz, target/arm/cpu.c GTIMER_BACKCOMPAT_HZ) va chi dung so nay neu
 * CNTFRQ doc ra 0. */
#define configCPU_CLOCK_HZ                   ( 62500000UL )
#define configTICK_RATE_HZ                   ( ( TickType_t ) 100 )
#define configTICK_TYPE_WIDTH_IN_BITS        TICK_TYPE_WIDTH_32_BITS
#define configUSE_PREEMPTION                 1
#define configUSE_TIME_SLICING               1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#define configMAX_PRIORITIES                 ( 5 )
#define configMINIMAL_STACK_SIZE             ( ( unsigned short ) 128 )
#define configMAX_TASK_NAME_LEN              ( 16 )
#define configIDLE_SHOULD_YIELD              1
#define configUSE_TICKLESS_IDLE              0
#define configSUPPORT_STATIC_ALLOCATION      1
#define configSUPPORT_DYNAMIC_ALLOCATION     1
#define configTOTAL_HEAP_SIZE                ( ( size_t ) ( 32 * 1024 ) )
#define configAPPLICATION_ALLOCATED_HEAP     0
#define configSTACK_DEPTH_TYPE               size_t
#define configSTACK_ALLOCATION_FROM_SEPARATE_HEAP 0
/* INCLUDE_* : FreeRTOS.h mac dinh 0, phai bat tuong minh. */
#define INCLUDE_vTaskDelay                   1
#define INCLUDE_vTaskDelayUntil              1
#define INCLUDE_vTaskDelete                  1
#define INCLUDE_vTaskSuspend                 1
#define INCLUDE_vTaskPrioritySet             1
#define INCLUDE_uxTaskPriorityGet            1
#define INCLUDE_xTaskGetSchedulerState       1
#define INCLUDE_xTaskGetCurrentTaskHandle    1
#define INCLUDE_xTaskGetIdleTaskHandle       1
#define INCLUDE_eTaskGetState                1
#define INCLUDE_pcTaskGetTaskName            1
#define INCLUDE_uxTaskGetStackHighWaterMark  1
#define INCLUDE_xQueueGetMutexHolder         1
#define INCLUDE_xTaskAbortDelay              1
#define INCLUDE_uxTaskGetNumberOfTasks       1
#define configUSE_TIMERS                     0
#define configUSE_EVENT_GROUPS               0
#define configUSE_STREAM_BUFFERS             0
#define configUSE_CO_ROUTINES                0
#define configUSE_MUTEXES                    1
#define configUSE_RECURSIVE_MUTEXES          0
#define configUSE_COUNTING_SEMAPHORES        1
#define configUSE_QUEUE_SETS                 0
#define configUSE_TASK_NOTIFICATIONS         1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE            0
#define configENABLE_BACKWARD_COMPATIBILITY  0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0
#define configUSE_MINI_LIST_ITEM             1
#define configMESSAGE_BUFFER_LENGTH_TYPE     size_t
#define configUSE_POSIX_ERRNO                0
#define configCHECK_FOR_STACK_OVERFLOW       2
#define configUSE_MALLOC_FAILED_HOOK         1
#define configUSE_IDLE_HOOK                  0
#define configUSE_TICK_HOOK                  0
#define configGENERATE_RUN_TIME_STATS        0
#define configUSE_TRACE_FACILITY             0
#define configUSE_STATS_FORMATTING_FUNCTIONS 0
/* configASSERT: prototype phai co truoc khi tasks.c dung (ISO C99 tro len). */
void vAssertCalled( const char *pcFile, unsigned long ulLine );
#define configASSERT( x )                    if( ( x ) == 0 ) { vAssertCalled( __FILE__, __LINE__ ); }
#define configSETUP_TICK_INTERRUPT()         vSetupTickInterruptR52()
#define configCLEAR_TICK_INTERRUPT()         vClearTickInterruptR52()
/* portASM.S (viet theo kieu VIC) ghi 1 word vao configEOI_ADDRESS khi ra khoi
 * ngat. GICv3 khong co thanh ghi EOI MMIO -> tro vao mot word dem vo hai
 * (_eoi_scratch trong toolchain/link-r52.ld). EOI that do
 * vApplicationIRQHandler trong freertos_tick_r52.c ghi ICC_EOIR1_EL1. */
#define configEOI_ADDRESS                    ( 0x1001C000UL )
/* Tick: dinh nghia trong src/freertos/freertos_tick_r52.c (GICv3 + CNTP PPI14). */
void vSetupTickInterruptR52( void );
void vClearTickInterruptR52( void );
#define configUSE_TASK_FPU_SUPPORT           2
#endif
EOF
}
# ---- vectors_a76.S: bang vector EL1 (VBAR_EL1) cho FreeRTOS GUEST ----
gen_vectors_a76() {
  if [ ! -f "$FREEDIR/vectors_a76.S" ]; then
    echo "  [gen] vectors_a76.S"; cat > "$FREEDIR/vectors_a76.S" <<'EOF'
/* vectors_a76.S -- 16 o x 128 byte (VBAR_EL1 = bang nay, dat trong xPortStartScheduler).
 *
 *   o 0 (offset 0x00) -> sync  : FreeRTOS_SWI_Handler (portYIELD dung "SVC 0";
 *                                port kiem tra ESR.EC == SVC, khac thi abort)
 *   o 1 (offset 0x80) -> IRQ   : FreeRTOS_IRQ_Handler (tick / nguon khac)
 *   o 2 (offset 0x100)-> FIQ   : khong dung  -> hang_a76
 *   o 3 (offset 0x180)-> SError: loi nghiem trong -> hang_a76
 * (rept 4 = 4 nhom theo EL/SP cua nguon gay exception.)
 */
    .section .text
    .global _freertos_vector_table
    .align 11
_freertos_vector_table:
    .rept 4
    b FreeRTOS_SWI_Handler
    .align 7
    b FreeRTOS_IRQ_Handler
    .align 7
    b hang_a76
    .align 7
    b hang_a76
    .endr
    .global hang_a76
hang_a76:
    b hang_a76
EOF
  fi
}
# ---- freertos_tick_a76.c: GICv2 + Generic Timer vat ly (PPI30) ----
gen_tick_a76() {
  if [ ! -f "$FREEDIR/freertos_tick_a76.c" ]; then
    echo "  [gen] freertos_tick_a76.c"; cat > "$FREEDIR/freertos_tick_a76.c" <<'EOF'
/* freertos_tick_a76.c -- GICv2 + Generic Timer (PPI30) cho QEMU virt.
 *
 * Luong 1 lan tick:
 *   IRQ -> FreeRTOS_IRQ_Handler (portASM.S: save context, doc GICC_IAR,
 *          goi vApplicationIRQHandler(IAR)) -> FreeRTOS_Tick_Handler()
 *          (port.c: goi configCLEAR_TICK_INTERRUPT() = vClearTickInterruptA76)
 *          -> portASM ghi GICC_EOIR bang chinh gia tri IAR da ack.
 *
 * Vi vay vApplicationIRQHandler KHONG duoc doc lai GICC_IAR (IAR chi doc duoc
 * 1 lan: lan doc thu 2 tra ve 1023 = spurious) va KHONG duoc tu ghi EOIR.
 */
#include "FreeRTOS.h"
#include "task.h"

#define GICD_BASE   ( 0x08000000UL )
#define GICC_BASE   ( 0x08010000UL )
#define GICD_CTLR   ( *( volatile unsigned * )( GICD_BASE + 0x000 ) )
#define GICD_ISEN0  ( *( volatile unsigned * )( GICD_BASE + 0x100 ) )
#define GICD_IPR30  ( *( volatile unsigned * )( GICD_BASE + 0x478 ) )
#define GICC_CTLR   ( *( volatile unsigned * )( GICC_BASE + 0x000 ) )
#define GICC_PMR    ( *( volatile unsigned * )( GICC_BASE + 0x004 ) )
#define TICK_PPI    ( 30 )
/* Uu tien GIC cua tick: thap nhat trong 32 muc = 30 << 3 (portPRIORITY_SHIFT) */
#define TICK_PRIORITY   ( 0xF0u )

static unsigned tick_reload;

void vSetupTickInterruptA76( void )
{
    unsigned long freq;

    __asm volatile ( "mrs %0, cntfrq_el0" : "=r" ( freq ) );
    if( freq == 0 ) freq = configCPU_CLOCK_HZ;
    tick_reload = ( unsigned )( freq / ( unsigned long ) configTICK_RATE_HZ );

    /* GICv2 (QEMU virt): GICD @0x08000000, GICC @0x08010000.
     *   GICD_CTLR = 3: view secure -> Grp0|Grp1; view non-secure -> Grp1.
     *   GICC_CTLR = 1: Grp0 (secure) / Grp1 (non-secure) - tick la Grp1.
     *   PMR = 0xFF = portUNMASK_VALUE (port.c) - khong mask gi. */
    GICD_CTLR = 3;
    GICC_CTLR = 1;
    GICC_PMR = 0xFF;
    GICD_IPR30 = ( GICD_IPR30 & ~( 0xFFu << 24 ) ) | ( TICK_PRIORITY << 24 );
    GICD_ISEN0 = ( 1u << TICK_PPI );

    /* Generic Timer vat ly: TVAL = 1 chu ky tick, bat timer (ENABLE=1, IMASK=0). */
    __asm volatile (
        "msr cntp_tval_el0, %0\n"
        "mov x0, #1\n"
        "msr cntp_ctl_el0, x0\n"
        "isb\n" :: "r" ( ( unsigned long ) tick_reload ) : "x0", "memory" );
}

/* Duoc port.c goi (configCLEAR_TICK_INTERRUPT) trong FreeRTOS_Tick_Handler:
 * nap lai TVAL -> ha ISTATUS (xoa nguon ngat) va hen tick ke tiep. */
void vClearTickInterruptA76( void )
{
    __asm volatile ( "msr cntp_tval_el0, %0\n"
                     "isb\n" :: "r" ( ( unsigned long ) tick_reload ) : "memory" );
}

void vApplicationIRQHandler( unsigned long ulICCIAR )
{
    unsigned id = ( unsigned ) ( ulICCIAR & 0x3FFu );

    if( id == TICK_PPI )
    {
        /* FreeRTOS_Tick_Handler() goi configCLEAR_TICK_INTERRUPT() roi
         * xTaskIncrementTick(); portASM.S se ghi EOIR sau khi ham nay tra ve. */
        FreeRTOS_Tick_Handler();
    }
}
EOF
  fi
}
# ---- vectors_r52.S: vector table tai dia chi 0 (SVC->vPortYield, IRQ->tick) ----
gen_vectors_r52() {
  if [ ! -f "$FREEDIR/vectors_r52.S" ]; then
    echo "  [gen] vectors_r52.S"; cat > "$FREEDIR/vectors_r52.S" <<'EOF'
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
EOF
  fi
}
# ---- freertos_tick_r52.c: tick SP804 (TODO: dien dia chi that AN536) ----
gen_tick_r52() {
  if [ ! -f "$FREEDIR/freertos_tick_r52.c" ]; then
    echo "  [gen] freertos_tick_r52.c"; cat > "$FREEDIR/freertos_tick_r52.c" <<'EOF'
/* freertos_tick_r52.c -- GICv3 + Generic Timer (PPI14 = INTID 30) cho
 * QEMU mps3-an536 (Cortex-R52).
 *
 * Khac A76 (GICv2 - MMIO) o 2 cho:
 *   1. GICv3 tach CPU interface ra system register (ICC_*_EL1) va chia phan
 *      theo tung CPU bang redistributor (GICR):
 *        GICD (distributor)  @ 0xF0000000    hw/arm/mps3r.c: PERIPHBASE
 *        GICR (redistributor)@ 0xF0100000, frame SGI/PPI @ +0x10000
 *        doc ICC_IAR1_EL1 / ghi ICC_EOIR1_EL1 (mcr p15,0,...,c12,c12)
 *      => portASM.S (viet theo kieu VIC) chi ghi 1 bien nho vo hai o
 *         configEOI_ADDRESS, nen vApplicationIRQHandler o DAY phai tu doc
 *         IAR va tu ghi EOI that.
 *   2. AN536 la "non-secure only" (R52 khong co EL3 -> GICv3 security_extn
 *      = false, DS = 1): khong co Group0, GICD_CTLR bit1 = EnableGrp1NS.
 *      GICR_IGROUPR0 reset = 0 (Group0) nen phai set bit cua ngat tick -> 1.
 *
 * Luong 1 lan tick:
 *   IRQ -> FreeRTOS_IRQ_Handler (portASM.S: save context + vao IRQ mode)
 *          -> vApplicationIRQHandler()            [doc ICC_IAR1_EL1]
 *               -> FreeRTOS_Tick_Handler()        [port.c]
 *                    -> vClearTickInterruptR52()  [configCLEAR_TICK_INTERRUPT]
 *               -> ghi ICC_EOIR1_EL1 = INTID      [EOI that]
 *
 * Nguon ngat tick = CNTP (physical timer EL1) = INTID 30 = PPI14:
 *   hw/arm/mps3r.c: timer_irq[GTIMER_PHYS] = ARCH_TIMER_NS_EL1_IRQ (= 30,
 *   include/hw/arm/bsa.h).  GICv3: PPI n = INTID 16+n, va cac bitmap cua GICR
 *   (IGROUPR0/ISENABLER0) danh theo INTID -> dung bit 30 cho PPI14.
 */
#include "FreeRTOS.h"
#include "task.h"

/* ---------------- tick: CNTP = INTID 30 = PPI14 ---------------- */
#define TICK_INTID     ( 30 )
#define TICK_BIT       ( 1u << TICK_INTID )
#define INTID_SPURIOUS ( 1023 )
/* Uu tien GICv3: SO NHO = uu tien CAO (nguoc GICv2). 0x00 = cao nhat. */
#define TICK_PRIORITY  ( 0x00u )

/* ---------------- GICv3 (AN536) ---------------- */
#define GICD_BASE       ( 0xF0000000UL )
#define GICR_BASE       ( 0xF0100000UL )            /* CPU0 redistributor    */
#define GICR_SGI        ( GICR_BASE + 0x10000UL )   /* frame SGI/PPI         */

#define GICD_CTLR       ( *( volatile unsigned * )( GICD_BASE + 0x0000 ) )
#define GICR_WAKER      ( *( volatile unsigned * )( GICR_BASE + 0x0014 ) )
#define GICR_IGROUPR0   ( *( volatile unsigned * )( GICR_SGI + 0x0080 ) )
#define GICR_ISENABLER0 ( *( volatile unsigned * )( GICR_SGI + 0x0100 ) )
/* IPRIORITYR: 1 byte cho moi INTID, cua tick la GICR_SGI + 0x400 + 30. */
#define GICR_IPRIORITYR_TICK \
    ( *( volatile unsigned char * )( GICR_SGI + 0x0400 + TICK_INTID ) )

#define GICD_CTLR_EN_GRP1NS       ( 1u << 1 )
#define GICR_WAKER_PROCESSORSLEEP ( 1u << 1 )
#define GICR_WAKER_CHILDRENASLEEP ( 1u << 2 )

static unsigned tick_reload;   /* so chu ky CNTP cho 1 tick */

/* ---- CP15: Generic Timer (c14) + GICv3 CPU interface (c12) ---- */
static inline unsigned gt_read_cntfrq( void )
{
    unsigned v;
    __asm volatile ( "mrc p15, 0, %0, c14, c0, 0" : "=r" ( v ) );
    return v;
}
static inline void gt_write_tval( unsigned v )
{
    __asm volatile ( "mcr p15, 0, %0, c14, c2, 0" :: "r" ( v ) : "memory" );
}
static inline void gt_write_ctl( unsigned v )
{
    __asm volatile ( "mcr p15, 0, %0, c14, c2, 1" :: "r" ( v ) : "memory" );
}
static inline void gi_write_pmr( unsigned v )
{
    __asm volatile ( "mcr p15, 0, %0, c4, c6, 0" :: "r" ( v ) : "memory" );
}
static inline void gi_write_igrpen1( unsigned v )
{
    __asm volatile ( "mcr p15, 0, %0, c12, c12, 7" :: "r" ( v ) : "memory" );
}
static inline unsigned gi_read_iar1( void )
{
    unsigned v;
    __asm volatile ( "mrc p15, 0, %0, c12, c12, 0" : "=r" ( v ) );
    return v;
}
static inline void gi_write_eoir1( unsigned v )
{
    __asm volatile ( "mcr p15, 0, %0, c12, c12, 1" :: "r" ( v ) : "memory" );
}

void vSetupTickInterruptR52( void )
{
    unsigned long freq = gt_read_cntfrq();
    unsigned long spin;

    /* CNTFRQ doc tu phan cung (QEMU R52: 62.5 MHz - GTIMER_BACKCOMPAT_HZ);
     * configCPU_CLOCK_HZ chi la gia tri du phong khi CNTFRQ = 0. */
    if( freq == 0 )
    {
        freq = ( unsigned long ) configCPU_CLOCK_HZ;
    }
    tick_reload = ( unsigned ) ( freq / ( unsigned long ) configTICK_RATE_HZ );

    /* 1) Thuc day redistributor CPU0 (reset: ProcessorSleep|ChildrenAsleep = 1;
     *    chua thuc day thi GICR khong day ngat ra CPU interface). */
    GICR_WAKER &= ~GICR_WAKER_PROCESSORSLEEP;
    for( spin = 0;
         ( ( GICR_WAKER & GICR_WAKER_CHILDRENASLEEP ) != 0 ) && ( spin < 1000000UL );
         spin++ )
    {
    }

    /* 2) PPI14: Group1 (khong phai Group0) + uu tien + cho phep. */
    GICR_IGROUPR0        |= TICK_BIT;
    GICR_IPRIORITYR_TICK  = ( unsigned char ) TICK_PRIORITY;
    GICR_ISENABLER0       = TICK_BIT;

    /* 3) Bat Group1 non-secure o distributor (GICD_CTLR.EnableGrp1NS). */
    GICD_CTLR |= GICD_CTLR_EN_GRP1NS;

    /* 4) CPU interface: PMR = 0xFF = portUNMASK_VALUE (port.c) - khong mask
     *    ngat nao; bat Group1 (ICC_IGRPEN1_EL1). */
    gi_write_pmr( 0xFFu );
    gi_write_igrpen1( 1u );

    /* 5) CNTP: hen tick dau tien (TVAL = 1 chu ky) roi bat (ENABLE=1, IMASK=0). */
    gt_write_tval( tick_reload );
    gt_write_ctl( 1u );
    __asm volatile ( "isb" ::: "memory" );
}
/* Duoc port.c goi (configCLEAR_TICK_INTERRUPT) trong FreeRTOS_Tick_Handler:
 * nap lai TVAL -> ha ISTATUS (xoa nguon ngat) va hen tick ke tiep. */
void vClearTickInterruptR52( void )
{
    gt_write_tval( tick_reload );
    __asm volatile ( "isb" ::: "memory" );
}

void vApplicationIRQHandler( unsigned long ulICCIAR )
{
    unsigned id;

    ( void ) ulICCIAR;              /* portASM.S chi truyen gia tri vo nghia
                                     * (kieu VIC); GICv3 doc IAR bang system
                                     * register nen phai tu doc o day. */
    id = gi_read_iar1() & 0x3FFu;   /* ICC_IAR1_EL1[9:0] = INTID */

    if( id == INTID_SPURIOUS )      /* 1023: khong co ngat -> khong EOI */
    {
        return;
    }

    if( id == TICK_INTID )          /* CNTP (PPI14): FreeRTOS_Tick_Handler()
                                     * goi configCLEAR_TICK_INTERRUPT() */
    {
        FreeRTOS_Tick_Handler();
    }

    /* EOI that: portASM.S khi ra khoi ngat chi ghi configEOI_ADDRESS (bien
     * nho vo hai tren GICv3), nen phai ghi ICC_EOIR1_EL1 o day. */
    gi_write_eoir1( id );
    __asm volatile ( "isb" ::: "memory" );
}

void vApplicationSVCHandler( unsigned long n ) { ( void ) n; }
EOF
  fi
}
# ---- libgcc_r52.c: helper chia so nguyen ma clang sinh (khong co libgcc) ----
gen_libgcc_r52() {
  if [ ! -f "$FREEDIR/libgcc_r52.c" ]; then
    echo "  [gen] libgcc_r52.c"; cat > "$FREEDIR/libgcc_r52.c" <<'EOF'
/* libgcc_r52.c -- vai helper chia so nguyen ma clang sinh ra cho AArch32
 * nhung khong co cho lay (build bare-metal, link thang bang ld.lld, khong co
 * libgcc/compiler-rt).
 *
 * Vi sao can: profile r52 bien dich bang "-march=armv7-a" (config.sh:
 * thumb-r52) -- ARMv7-A KHONG bat buoc co lenh chia (UDIV/SDIV chi bat buoc
 * tu ARMv7VE / ARMv8-R).  Voi so chia la HANG SO clang tu doi thanh nhan+shift
 * (vi du k_putdec() dung '% 10' van chay duoc, os-r52.elf cua demOS khong can
 * file nay), nhung khi so chia la BIEN thi phai goi helper:
 *
 *     tasks.c (xTaskDelayUntil):  xIncrements = xTicksElapsed / xTimeIncrement;
 *     -> ld.lld: undefined symbol: __aeabi_uidiv
 *
 * ABI (giong libgcc, AAPCS): tham so o r0/r1; ket qua
 *     __aeabi_uidiv(a,b)     -> r0 = a / b
 *     __aeabi_uidivmod(a,b)  -> r0 = a / b (quot), r1 = a % b (rem)
 *     __aeabi_idiv(a,b)      -> r0 = a / b    (co dau)
 *     __aeabi_idivmod(a,b)   -> r0 = a / b,  r1 = a % b (co dau)
 * Clang goi __aeabi_*divmod va lay quotient o r0, remainder o r1 -> dung
 * struct 2 word tra ve o r0/r1 la khop ABI.
 *
 * Cai dat: chia nhi phan "dich + tru" (khong dung phep chia nao => khong tu
 * goi lai chinh no), 32 vong lap, uu tien de doc/dung.  Chia cho 0 tra ve 0
 * thay vi treo (chia 0 la UB trong C, o day chi can khong ket vong lap).
 */

typedef struct
{
    unsigned quot;  /* r0: thuong  */
    unsigned rem;   /* r1: phan du */
} udivmod_t;

/* Thuong + du cua phep chia KHONG dau: restoring division 32 bit. */
static udivmod_t prvUdivmod( unsigned num, unsigned den )
{
    udivmod_t r;
    unsigned quot = 0;
    unsigned rem  = 0;
    int i;

    r.quot = 0;
    r.rem  = 0;

    if( den == 0 )
    {
        return r;
    }

    for( i = 31; i >= 0; i-- )
    {
        rem = ( rem << 1 ) | ( ( num >> i ) & 1u );
        if( rem >= den )
        {
            rem  -= den;
            quot |= ( 1u << i );
        }
    }

    r.quot = quot;
    r.rem  = rem;
    return r;
}

unsigned __aeabi_uidiv( unsigned num, unsigned den )
{
    return prvUdivmod( num, den ).quot;
}

udivmod_t __aeabi_uidivmod( unsigned num, unsigned den )
{
    return prvUdivmod( num, den );
}

/* Co dau: lam viec tren tri tuyet doi roi chinh dau lai cho khop C99
 * (thuong lam tron ve 0, du cung dau voi so bi chia). */
int __aeabi_idiv( int num, int den )
{
    unsigned un, ud;
    int q;

    un = ( num < 0 ) ? ( unsigned ) ( -num ) : ( unsigned ) num;
    ud = ( den < 0 ) ? ( unsigned ) ( -den ) : ( unsigned ) den;
    q  = ( int ) prvUdivmod( un, ud ).quot;

    if( ( num < 0 ) != ( den < 0 ) )
    {
        q = -q;
    }
    return q;
}

udivmod_t __aeabi_idivmod( int num, int den )
{
    unsigned un, ud;
    udivmod_t r;

    un  = ( num < 0 ) ? ( unsigned ) ( -num ) : ( unsigned ) num;
    ud  = ( den < 0 ) ? ( unsigned ) ( -den ) : ( unsigned ) den;
    r   = prvUdivmod( un, ud );

    if( ( num < 0 ) != ( den < 0 ) )                /* thuong: khac dau  */
    {
        r.quot = ( unsigned ) -( int ) r.quot;
    }
    if( num < 0 )                                   /* du: cung dau voi num */
    {
        r.rem = ( unsigned ) -( int ) r.rem;
    }
    return r;
}
EOF
  fi
}
# ---- hooks.c: 5 hook + configASSERT qua UART ----
gen_hooks() {
  if [ ! -f "$FREEDIR/hooks.c" ]; then
    echo "  [gen] hooks.c"; cat > "$FREEDIR/hooks.c" <<'EOF'
/* hooks.c -- hook + ASSERT, xuat qua UART san co (k_puts/k_putdec). */
#include "FreeRTOS.h"
#include "task.h"
#include "os.h"
void vAssertCalled( const char *file, unsigned long line )
{
    k_puts( "\r\nASSERT " ); k_puts( file ); k_puts( " :" );
    k_putdec( ( unsigned ) line ); k_puts( "\r\n" );
    taskDISABLE_INTERRUPTS();
    for( ;; );
}
void vApplicationStackOverflowHook( TaskHandle_t t, char *n ) { ( void ) t; k_puts( "\r\nSTACK-OVF " ); k_puts( n ); k_puts( "\r\n" ); taskDISABLE_INTERRUPTS(); for( ;; ); }
void vApplicationMallocFailedHook( void ) { k_puts( "\r\nMALLOC-FAIL\r\n" ); taskDISABLE_INTERRUPTS(); for( ;; ); }
void vApplicationGetIdleTaskMemory( StaticTask_t **tcb, StackType_t **st, configSTACK_DEPTH_TYPE *sz )
{ static StaticTask_t xT; static StackType_t xS[ configMINIMAL_STACK_SIZE ]; *tcb = &xT; *st = xS; *sz = configMINIMAL_STACK_SIZE; }
void vApplicationGetTimerTaskMemory( StaticTask_t **tcb, StackType_t **st, configSTACK_DEPTH_TYPE *sz )
{
#if ( configUSE_TIMERS == 1 )
    static StaticTask_t xT; static StackType_t xS[ configTIMER_TASK_STACK_DEPTH ];
    *tcb = &xT; *st = xS; *sz = configTIMER_TASK_STACK_DEPTH;
#else
    ( void ) tcb; ( void ) st; ( void ) sz;
#endif
}
EOF
  fi
}
# ---- libc_mini.c: memset/memcpy/... cho -nostdlib ----
gen_libc() {
  if [ ! -f "$FREEDIR/libc_mini.c" ]; then
    echo "  [gen] libc_mini.c"; cat > "$FREEDIR/libc_mini.c" <<'EOF'
/* libc_mini.c -- kernel goi memset/memcpy/strlen... nhung -nostdlib khong co. */
#include <stddef.h>
void *memset( void *d, int c, size_t n ) { unsigned char *p = d; while( n-- ) *p++ = ( unsigned char ) c; return d; }
void *memcpy( void *d, const void *s, size_t n ) { unsigned char *p = d; const unsigned char *q = s; while( n-- ) *p++ = *q++; return d; }
int memcmp( const void *a, const void *b, size_t n ) { const unsigned char *p = a, *q = b; while( n-- ) { if( *p != *q ) return *p - *q; p++; q++; } return 0; }
size_t strlen( const char *s ) { size_t n = 0; while( *s++ ) n++; return n; }
char *strcpy( char *d, const char *s ) { char *p = d; while( ( *p++ = *s++ ) != '\0' ) { } return d; }
int strcmp( const char *a, const char *b ) { while( *a && *a == *b ) { a++; b++; } return ( unsigned char ) *a - ( unsigned char ) *b; }
EOF
  fi
}
# ---- app_main.c: producer -> queue -> consumer (chay ca 2 profile) ----
gen_app() {
  if [ ! -f "$FREEDIR/app_main.c" ]; then
    echo "  [gen] app_main.c"; cat > "$FREEDIR/app_main.c" <<'EOF'
/* app_main.c -- app mau FreeRTOS: 2 task + 1 queue. */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "os.h"
static QueueHandle_t xQ;
static void vProd( void *p ) { unsigned n = 0; ( void ) p; for( ;; ) { xQueueSend( xQ, &n, portMAX_DELAY ); n++; vTaskDelay( pdMS_TO_TICKS( 200 ) ); } }
static void vCons( void *p ) { unsigned v; ( void ) p; for( ;; ) if( xQueueReceive( xQ, &v, portMAX_DELAY ) == pdPASS ) { k_puts( "got " ); k_putdec( v ); k_puts( "\r\n" ); } }

/* Cho phep FP/SIMD truoc khi chay bat ky code C nao.
 *
 * Ly do (da debug tren QEMU): sau reset CPACR.FPEN = 0, moi lenh FP/SIMD deu
 * sinh exception. Clang -O2 tu vector hoa vong lap trong libc_mini.c
 * (memset -> "dup v0.16b, w1"), ma port ARM_AARCH64 lai bat
 * configUSE_TASK_FPU_SUPPORT = 2 (moi task co context FPU) => phai mo FP.
 */
static void vPortEnableFPU( void )
{
#if defined( __aarch64__ )
    __asm volatile ( "mrs x0, cpacr_el1 \n"
                     "orr x0, x0, #( 3 << 20 ) \n"   /* FPEN = 0b11: EL0/EL1 khong trap */
                     "msr cpacr_el1, x0 \n"
                     "isb \n" ::: "x0", "memory" );
#elif defined( __arm__ )
    /* AArch32: CPACR co HAI field rieng -- CP10 (bit 21:20, D0-D15) va
     * CP11 (bit 23:22, D16-D31). Phai bat CA HAI = 0b11, thieu mot
     * cai la moi lenh VFP/NEON thanh Undefined Instruction. Clang vector hoa
     * bang q8..q15 (= D16+) -- vi du "vdup.8 q8, r1" trong memset -- nen chi
     * bat CP10 la chet ngay sau khi in banner:
     *   Taking exception 1 [Undefined Instruction] ... ESR 0x0/0x2000000 */
    __asm volatile ( "mrc p15, 0, r0, c1, c0, 2 \n"
                     "orr r0, r0, #( 0xf << 20 ) \n"  /* CP10 = CP11 = 0b11 */
                     "mcr p15, 0, r0, c1, c0, 2 \n"
                     "isb \n" ::: "r0", "memory" );
#endif
}

void k_os_entry( void )
{
    vPortEnableFPU();       /* phai la viec dau tien (xem chu thich tren) */
    k_puts( "freertos bring-up\r\n" );
    xQ = xQueueCreate( 8, sizeof( unsigned ) );
    configASSERT( xQ != NULL );
    xTaskCreate( vProd, "prod", 256, NULL, 2, NULL );
    xTaskCreate( vCons, "cons", 256, NULL, 1, NULL );
    vTaskStartScheduler();
    configASSERT( 0 );
}
EOF
  fi
}
# ---- include-compat: stdlib.h/string.h/... toi thieu cho -nostdlib ----
gen_compat() {
  if [ ! -f "$FREEDIR/compat/stdlib.h" ]; then
    echo "  [gen] compat/*.h"; mkdir -p "$FREEDIR/compat"; cat > "$FREEDIR/compat/stdlib.h" <<'EOF'
/* stdlib.h toi thieu cho FreeRTOS freestanding (tasks.c can NULL/size_t). */
#ifndef COMPAT_STDLIB_H
#define COMPAT_STDLIB_H
#include <stddef.h>
#define NULL ( ( void * ) 0 )
#define RAND_MAX 0x7fffffff
static inline int abs( int j ) { return j < 0 ? -j : j; }
static inline long labs( long j ) { return j < 0 ? -j : j; }
void *malloc( unsigned long n );
void free( void *p );
void *calloc( unsigned long n, unsigned long s );
void *realloc( void *p, unsigned long n );
#endif
EOF
  fi
cat > "$FREEDIR/compat/string.h" <<'EOF'
/* string.h toi thieu cho FreeRTOS freestanding (memset/memcpy/strlen...). */
#ifndef COMPAT_STRING_H
#define COMPAT_STRING_H
#include <stddef.h>
void *memset( void *d, int c, size_t n );
void *memcpy( void *d, const void *s, size_t n );
int memcmp( const void *a, const void *b, size_t n );
size_t strlen( const char *s );
char *strcpy( char *d, const char *s );
int strcmp( const char *a, const char *b );
#endif
EOF
cat > "$FREEDIR/compat/stdio.h" <<'EOF'
/* stdio.h toi thieu (tasks.c chi can khi configUSE_STATS... bat). */
#ifndef COMPAT_STDIO_H
#define COMPAT_STDIO_H
#include <stddef.h>
int sprintf( char *s, const char *f, ... );
#endif
EOF
}
# --PART9--
# ================= build 1 profile -> os-<p>-freertos.elf =================
build_one_freertos() {
  local p="$1"
  local w="$BUILD/$p"
  local triple thumbopt cpu machine uart uarttype stacktop portdir heap
  triple=$(pcfg triple-$p); thumbopt=$(pcfg thumb-$p)
  cpu=$(pcfg cpu-$p); machine=$(pcfg machine-$p)
  uart=$(pcfg uart-$p); uarttype=$(pcfg uarttype-$p); stacktop=$(pcfg stacktop-$p)
  if [ "$p" = a76 ]; then portdir="$FR/portable/GCC/ARM_AARCH64"; heap="$FR/portable/MemMang/heap_4.c";
  else portdir="$FR/portable/GCC/ARM_CRx_No_GIC"; heap="$FR/portable/MemMang/heap_1.c"; fi
  [ -d "$FR/.git" ] || die "thieu FreeRTOS-Kernel -- chay: ./run_os.sh get free-rtos"
  mkdir -p "$FREEDIR" "$w"
  if [ ! -f "$FREEDIR/FreeRTOSConfig-$p.h" ]; then
    echo "  [gen] FreeRTOSConfig-$p.h"; if [ "$p" = a76 ]; then gen_config_a76; else gen_config_r52; fi
  fi
  if [ "$p" = a76 ]; then gen_vectors_a76; gen_tick_a76; else gen_vectors_r52; gen_tick_r52; gen_libgcc_r52; fi
  gen_hooks; gen_libc; gen_compat; gen_app
  printf '\n== freertos build [%s] %s (%s) ==\n' "$p" "$cpu" "$machine"
  local cflags="-O2 -Wall -Wextra -g -ffreestanding -fno-builtin -nostdlib"
  # File .C (kernel/FreeRTOS/glue) KHONG duoc dung FP/SIMD: clang -O2 tung vector
  # hoa pxPortInitialiseStack thanh "stur q0,[x0,#-0x28]" -> alignment fault
  # (128-bit store doi dia chi 16-byte, trong khi pxTopOfStack chi 8-byte).
  # Context FPU cua task do portASM.S (asm) lo, khong phai code C.
  # -mstrict-align: MMU dang tat nen moi access la Device memory -> moi truy cap
  # lech hang (vi du "stur xzr,[x29,#-0xb]" khi khoi tao vung nho 13 byte)
  # deu sinh Alignment fault. Cam clang phat sinh access lech hang.
  # (-mgeneral-regs-only chi co tren clang AArch64, khong co cho arm-none-eabi.)
  local cflags_c="$cflags -mstrict-align"
  [ "$p" = a76 ] && cflags_c="$cflags_c -mgeneral-regs-only"
  local defs="-DUART_BASE=$uart -DUART_TYPE=$uarttype -DPLAT_CPU=\"$cpu\" -DPLAT_MACHINE=\"$machine\" -DPLAT_STACKTOP=$stacktop"
  local clanginc=""; command -v "$CLANG" >/dev/null 2>&1 && clanginc="-isystem $("$CLANG" -print-resource-dir 2>/dev/null)/include"
  cp "$FREEDIR/FreeRTOSConfig-$p.h" "$w/FreeRTOSConfig.h"
  # $w phai nam trong -I de moi file FreeRTOS tim thay "FreeRTOSConfig.h"
  local inc="-nostdinc $clanginc -isystem $FREEDIR/compat -I$w -I$SRC/kernel -I$FREEDIR -I$FR/include -I$portdir"
  # -include string.h (chi cho file .C): port.c goi memset nhung chi include <stdlib.h>
  local cinc="$inc -include string.h"
  # 1) boot+uart+libc: R52 dung vectors_r52.S (da co _start) thay start_r52.S
  if [ "$p" = a76 ]; then
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags "$SRC/boot/start_$p.S" -o "$w/f_start.o"
  else
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags "$FREEDIR/vectors_r52.S" -o "$w/f_start.o"
  fi
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$SRC/kernel/uart.c" -o "$w/f_uart.o"
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$FREEDIR/libc_mini.c" -o "$w/f_libc.o"
  # 2) nhan FreeRTOS: tasks+list+queue (timer/event/stream tat o config)
  local f
  for f in tasks list queue; do
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $cinc "$FR/$f.c" -o "$w/f_$f.o"
  done
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $cinc "$heap" -o "$w/f_heap.o"
  # 3) port (A64 can -DGUEST de chay EL1/SVC)
  local portdefs=""; [ "$p" = a76 ] && portdefs="-DGUEST -DQEMU"
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $portdefs $cinc "$portdir/port.c" -o "$w/f_port.o"
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags $portdefs "$portdir/portASM.S" -o "$w/f_portasm.o"
  # 4) glue: tick + vectors(a76) + hooks + app
  if [ "$p" = a76 ]; then
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$FREEDIR/freertos_tick_a76.c" -o "$w/f_tick.o"
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags $defs $inc "$FREEDIR/vectors_a76.S" -o "$w/f_vectors.o"
  else
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$FREEDIR/freertos_tick_r52.c" -o "$w/f_tick.o"
    # helper chia + phep chia co dau (clang AArch32 sinh loi goi __aeabi_*div)
    # shellcheck disable=SC2086
    run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $cinc "$FREEDIR/libgcc_r52.c" -o "$w/f_libgcc.o"
  fi
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$FREEDIR/hooks.c" -o "$w/f_hooks.o"
  # shellcheck disable=SC2086
  run "$CLANG" --target="$triple" $thumbopt -c $cflags_c $defs $cinc "$FREEDIR/app_main.c" -o "$w/f_app.o"
  # 5) link (-e _start, .ld giu nguyen dia chi demOS)
  [ -n "${LLD:-}" ] && [ -x "$LLD" ] || die "thieu ld.lld -- chay: ./run_os.sh setup"
  local objs="$w/f_start.o $w/f_uart.o $w/f_libc.o $w/f_tasks.o $w/f_list.o $w/f_queue.o $w/f_heap.o $w/f_port.o $w/f_portasm.o $w/f_tick.o $w/f_hooks.o $w/f_app.o"
  [ "$p" = a76 ] && objs="$objs $w/f_vectors.o"
  [ "$p" = r52 ] && objs="$objs $w/f_libgcc.o"
  # shellcheck disable=SC2086
  run "$LLD" -o "$w/os-$p-freertos.elf" -e _start -T "$HERE/toolchain/$(pcfg ld-$p)" $objs
  if command -v llvm-objdump >/dev/null 2>&1; then
    llvm-objdump -d "$w/os-$p-freertos.elf" > "$w/os-$p-freertos.list"
  elif [ -x "$LLVM_PREFIX/bin/llvm-objdump" ]; then
    "$LLVM_PREFIX/bin/llvm-objdump" -d "$w/os-$p-freertos.elf" > "$w/os-$p-freertos.list"
  fi
  printf '   -> %s (%s)\n' "$w/os-$p-freertos.elf" "$(du -h "$w/os-$p-freertos.elf" | cut -f1)"
  if [ "$p" = r52 ]; then
    echo '   NOTE r52: ngat tick = CNTP (INTID 30 = PPI14) qua GICv3; portASM.S ghi'
    echo '            EOI kieu VIC vao configEOI_ADDRESS = _eoi_scratch (0x1001C000)'
    echo '            -- EOI that do vApplicationIRQHandler ghi ICC_EOIR1_EL1.'
  fi
}
# ================= CLI =================
case "${1:-a76}" in
  a76 | r52) build_one_freertos "$1" ;;
  all) build_one_freertos a76; build_one_freertos r52 ;;
  clean) rm -rf "$BUILD/a76/os-a76-freertos"* "$BUILD/a76/f_"* "$BUILD/r52/os-r52-freertos"* "$BUILD/r52/f_"* 2>/dev/null; echo "cleaned freertos artifacts (demOS os-<p>.elf giu nguyen)" ;;
  help|-h|--help) sed -n '2,5p' "$0" ;;
  *) echo "dung: $0 [a76|r52|all|clean]" >&2; exit 2 ;;
esac
