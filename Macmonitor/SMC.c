// smc.c
#include "SMC.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define SMC_TYPE(a, b, c, d)                                                   \
  (((unsigned int)(a) << 24) | ((unsigned int)(b) << 16) |                    \
   ((unsigned int)(c) << 8) | (unsigned int)(d))

io_connect_t SMCOpen(void) {
  kern_return_t result;
  io_iterator_t iterator;
  io_object_t device;
  io_connect_t conn = 0;

  CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
  result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary,
                                        &iterator);
  if (result != kIOReturnSuccess) {
    return 0;
  }

  device = IOIteratorNext(iterator);
  IOObjectRelease(iterator);

  if (device == 0) {
    return 0;
  }

  result = IOServiceOpen(device, mach_task_self(), 0, &conn);
  IOObjectRelease(device);

  if (result != kIOReturnSuccess) {
    return 0;
  }

  return conn;
}

kern_return_t SMCClose(io_connect_t conn) { return IOServiceClose(conn); }

kern_return_t SMCCall(io_connect_t conn, int index,
                      SMCKeyData_t *inputStructure,
                      SMCKeyData_t *outputStructure) {
  size_t structureInputSize;
  size_t structureOutputSize;

  structureInputSize = sizeof(SMCKeyData_t);
  structureOutputSize = sizeof(SMCKeyData_t);

  return IOConnectCallStructMethod(conn, index, inputStructure,
                                   structureInputSize, outputStructure,
                                   &structureOutputSize);
}

kern_return_t SMCReadKey(io_connect_t conn, const char *key,
                         SMCKeyData_t *val) {
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));
  memset(val, 0, sizeof(SMCKeyData_t));

  inputStructure.key = (key[0] << 24) | (key[1] << 16) | (key[2] << 8) | key[3];
  inputStructure.data8 = SMC_CMD_READ_KEYINFO;

  result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
  if (result != kIOReturnSuccess) {
    return result;
  }

  val->keyInfo.dataSize = outputStructure.keyInfo.dataSize;
  val->keyInfo.dataType = outputStructure.keyInfo.dataType;
  inputStructure.keyInfo.dataSize = val->keyInfo.dataSize;
  inputStructure.data8 = SMC_CMD_READ_BYTES;

  result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
  if (result != kIOReturnSuccess) {
    return result;
  }

  memcpy(val->bytes, outputStructure.bytes, sizeof(outputStructure.bytes));
  return kIOReturnSuccess;
}

double SMCGetFloatValue(io_connect_t conn, const char *key) {
  SMCKeyData_t val;
  kern_return_t result = SMCReadKey(conn, key, &val);
  if (result != kIOReturnSuccess) {
    return 0.0;
  }

  bool supported = false;
  double value = SMCDecodeNumericValue(&val, &supported);
  return supported ? value : 0.0;
}

double SMCDecodeNumericValue(const SMCKeyData_t *value, bool *supported) {
  if (supported != NULL) {
    *supported = true;
  }

  switch (value->keyInfo.dataType) {
  case SMC_TYPE('f', 'l', 't', ' '): {
    if (value->keyInfo.dataSize < sizeof(float)) {
      break;
    }
    float decoded;
    memcpy(&decoded, value->bytes, sizeof(decoded));
    return (double)decoded;
  }
  case SMC_TYPE('s', 'p', '7', '8'): {
    if (value->keyInfo.dataSize < 2) {
      break;
    }
    int16_t raw = (int16_t)(((uint8_t)value->bytes[0] << 8) |
                            (uint8_t)value->bytes[1]);
    return (double)raw / 256.0;
  }
  case SMC_TYPE('f', 'p', 'e', '2'): {
    if (value->keyInfo.dataSize < 2) {
      break;
    }
    uint16_t raw = (uint16_t)(((uint8_t)value->bytes[0] << 8) |
                              (uint8_t)value->bytes[1]);
    return (double)raw / 4.0;
  }
  case SMC_TYPE('u', 'i', '8', ' '):
    if (value->keyInfo.dataSize >= 1) {
      return (uint8_t)value->bytes[0];
    }
    break;
  case SMC_TYPE('u', 'i', '1', '6'):
    if (value->keyInfo.dataSize >= 2) {
      return (double)(((uint8_t)value->bytes[0] << 8) |
                      (uint8_t)value->bytes[1]);
    }
    break;
  case SMC_TYPE('u', 'i', '3', '2'):
    if (value->keyInfo.dataSize >= 4) {
      return (double)(((uint32_t)(uint8_t)value->bytes[0] << 24) |
                      ((uint32_t)(uint8_t)value->bytes[1] << 16) |
                      ((uint32_t)(uint8_t)value->bytes[2] << 8) |
                      (uint8_t)value->bytes[3]);
    }
    break;
  default:
    break;
  }

  if (supported != NULL) {
    *supported = false;
  }
  return 0.0;
}

