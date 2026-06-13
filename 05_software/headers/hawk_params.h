#ifndef HAWK_PARAMS_H
#define HAWK_PARAMS_H

/*
 * ============================================================
 * Selección de conjunto de parámetros
 * ============================================================
 */

//#define HAWK_256
#define HAWK_512
//#define HAWK_1024

/*
 * ============================================================
 * Parámetros específicos
 * ============================================================
 */

#ifdef HAWK_256

    #define HAWK_NAME                "HAWK-256"

    #define HAWK_LAMBDA              64

    #define HAWK_N                   256

    #define HAWK_QS                  (1ULL << 32)

    #define HAWK_ETA                 2

    #define HAWK_SIGMA_SIGN          1010
    #define HAWK_SIGMA_VERIFY        1042
    #define HAWK_SIGMA_KREC          1042

    #define HAWK_SALTLEN_BITS        112

    #define HAWK_KGSEED_BITS         128
    #define HAWK_HPUB_BITS           128

    #define HAWK_Q00_LOW_BITS        5
    #define HAWK_Q00_HIGH_BITS       9

    #define HAWK_Q01_LOW_BITS        8
    #define HAWK_Q01_HIGH_BITS       11

    #define HAWK_Q11_BITS            13

    #define HAWK_S0_HIGH_BITS        12

    #define HAWK_S1_LOW_BITS         5
    #define HAWK_S1_HIGH_BITS        9

    #define HAWK_BETA0_NUM           1
    #define HAWK_BETA0_DEN           250

#endif

#ifdef HAWK_512

    #define HAWK_NAME                "HAWK-512"

    #define HAWK_LAMBDA              128

    #define HAWK_N                   512

    #define HAWK_QS                  (1ULL << 64)

    #define HAWK_ETA                 4

    #define HAWK_SIGMA_SIGN          1278
    #define HAWK_SIGMA_VERIFY        1425
    #define HAWK_SIGMA_KREC          1425

    #define HAWK_SALTLEN_BITS        192

    #define HAWK_KGSEED_BITS         192
    #define HAWK_HPUB_BITS           256

    #define HAWK_Q00_LOW_BITS        5
    #define HAWK_Q00_HIGH_BITS       9

    #define HAWK_Q01_LOW_BITS        9
    #define HAWK_Q01_HIGH_BITS       12

    #define HAWK_Q11_BITS            15

    #define HAWK_S0_HIGH_BITS        13

    #define HAWK_S1_LOW_BITS         5
    #define HAWK_S1_HIGH_BITS        9

    #define HAWK_BETA0_NUM           1
    #define HAWK_BETA0_DEN           1000

#endif

#ifdef HAWK_1024

    #define HAWK_NAME                "HAWK-1024"

    #define HAWK_LAMBDA              256

    #define HAWK_N                   1024

    #define HAWK_QS                  (1ULL << 64)

    #define HAWK_ETA                 8

    #define HAWK_SIGMA_SIGN          1299
    #define HAWK_SIGMA_VERIFY        1571
    #define HAWK_SIGMA_KREC          1974

    #define HAWK_SALTLEN_BITS        320

    #define HAWK_KGSEED_BITS         320
    #define HAWK_HPUB_BITS           512

    #define HAWK_Q00_LOW_BITS        6
    #define HAWK_Q00_HIGH_BITS       10

    #define HAWK_Q01_LOW_BITS        10
    #define HAWK_Q01_HIGH_BITS       14

    #define HAWK_Q11_BITS            17

    #define HAWK_S0_HIGH_BITS        14

    #define HAWK_S1_LOW_BITS         6
    #define HAWK_S1_HIGH_BITS        10

    #define HAWK_BETA0_NUM           1
    #define HAWK_BETA0_DEN           3000

#endif

/*
 * ============================================================
 * Parámetros derivados
 * ============================================================
 */

#define HAWK_N_BYTES             (HAWK_N / 8)

#define HAWK_KGSEED_BYTES        (HAWK_KGSEED_BITS / 8)

#define HAWK_HPUB_BYTES          (HAWK_HPUB_BITS / 8)

#define HAWK_SALTLEN_BYTES       (HAWK_SALTLEN_BITS / 8)

/*
 * Tabla 4
 */

#if HAWK_N == 256

    #define HAWK_PRIV_BYTES      96
    #define HAWK_PUB_BYTES       450
    #define HAWK_SIG_BYTES       249

#elif HAWK_N == 512

    #define HAWK_PRIV_BYTES      184
    #define HAWK_PUB_BYTES       1024
    #define HAWK_SIG_BYTES       555

#elif HAWK_N == 1024

    #define HAWK_PRIV_BYTES      360
    #define HAWK_PUB_BYTES       2440
    #define HAWK_SIG_BYTES       1221

#endif

#endif