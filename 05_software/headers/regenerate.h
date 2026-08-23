#ifndef REGENERATE_H
#define REGENERATE_H

#include <stdint.h>
#include "hawk_params.h"

int RegenerateFG(const uint8_t *kgseed,
                 int8_t *f,
                 int8_t *g);

#endif