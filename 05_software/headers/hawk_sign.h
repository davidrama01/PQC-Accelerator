#ifndef HAWK_SIGN_H
#define HAWK_SIGN_H

#include <stdint.h>
#include <stddef.h>
#include "hawk_params.h"

void hawk_sign (const uint8_t *priv, const uint8_t *message, size_t message_len);

#endif
