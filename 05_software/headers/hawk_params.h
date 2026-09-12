#ifndef HAWK_PARAMS_H
#define HAWK_PARAMS_H
#include <stdint.h>
#include <math.h>

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

#define HAWK_N_BYTES            (HAWK_N / 8)

#define HAWK_N_WORDS32          (HAWK_N / 32U)

#define HAWK_KGSEED_BYTES       (HAWK_KGSEED_BITS / 8)

#define HAWK_HPUB_BYTES         (HAWK_HPUB_BITS / 8)

#define HAWK_SALTLEN_BYTES      (HAWK_SALTLEN_BITS / 8)

/* M = SHAKE256(m || hpub)[0:512] para todos los conjuntos de parametros. */
#define HAWK_M_BYTES            64U

#define HAWK_SAMPLER_Y_WORDS    ((5 * HAWK_N) / 2)

#define HAWK_SAMPLER_X4_WORDS   (HAWK_SAMPLER_Y_WORDS / 4)

/* Table 5: cumulative distribution tables used by SamplerSign. */
typedef struct {
    uint16_t hi;
    uint64_t lo;
} hawk_u80;

#define HAWK_U80(hi, lo) \
    { (uint16_t)(hi), (uint64_t)(lo) }

#if HAWK_N == 256

    #define HAWK_SAMPLER_TABLE_LEN 10U
    static const hawk_u80 HAWK_T0[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x26B8, 0x71FBD58485D45050ULL),
        HAWK_U80(0x07C0, 0x54114F1DC2FA7AC9ULL),
        HAWK_U80(0x00A2, 0x42F74ADDA0B5AE61ULL),
        HAWK_U80(0x0005, 0x252E2152AB5D758BULL),
        HAWK_U80(0x0000, 0x0FDE62196C1718FCULL),
        HAWK_U80(0x0000, 0x00127325DDF8CEBAULL),
        HAWK_U80(0x0000, 0x000008100822C548ULL),
        HAWK_U80(0x0000, 0x0000000152A6E9AEULL),
        HAWK_U80(0x0000, 0x000000000014DA4AULL),
        HAWK_U80(0x0000, 0x000000000000007BULL)
    };
    static const hawk_u80 HAWK_T1[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x1345, 0x9408A4B181C718B1ULL),
        HAWK_U80(0x027D, 0x614569CC54722DC9ULL),
        HAWK_U80(0x0020, 0x951C5CDCBAFF49A3ULL),
        HAWK_U80(0x0000, 0xA3460C30AC398322ULL),
        HAWK_U80(0x0000, 0x01355A8330C44097ULL),
        HAWK_U80(0x0000, 0x0000DC8DE401FD12ULL),
        HAWK_U80(0x0000, 0x0000003B0FFB28F0ULL),
        HAWK_U80(0x0000, 0x0000000005EFCD99ULL),
        HAWK_U80(0x0000, 0x0000000000003953ULL),
        HAWK_U80(0x0000, 0x0000000000000000ULL)
    };

#elif HAWK_N == 512

    #define HAWK_SAMPLER_TABLE_LEN 13U
    static const hawk_u80 HAWK_T0[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x2C05, 0x8C27920A04F8F267ULL),
        HAWK_U80(0x0E9A, 0x1C4FF17C204AA058ULL),
        HAWK_U80(0x02DB, 0xDE63263BE0098FFDULL),
        HAWK_U80(0x0051, 0x56AEDFB0876A3BD8ULL),
        HAWK_U80(0x0005, 0x061E21D588CC61CCULL),
        HAWK_U80(0x0000, 0x2BA568D92EEC18E7ULL),
        HAWK_U80(0x0000, 0x00CF0F8687D3B009ULL),
        HAWK_U80(0x0000, 0x000216A0C344EB45ULL),
        HAWK_U80(0x0000, 0x000002EDF0B98A84ULL),
        HAWK_U80(0x0000, 0x000000023AF3B2E7ULL),
        HAWK_U80(0x0000, 0x0000000000EBCC6AULL),
        HAWK_U80(0x0000, 0x00000000000034CFULL),
        HAWK_U80(0x0000, 0x0000000000000006ULL)
    };
    static const hawk_u80 HAWK_T1[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x1AFC, 0xBC689D9213449DC9ULL),
        HAWK_U80(0x06EB, 0xFB908C81FCE3524FULL),
        HAWK_U80(0x0106, 0x4EBEFD8FF4F07378ULL),
        HAWK_U80(0x0015, 0xC628BC6B23887196ULL),
        HAWK_U80(0x0000, 0xFF769211F07B326FULL),
        HAWK_U80(0x0000, 0x0668F461693DFF8FULL),
        HAWK_U80(0x0000, 0x001670DB65964485ULL),
        HAWK_U80(0x0000, 0x00002AB6E11C2552ULL),
        HAWK_U80(0x0000, 0x0000002C253C7E81ULL),
        HAWK_U80(0x0000, 0x0000000018C14ABFULL),
        HAWK_U80(0x0000, 0x000000000007876EULL),
        HAWK_U80(0x0000, 0x000000000000013DULL),
        HAWK_U80(0x0000, 0x0000000000000000ULL)
    };