kern_return_t SMCEncodeNumericValue(const SMCKeyData_keyInfo_t *keyInfo,
                                    double value, SMCBytes_t bytes) {
  if (keyInfo == NULL || bytes == NULL || keyInfo->dataSize > sizeof(SMCBytes_t) ||
      !isfinite(value) || value < 0) {
    return kIOReturnBadArgument;
  }

  memset(bytes, 0, sizeof(SMCBytes_t));
  switch (keyInfo->dataType) {
  case SMC_TYPE('f', 'l', 't', ' '): {
    if (keyInfo->dataSize < sizeof(float)) {
      return kIOReturnBadArgument;
    }
    float encoded = (float)value;
    memcpy(bytes, &encoded, sizeof(encoded));
    return kIOReturnSuccess;
  }
  case SMC_TYPE('f', 'p', 'e', '2'): {
    if (keyInfo->dataSize < 2 || value > 16383.75) {
      return kIOReturnBadArgument;
    }
    uint16_t raw = (uint16_t)llround(value * 4.0);
    bytes[0] = (char)(raw >> 8);
    bytes[1] = (char)(raw & 0xff);
    return kIOReturnSuccess;
  }
  case SMC_TYPE('u', 'i', '8', ' '):
    if (keyInfo->dataSize < 1 || value > UINT8_MAX) {
      return kIOReturnBadArgument;
    }
    bytes[0] = (char)llround(value);
    return kIOReturnSuccess;
  case SMC_TYPE('u', 'i', '1', '6'): {
    if (keyInfo->dataSize < 2 || value > UINT16_MAX) {
      return kIOReturnBadArgument;
    }
    uint16_t raw = (uint16_t)llround(value);
    bytes[0] = (char)(raw >> 8);
    bytes[1] = (char)(raw & 0xff);
    return kIOReturnSuccess;
  }
  case SMC_TYPE('u', 'i', '3', '2'): {
    if (keyInfo->dataSize < 4 || value > UINT32_MAX) {
      return kIOReturnBadArgument;
    }
    uint32_t raw = (uint32_t)llround(value);
    bytes[0] = (char)(raw >> 24);
    bytes[1] = (char)((raw >> 16) & 0xff);
    bytes[2] = (char)((raw >> 8) & 0xff);
    bytes[3] = (char)(raw & 0xff);
    return kIOReturnSuccess;
  }
  default:
    return kIOReturnUnsupported;
  }
}

int SMCGetKeyCount(io_connect_t conn) {
  SMCKeyData_t val;
  kern_return_t result = SMCReadKey(conn, "#KEY", &val);
  if (result != kIOReturnSuccess) {
    // printf("SMCGetKeyCount: SMCReadKey failed with result %d\n", result);
    return 0;
  }

  unsigned int count = 0;
  count = ((unsigned char)val.bytes[0] << 24) |
          ((unsigned char)val.bytes[1] << 16) |
          ((unsigned char)val.bytes[2] << 8) | (unsigned char)val.bytes[3];
  // printf("SMCGetKeyCount: Found %d keys\n", count);
  return count;
}

kern_return_t SMCGetKeyFromIndex(io_connect_t conn, int index,
                                 char *outputKey) {
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));

  inputStructure.data8 = SMC_CMD_READ_INDEX;
  inputStructure.data32 = index;

  result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
  if (result != kIOReturnSuccess) {
    return result;
  }

  unsigned int key = outputStructure.key;
  outputKey[0] = (key >> 24) & 0xFF;
  outputKey[1] = (key >> 16) & 0xFF;
  outputKey[2] = (key >> 8) & 0xFF;
  outputKey[3] = key & 0xFF;
  outputKey[4] = '\0';

  return kIOReturnSuccess;
}

kern_return_t SMCGetKeyInfo(io_connect_t conn, const char *key,
                            SMCKeyData_keyInfo_t *keyInfo) {
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));

  inputStructure.key = (key[0] << 24) | (key[1] << 16) | (key[2] << 8) | key[3];
  inputStructure.data8 = SMC_CMD_READ_KEYINFO;

  result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
  if (result != kIOReturnSuccess) {
    return result;
  }

  *keyInfo = outputStructure.keyInfo;
  return kIOReturnSuccess;
}

kern_return_t SMCWriteKey(io_connect_t conn, const char *key,
                          unsigned int dataType, SMCBytes_t bytes,
                          unsigned int dataSize) {
  if (dataSize == 0 || dataSize > sizeof(SMCBytes_t)) {
    return kIOReturnBadArgument;
  }
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));

  inputStructure.key = (key[0] << 24) | (key[1] << 16) | (key[2] << 8) | key[3];
  inputStructure.data8 = SMC_CMD_WRITE_BYTES;
  inputStructure.keyInfo.dataSize = dataSize;
  inputStructure.keyInfo.dataType = dataType;
  memcpy(inputStructure.bytes, bytes, dataSize);

  result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
  return result;
}

kern_return_t SMCSetFloat(io_connect_t conn, const char *key, float value) {
  return SMCSetNumericValue(conn, key, value);
}

kern_return_t SMCSetNumericValue(io_connect_t conn, const char *key,
                                 double value) {
  SMCKeyData_keyInfo_t keyInfo;
  kern_return_t result = SMCGetKeyInfo(conn, key, &keyInfo);
  if (result != kIOReturnSuccess) {
    return result;
  }
  if (keyInfo.dataSize == 0) {
    return kIOReturnNotFound;
  }

  SMCBytes_t bytes;
  result = SMCEncodeNumericValue(&keyInfo, value, bytes);
  if (result != kIOReturnSuccess) {
    return result;
  }

  return SMCWriteKey(conn, key, keyInfo.dataType, bytes, keyInfo.dataSize);
}
