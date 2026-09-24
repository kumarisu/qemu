/* os.h — chip-emu demOS kernel interface (bare-metal, no libc) */
#ifndef CHIPEMU_OS_H
#define CHIPEMU_OS_H

#ifndef UART_BASE
#error "UART_BASE must be defined at build time (config.sh profile)"
#endif

/* kernel entry (called from the boot glue in src/boot)               */
void k_os_entry(void);

/* serial / debug UART (platform driver in uart.c)                    */
void k_putc(char c);
void k_puts(const char *s);
void k_crlf(void);
void k_puthex(unsigned int v);
void k_putdec(unsigned int v);

/* scheduler / runtime helpers                                        */
void k_yield(void);          /* cooperative yield (returns immediately) */
void k_halt(void);           /* enter low-power loop / hang             */

#endif /* CHIPEMU_OS_H */