#elif HAWK_N == 1024

    #define HAWK_SAMPLER_TABLE_LEN 13U
    static const hawk_u80 HAWK_T0[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x2C58, 0x3AAA2EB76504E560ULL),
        HAWK_U80(0x0F1D, 0x70E1C03E49BB683EULL),
        HAWK_U80(0x0319, 0x55CDA662EF2D1C48ULL),
        HAWK_U80(0x005E, 0x31E874B355421BB7ULL),
        HAWK_U80(0x0006, 0x57C0676C029895A7ULL),
        HAWK_U80(0x0000, 0x3D4D67696E51F820ULL),
        HAWK_U80(0x0000, 0x014A1A8A93F20738ULL),
        HAWK_U80(0x0000, 0x0003DAF47E8DFB21ULL),
        HAWK_U80(0x0000, 0x000006634617B3FFULL),
        HAWK_U80(0x0000, 0x00000005DBEFB646ULL),
        HAWK_U80(0x0000, 0x0000000002F93038ULL),
        HAWK_U80(0x0000, 0x000000000000D5A7ULL),
        HAWK_U80(0x0000, 0x0000000000000021ULL)
    };
    static const hawk_u80 HAWK_T1[HAWK_SAMPLER_TABLE_LEN] = {
        HAWK_U80(0x1B7F, 0x01AE2B17728DF2DEULL),
        HAWK_U80(0x0750, 0x6A00B82C69624C93ULL),
        HAWK_U80(0x0125, 0x2685DB30348656A4ULL),
        HAWK_U80(0x001A, 0x430192770E205503ULL),
        HAWK_U80(0x0001, 0x5353BD4091AA96DBULL),
        HAWK_U80(0x0000, 0x09915A53D8667BEEULL),
        HAWK_U80(0x0000, 0x0026670030160D5FULL),
        HAWK_U80(0x0000, 0x0000557CD1C5F797ULL),
        HAWK_U80(0x0000, 0x0000006965E15B13ULL),
        HAWK_U80(0x0000, 0x0000000047E9AB38ULL),
        HAWK_U80(0x0000, 0x00000000001B2445ULL),
        HAWK_U80(0x0000, 0x00000000000005AAULL),
        HAWK_U80(0x0000, 0x0000000000000000ULL)
    };

#endif

#define HAWK_BETA0              ((double)HAWK_BETA0_NUM / (double)HAWK_BETA0_DEN)

#define P1                      2147473409

#define G1                      3

#define P2                      2147389441

#define G2                      11

#define PI                      3.14159265358979323846264338327950288

#define DELTA_ANGLE             2.0 * PI / 2048.0

#define Y00_MAX_BITS (HAWK_N / 2U) *(1U + HAWK_Q00_LOW_BITS + (1U << (HAWK_Q00_HIGH_BITS - HAWK_Q00_LOW_BITS)))

#define Y01_MAX_BITS (HAWK_N) *(1U + HAWK_Q01_LOW_BITS + (1U << (HAWK_Q01_HIGH_BITS - HAWK_Q01_LOW_BITS)))

#define YS1_MAX_BITS ((HAWK_N) * (1U + HAWK_S1_LOW_BITS + (1U << (HAWK_S1_HIGH_BITS - HAWK_S1_LOW_BITS))))

#define NORM_THR     8ULL * HAWK_N * HAWK_SIGMA_VERIFY * HAWK_SIGMA_VERIFY / (1000000ULL)

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
