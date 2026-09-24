/* kernel.c — chip-emu demOS
 *
 *  A tiny cooperative real-time style kernel (no libc, freestanding) that
 *  we build for BOTH chip profiles and boot straight on QEMU:
 *
 *     cortex-a76  -> qemu-system-aarch64 -M virt -cpu cortex-a76  -kernel ...
 *     cortex-r52  -> qemu-system-arm     -M mps3-an536            -kernel ...
 *
 *  Features demonstrated:
 *     * platform banner (cpu / machine / uart / memory map)
 *     * round-robin scheduler with one private stack per task
 *     * task switching by explicit yield (cooperative)
 *
 *  Build-time macros (set by run_os.sh from config.sh):
 *     UART_BASE    platform UART base address
 *     UART_TYPE    pl011 | cmsdk
 *     PLAT_CPU     "cortex-a76" | "cortex-r52"
 *     PLAT_MACHINE "virt" | "mps3-an536"
 *     PLAT_STACKTOP initial stack pointer value
 */
#include "os.h"

#ifndef PLAT_CPU
#define PLAT_CPU "unknown-cpu"
#endif
#ifndef PLAT_MACHINE
#define PLAT_MACHINE "unknown-machine"
#endif
#ifndef PLAT_STACKTOP
#define PLAT_STACKTOP 0u
#endif

#define NTASKS        2u
#define STACK_WORDS   32u

/* --- task stacks (in .bss; QEMU starts the RAM zeroed) ------------- */
static volatile unsigned int stack0[STACK_WORDS];
static volatile unsigned int stack1[STACK_WORDS];

static unsigned int tick;          /* scheduler uptime (quanta)      */
static unsigned int cnt_a;         /* private counters per task      */
static unsigned int cnt_b;

/* --- register helpers (bare-metal, stable addresses on both chips) -- */
static unsigned long area_top(const volatile unsigned int *s)
{
    return (unsigned long)(const void *)(s + STACK_WORDS);
}

/* implemented in the boot glue (src/boot/start_*.S): x31 := x0 */
extern void k_stack_push(unsigned long top);

static void task_stack_push(unsigned int t)
{
    /* point sp (x31) at the task's own stack area before it runs */
    k_stack_push((t == 0u) ? area_top(stack0) : area_top(stack1));
}

/* ------------------------------------------------------------------ */
/*  the two "processes" — each runs one quantum then cooperatively
 *  yields back to the scheduler (which switches the stack + task)      */
static void task_a(void)
{
    k_puts("  [taskA] quantum ");
    k_putdec(cnt_a++);
    k_puts("  -> private stack @0x");
    k_puthex(area_top(stack0) - STACK_WORDS * 4u);
    k_puts(" alpha\r\n");
}

static void task_b(void)
{
    k_puts("  [taskB] quantum ");
    k_putdec(cnt_b++);
    k_puts("  -> private stack @0x");
    k_puthex(area_top(stack1) - STACK_WORDS * 4u);
    k_puts(" beta\r\n");
}

/* ------------------------------------------------------------------ */
static void scheduler_roundrobin(void)
{
    for (;;) {
        unsigned int t = tick % NTASKS;
        tick++;

        task_stack_push(t);          /* switch to that task's stack    */
        k_yield();                   /* cooperative context switch     */
        if (t == 0u) {
            task_a();
        } else {
            task_b();
        }

        if (tick >= 16u) {           /* demo: stop after N quanta      */
            break;
        }
    }

    k_crlf();
    k_puts("[chip-emu] DEMO-OS-OK  ");
    k_putdec(tick);
    k_puts(" quanta scheduled by cooperative round-robin on ");
    k_puts(PLAT_CPU);
    k_puts(" / ");
    k_puts(PLAT_MACHINE);
    k_putc('.');
    k_crlf();
}

static void print_banner(void)
{
    k_crlf();
    k_puts("  +-------------------------------------------------------+\r\n");
    k_puts("  |  chip-emu demOS v0.1   (bare-metal, no libc)          |\r\n");
    k_puts("  +-------------------------------------------------------+\r\n");
    k_puts("  cpu        : ");
    k_puts(PLAT_CPU);
    k_crlf();
    k_puts("  machine    : ");
    k_puts(PLAT_MACHINE);
    k_crlf();
    k_puts("  uart       : 0x");
    k_puthex((unsigned int)UART_BASE);
    k_crlf();
    k_puts("  stack top  : 0x");
    k_puthex((unsigned int)PLAT_STACKTOP);
    k_crlf();
    k_puts("  tasks      : ");
    k_putdec(NTASKS);
    k_puts(" cooperative, round-robin, one private stack per task\r\n");
    k_puts("  ---------------------------------------------------------\r\n");
}

void k_os_entry(void)
{
    print_banner();
    k_puts("[chip-emu] scheduler starts\r\n");
    scheduler_roundrobin();
    k_halt();                        /* unreachable: scheduler halts   */
}

void k_halt(void)
{
    for (;;) {
        /* low-power wait-for-interrupt loop (no interrupts enabled) */
    }
}