#include "hawk_params.h"
#include "ntt_transform.h"
#include <stdio.h>

int main() 
{
    printf("Testing find_generator function\n");
    printf("================================\n\n");
    
    // Test with 104857601U
    printf("Test 1: find_generator(104857601U)\n");
    uint32_t result1 = find_generator(104857601U);
    printf("Result: %u\n\n", result1);
    
    // Test with other prime numbers
    printf("Test 2: find_generator(65537U)\n");
    uint32_t result2 = find_generator(65537U);
    printf("Result: %u\n\n", result2);
    
    printf("Test 3: find_generator(12289U)\n");
    uint32_t result3 = find_generator(12289U);
    printf("Result: %u\n\n", result3);

    printf("Test 4: find_generator(P1)\n");
    uint32_t result4 = find_generator(P1);
    printf("Result: %u\n\n", result4);

    printf("Test 5: find_generator(P2)\n");
    uint32_t result5 = find_generator(P2);
    printf("Result: %u\n\n", result5);

    printf("Testing gamma calculation\n");
    printf("=========================\n\n");
    
    // Calculate gamma for each prime
    uint32_t gamma1 = compute_gamma(result4, P1, HAWK_N);
    uint32_t gamma2 = compute_gamma(result5, P2, HAWK_N);
    printf("Gamma for P1: %u\n", gamma1);
    printf("Gamma for P2: %u\n\n", gamma2);

    printf("All tests completed.\n");
    return 0;
}