#import <Foundation/Foundation.h>
#import "../Macmonitor/IOReportWrapper.h"
#import "../Macmonitor/SMC.h"

#include <math.h>
#include <unistd.h>

static const int kMaximumSupportedFans = 8;

static BOOL keyExists(io_connect_t conn, const char *key) {
    SMCKeyData_keyInfo_t info;
    return SMCGetKeyInfo(conn, key, &info) == kIOReturnSuccess && info.dataSize > 0;
}

static BOOL readNumber(io_connect_t conn, const char *key, double *value) {
    SMCKeyData_t raw;
    if (SMCReadKey(conn, key, &raw) != kIOReturnSuccess || raw.keyInfo.dataSize == 0) {
        return NO;
    }
    bool supported = false;
    double decoded = SMCDecodeNumericValue(&raw, &supported);
    if (!supported || !isfinite(decoded)) {
        return NO;
    }
    *value = decoded;
    return YES;
}

static int fanCount(io_connect_t conn) {
    double count = 0;
    if (!readNumber(conn, "FNum", &count)) {
        // Some Apple Silicon models do not expose FNum to unprivileged readers.
        // A valid F0 maximum is still sufficient to establish one controllable fan.
        double fan0Maximum = 0;
        return readNumber(conn, "F0Mx", &fan0Maximum) && fan0Maximum > 0 ? 1 : 0;
    }
    return MAX(0, MIN(kMaximumSupportedFans, (int)llround(count)));
}

static NSString *fanKey(int index, NSString *suffix) {
    return [NSString stringWithFormat:@"F%d%@", index, suffix];
}

static NSString *modeKey(io_connect_t conn, int index) {
    for (NSString *suffix in @[@"md", @"Md"]) {
        NSString *candidate = fanKey(index, suffix);
        if (keyExists(conn, candidate.UTF8String)) {
            return candidate;
        }
    }
    return nil;
}

static BOOL writeAndVerify(io_connect_t conn, NSString *key, double value) {
    if (SMCSetNumericValue(conn, key.UTF8String, value) != kIOReturnSuccess) {
        return NO;
    }
    double observed = 0;
    return readNumber(conn, key.UTF8String, &observed) && fabs(observed - value) < 1.0;
}

