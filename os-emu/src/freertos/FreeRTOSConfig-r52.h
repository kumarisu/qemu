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
