#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include "../05_software/shake256.h"

static void print_bytes(const uint8_t *buf, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        printf("%02x", buf[i]);
    }
    printf("\n");
}

static void print_u64_array(const char *name, const uint64_t *v, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        printf("%s[%lu] = 0x%016llx\n",
               name,
               (unsigned long)i,
               (unsigned long long)v[i]);
    }
}

int main(void)
{
    const uint8_t msg[] = "Hola";
    size_t msg_len = sizeof(msg) - 1;

    printf("Message: %s\n\n", msg);

    // ------------------------------------------------------------
    // Test 1: EncodeInt(j, 8)
    // ------------------------------------------------------------

    printf("=== EncodeInt(j, 8) ===\n");

    for (uint64_t j = 0; j < 4; j++) {
        uint8_t enc[1];

        EncodeInt(enc, j, 8);

        printf("EncodeInt(%llu, 8) = ",
               (unsigned long long)j);
        print_bytes(enc, 1);
    }

    printf("\n");

    // ------------------------------------------------------------
    // Test 2: DecodeInt
    // ------------------------------------------------------------

    printf("=== DecodeInt ===\n");

    uint8_t b1[1] = {0x05};
    uint8_t b8[8] = {
        0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08
    };

    printf("DecodeInt({0x05}, 8) = %llu\n",
           (unsigned long long)DecodeInt(b1, 8));

    printf("DecodeInt({01 02 03 04 05 06 07 08}, 64) = 0x%016llx\n",
           (unsigned long long)DecodeInt(b8, 64));

    printf("\n");

    // ------------------------------------------------------------
    // Test 3: SHAKE256 normal
    // ------------------------------------------------------------

    printf("=== SHAKE256 ===\n");

    uint8_t shake_out[64];

    shake256(shake_out, sizeof(shake_out), msg, msg_len);

    printf("SHAKE256(\"Hola\", 64 bytes) =\n");
    print_bytes(shake_out, sizeof(shake_out));

    printf("\n");

    // ------------------------------------------------------------
    // Test 4: SHAKE256w
    // ------------------------------------------------------------

    printf("=== SHAKE256w ===\n");

    uint64_t w[8];

    shake256w(w, 8, msg, msg_len);

    print_u64_array("w", w, 8);

    printf("\n");

    // ------------------------------------------------------------
    // Test 5: SHAKE256x4
    // ------------------------------------------------------------

    printf("=== SHAKE256x4 ===\n");

    uint64_t x4[4 * 8];

    shake256x4(x4, 8, msg, msg_len);

    print_u64_array("x4", x4, 4 * 8);

    printf("\n");

    // ------------------------------------------------------------
    // Test 6: comprobar estructura x4[4*i+j]
    // ------------------------------------------------------------

    printf("=== SHAKE256x4 structure ===\n");

    for (size_t i = 0; i < 8; i++) {
        printf("i = %lu:\n", (unsigned long)i);

        for (size_t j = 0; j < 4; j++) {
            printf("  x4[4*%lu + %lu] = 0x%016llx\n",
                   (unsigned long)i,
                   (unsigned long)j,
                   (unsigned long long)x4[4 * i + j]);
        }
    }

    return 0;
}