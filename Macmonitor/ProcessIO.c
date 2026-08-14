#include "ProcessIO.h"

#include <libproc.h>
#include <sys/resource.h>

bool MMReadProcessDiskCounters(pid_t pid, uint64_t *readBytes, uint64_t *writeBytes) {
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
        return false;
    }

    *readBytes = usage.ri_diskio_bytesread;
    *writeBytes = usage.ri_diskio_byteswritten;
    return true;
}
