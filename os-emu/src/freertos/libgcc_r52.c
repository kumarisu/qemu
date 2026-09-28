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
