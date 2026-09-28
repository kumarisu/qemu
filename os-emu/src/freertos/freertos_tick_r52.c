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
