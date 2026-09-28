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
