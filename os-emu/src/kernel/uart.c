/* uart.c — bare-metal serial driver for the two chip platforms.
 *
 *   Cortex-A76 (QEMU "virt")          -> ARM PrimeCell PL011 @ 0x09000000
 *   Cortex-R52 (QEMU "mps3-an536")    -> CMSDK/APB style UART @ 0xE7C00000
 *
 * Selected at build time:  -DUART_TYPE=1 | 2   (config.sh profile)
 *   (1 = pl011, 2 = cmsdk; integers, because testing identifiers that are
 *    both #if-undefined always yields "equal")
 */
#include "os.h"

#define UART_PL011 1
#define UART_CMSDK 2
#ifndef UART_TYPE
#define UART_TYPE UART_PL011
#endif

#if UART_TYPE == UART_PL011
/* ---------------------------------------------------------------
 * ARM PrimeCell PL011
 *   UARTDR   @ base+0x00  (write: transmits a character)
 *   UARTFR   @ base+0x18  (flags; bit5 = TX FIFO full)
 *   UARTCR   @ base+0x30  (UART enable, TX enable, RX enable, OUT2)
 *   UARTLCRH @ base+0x2c  (FEN = enable FIFOs)
 * --------------------------------------------------------------- */
#define PL_DR(B)   (*(volatile unsigned int *)((B) + 0x00))
#define PL_FR(B)   (*(volatile unsigned int *)((B) + 0x18))
#define PL_Cr(B)   (*(volatile unsigned int *)((B) + 0x30))
#define PL_LCR(B)  (*(volatile unsigned int *)((B) + 0x2c))
#define PL_CR_UARTEN (1u << 0)
#define PL_CR_TXE    (1u << 8)
#define PL_CR_RXE    (1u << 9)
#define PL_CR_OUT2   (1u << 13)
#define PL_LCR_FEN   (1u << 4)
#define PL_FR_TXFF   (1u << 5)

static void uart_write(char c)
{
    unsigned long b = (unsigned long)UART_BASE;
    PL_Cr(b)  = PL_CR_UARTEN | PL_CR_TXE | PL_CR_RXE | PL_CR_OUT2;
    PL_LCR(b) = PL_LCR_FEN;
    for (int i = 0; (PL_FR(b) & PL_FR_TXFF) && (i < 64); i++) {
        /* wait for the TX FIFO to drain (bounded, no deadlock) */
    }
    PL_DR(b) = (unsigned char)c;
}

#else
/* ---------------------------------------------------------------
 * CMSDK / APB style UART (used by the AN536 / Cortex-R52 image)
 *   UART_DATA    @ base+0x00   UART_STATE @ base+0x04
 *   UART_CTRL    @ base+0x08   UART_BAUDDIV @ base+0x10
 * --------------------------------------------------------------- */
#define U_DATA(B)  (*(volatile unsigned int *)((B) + 0x00))
#define U_STATE(B) (*(volatile unsigned int *)((B) + 0x04))
#define U_CTRL(B)  (*(volatile unsigned int *)((B) + 0x08))
#define U_BAUD(B)  (*(volatile unsigned int *)((B) + 0x10))

static void uart_write(char c)
{
    unsigned long b = (unsigned long)UART_BASE;
    U_CTRL(b) = 0;
    U_BAUD(b) = 434;                        /* 115200 baud */
    U_CTRL(b) = (1u << 0) | (1u << 1) | (1u << 2);
    for (int i = 0; (U_STATE(b) & (1u << 0)) && (i < 64); i++) {
        /* wait while TX is busy (bounded) */
    }
    U_DATA(b) = (unsigned char)c;
}
#endif

void k_putc(char c) { uart_write(c); }

void k_puts(const char *s)
{
    while (*s) {
        k_putc(*s++);
    }
}

void k_crlf(void)
{
    k_putc('\r');
    k_putc('\n');
}

void k_puthex(unsigned int v)
{
    static const char *h = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4) {
        k_putc(h[(v >> i) & 0xf]);
    }
}

void k_putdec(unsigned int v)
{
    char buf[12];
    int n = 0;
    if (v == 0) {
        k_putc('0');
        return;
    }
    while (v) {
        buf[n++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (n) {
        k_putc(buf[--n]);
    }
}

void k_yield(void) { /* cooperative yield: return to the scheduler */ }