#import <Foundation/Foundation.h>
#import "../Macmonitor/IOReportWrapper.h"
#import "../Macmonitor/SMC.h"

static NSDictionary *collectMetrics(void) {
    io_connect_t conn = SMCOpen();
    IOReportData data = [IOReportWrapper fetchIOReportDataWithSMC:conn];
    if (conn != 0) {
        SMCClose(conn);
    }

    NSMutableArray *cpuCoreActive = [NSMutableArray arrayWithCapacity:data.cpuCoreCount];
    NSMutableArray *cpuCoreKinds = [NSMutableArray arrayWithCapacity:data.cpuCoreCount];
    for (int32_t index = 0; index < data.cpuCoreCount && index < MACMONITOR_MAX_CPU_CORES; index++) {
        [cpuCoreActive addObject:@(data.cpuCoreActive[index])];
        [cpuCoreKinds addObject:@(data.cpuCoreKind[index])];
    }

    return @{
        @"cpuTemp": @(data.cpuTemp),
        @"cpuDieHotspot": @(data.cpuDieHotspot),
        @"gpuTemp": @(data.gpuTemp),
        @"cpuPower": @(data.cpuPower),
        @"gpuPower": @(data.gpuPower),
        @"anePower": @(data.anePower),
        @"dramPower": @(data.dramPower),
        @"systemPower": @(data.systemPower),
        @"gpuUsage": @(data.gpuUsage),
        @"gpuFreqMHz": @(data.gpuFreqMHz),
        @"eClusterActive": @(data.eClusterActive),
        @"pClusterActive": @(data.pClusterActive),
        @"sClusterActive": @(data.sClusterActive),
        @"eClusterFreqMHz": @(data.eClusterFreqMHz),
        @"pClusterFreqMHz": @(data.pClusterFreqMHz),
        @"sClusterFreqMHz": @(data.sClusterFreqMHz),
        @"cpuCoreActive": cpuCoreActive,
        @"cpuCoreKinds": cpuCoreKinds,
        @"dramReadBytes": @(data.dramReadBytes),
        @"dramWriteBytes": @(data.dramWriteBytes),
        @"fanRPM": @(data.fanRPM)
    };
}

int main(void) {
    @autoreleasepool {
        NSDictionary *payload = collectMetrics();
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
        if (json == nil) {
            fprintf(stderr, "json_error=%s\n", error.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }
        fwrite(json.bytes, 1, json.length, stdout);
    }
    return 0;
}
