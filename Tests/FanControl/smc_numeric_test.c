#include "SMC.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define TYPE(a, b, c, d)                                                       \
  (((unsigned int)(a) << 24) | ((unsigned int)(b) << 16) |                    \
   ((unsigned int)(c) << 8) | (unsigned int)(d))

static void roundTrip(unsigned int type, unsigned int size, double input) {
  SMCKeyData_keyInfo_t info = {.dataSize = size, .dataType = type};
  SMCBytes_t bytes;
  assert(SMCEncodeNumericValue(&info, input, bytes) == kIOReturnSuccess);

  SMCKeyData_t value;
  memset(&value, 0, sizeof(value));
  value.keyInfo = info;
  memcpy(value.bytes, bytes, size);
  bool supported = false;
  double output = SMCDecodeNumericValue(&value, &supported);
  assert(supported);
  assert(fabs(output - input) < 0.26);
}

int main(void) {
  roundTrip(TYPE('f', 'l', 't', ' '), 4, 5200);
  roundTrip(TYPE('f', 'p', 'e', '2'), 2, 4900);
  roundTrip(TYPE('u', 'i', '8', ' '), 1, 1);
  roundTrip(TYPE('u', 'i', '1', '6'), 2, 3);

  SMCKeyData_keyInfo_t unsupported = {.dataSize = 2, .dataType = TYPE('x', 'x', 'x', 'x')};
  SMCBytes_t bytes;
  assert(SMCEncodeNumericValue(&unsupported, 100, bytes) == kIOReturnUnsupported);
  puts("SMC numeric tests passed");
  return 0;
}