static BOOL enableManualMode(io_connect_t conn, int index) {
    NSString *key = modeKey(conn, index);
    if (key == nil) {
        return NO;
    }
    if (writeAndVerify(conn, key, 1)) {
        return YES;
    }

    // Apple Silicon's thermalmonitord can retain arbitration. Ftst asks it to
    // yield, after which the per-fan mode byte becomes writable.
    if (!keyExists(conn, "Ftst") || SMCSetNumericValue(conn, "Ftst", 1) != kIOReturnSuccess) {
        return NO;
    }
    for (int attempt = 0; attempt < 20; attempt++) {
        usleep(100000);
        if (writeAndVerify(conn, key, 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL restoreAutomatic(io_connect_t conn, int count) {
    BOOL success = YES;
    BOOL usesPerFanMode = modeKey(conn, 0) != nil;
    if (usesPerFanMode) {
        for (int index = 0; index < count; index++) {
            NSString *key = modeKey(conn, index);
            if (key == nil) {
                success = NO;
                continue;
            }
            if (!writeAndVerify(conn, key, 0)) {
                success = NO;
            }
            NSString *target = fanKey(index, @"Tg");
            if (keyExists(conn, target.UTF8String)) {
                (void)SMCSetNumericValue(conn, target.UTF8String, 0);
            }
        }
    } else if (keyExists(conn, "FS! ")) {
        if (SMCSetNumericValue(conn, "FS! ", 0) != kIOReturnSuccess) {
            success = NO;
        }
    } else {
        success = NO;
    }

    if (keyExists(conn, "Ftst") && SMCSetNumericValue(conn, "Ftst", 0) != kIOReturnSuccess) {
        success = NO;
    }
    return success;
}

static BOOL setMaximumCooling(io_connect_t conn, int count, NSMutableArray<NSNumber *> *targets) {
    BOOL usesLegacyMask = modeKey(conn, 0) == nil && keyExists(conn, "FS! ");
    NSMutableArray<NSString *> *targetKeys = [NSMutableArray arrayWithCapacity:count];

    // Preflight every fan before changing any control mode. This avoids leaving
    // a partially controlled system merely because a later fan lacks a target key.
    for (int index = 0; index < count; index++) {
        NSString *maximumKey = fanKey(index, @"Mx");
        NSString *targetKey = fanKey(index, @"Tg");
        double maximum = 0;
        if (!keyExists(conn, targetKey.UTF8String) ||
            !readNumber(conn, maximumKey.UTF8String, &maximum) ||
            maximum < 1000 || maximum > 20000) {
            return NO;
        }
        [targetKeys addObject:targetKey];
        [targets addObject:@((int)llround(maximum))];
    }

    if (usesLegacyMask) {
        // Legacy SMCs allow targets to be staged while automatic control remains
        // active. Set every maximum first, then claim all fan bits atomically.
        for (int index = 0; index < count; index++) {
            if (SMCSetNumericValue(conn, targetKeys[index].UTF8String,
                                   targets[index].doubleValue) != kIOReturnSuccess) {
                return NO;
            }
        }
        unsigned int mask = (1u << count) - 1u;
        if (SMCSetNumericValue(conn, "FS! ", mask) != kIOReturnSuccess) {
            return NO;
        }
        for (int index = 0; index < count; index++) {
            if (!writeAndVerify(conn, targetKeys[index], targets[index].doubleValue)) {
                (void)restoreAutomatic(conn, count);
                return NO;
            }
        }
    } else {
        // Apple Silicon requires each mode byte before its target becomes writable.
        // Complete one fan at a time so no later fan waits in manual mode without
        // immediately receiving its validated maximum target.
        for (int index = 0; index < count; index++) {
            if (!enableManualMode(conn, index) ||
                !writeAndVerify(conn, targetKeys[index], targets[index].doubleValue)) {
                (void)restoreAutomatic(conn, count);
                return NO;
            }
        }
    }
    return YES;
}

static NSDictionary *collectMetrics(void) {
    io_connect_t conn = SMCOpen();
    IOReportData data = [IOReportWrapper fetchIOReportDataWithSMC:conn];
    if (conn != 0) {
        SMCClose(conn);
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
        @"eClusterFreqMHz": @(data.eClusterFreqMHz),
        @"pClusterFreqMHz": @(data.pClusterFreqMHz),
        @"dramReadBytes": @(data.dramReadBytes),
        @"dramWriteBytes": @(data.dramWriteBytes),
        @"fanCount": @(data.fanCount),
        @"fanRPM": @(data.fanRPM)
    };
}

static NSDictionary *performFanControl(NSString *operation) {
    if (geteuid() != 0) {
        return @{@"success": @NO, @"operation": operation,
                 @"error": @"Fan control requires the privileged helper."};
    }

    io_connect_t conn = SMCOpen();
    if (conn == 0) {
        return @{@"success": @NO, @"operation": operation,
                 @"error": @"AppleSMC is unavailable."};
    }

    int count = fanCount(conn);
    if (count == 0) {
        SMCClose(conn);
        return @{@"success": @NO, @"operation": operation,
                 @"error": @"No controllable fans were detected."};
    }

    NSMutableArray<NSNumber *> *targets = [NSMutableArray array];
    BOOL success = [operation isEqualToString:@"maximum"]
        ? setMaximumCooling(conn, count, targets)
        : restoreAutomatic(conn, count);
    SMCClose(conn);

    if (!success) {
        return @{@"success": @NO, @"operation": operation, @"fanCount": @(count),
                 @"error": @"The SMC rejected the fan control request; automatic mode was requested as a fallback."};
    }
    return @{@"success": @YES, @"operation": operation, @"fanCount": @(count),
             @"targetRPM": targets};
}

static int writeJSON(NSDictionary *payload, int status) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (json == nil) {
        fprintf(stderr, "json_error=%s\n", error.localizedDescription.UTF8String ?: "unknown");
        return 1;
    }
    fwrite(json.bytes, 1, json.length, stdout);
    return status;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 1) {
            return writeJSON(collectMetrics(), 0);
        }
        if (argc != 2) {
            return writeJSON(@{@"success": @NO, @"error": @"Invalid arguments."}, 64);
        }

        NSString *argument = [NSString stringWithUTF8String:argv[1]];
        if ([argument isEqualToString:@"--fan-max"]) {
            NSDictionary *result = performFanControl(@"maximum");
            return writeJSON(result, [result[@"success"] boolValue] ? 0 : 1);
        }
        if ([argument isEqualToString:@"--fan-auto"]) {
            NSDictionary *result = performFanControl(@"automatic");
            return writeJSON(result, [result[@"success"] boolValue] ? 0 : 1);
        }
        return writeJSON(@{@"success": @NO, @"error": @"Unknown command."}, 64);
    }
}
