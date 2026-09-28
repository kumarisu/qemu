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
