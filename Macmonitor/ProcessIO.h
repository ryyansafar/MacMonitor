#ifndef ProcessIO_h
#define ProcessIO_h

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

bool MMReadProcessDiskCounters(pid_t pid, uint64_t *readBytes, uint64_t *writeBytes);

#endif
