#ifndef REGENERATE_H
#define REGENERATE_H

#include <stdint.h>
#include "hawk_params.h"

int RegenerateFG(const uint8_t *kgseed,
                 int16_t *f,
                 int16_t *g);

#endif