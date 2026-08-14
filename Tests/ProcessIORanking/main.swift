import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let start = Date(timeIntervalSince1970: 100)
let end = Date(timeIntervalSince1970: 102)
let diskRows = ProcessIORanking.diskRows(
    previous: [7: DiskIOCounter(readBytes: 1_000, writeBytes: 2_000, sampledAt: start)],
    current: [7: DiskIOCounter(readBytes: 3_000, writeBytes: 3_000, sampledAt: end)],
    names: [7: "writer"]
)
expect(diskRows == [DiskProcInfo(pid: 7, name: "writer", readBps: 1_000, writeBps: 500)],
       "disk rates should use the measured interval")

let resetRows = ProcessIORanking.diskRows(
    previous: [7: DiskIOCounter(readBytes: 3_000, writeBytes: 3_000, sampledAt: start)],
    current: [7: DiskIOCounter(readBytes: 10, writeBytes: 20, sampledAt: end)],
    names: [7: "reused-pid"]
)
expect(resetRows.isEmpty, "counter resets and PID reuse should not create spikes")

let nettop = """
,bytes_in,bytes_out,
old.1,9000,9000,
,bytes_in,bytes_out,
\"Browser, Helper.22\",200,50,
sync.service.33,10,500,
idle.44,0,0,
"""
let networkRows = ProcessIORanking.networkRows(from: nettop)
expect(networkRows.count == 2, "only active rows from the final nettop sample should remain")
expect(networkRows[0] == NetworkProcInfo(pid: 33, name: "sync.service", downBps: 10, upBps: 500),
       "network rows should be sorted by combined throughput")
expect(networkRows[1].name == "Browser, Helper" && networkRows[1].pid == 22,
       "quoted CSV names and the final PID separator should parse correctly")

print("Process I/O ranking tests passed")
