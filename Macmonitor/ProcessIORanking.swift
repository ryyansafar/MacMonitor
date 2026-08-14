import Foundation

struct DiskProcInfo: Identifiable, Equatable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let readBps: Int64
    let writeBps: Int64
}

struct NetworkProcInfo: Identifiable, Equatable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let downBps: Int64
    let upBps: Int64
}

struct DiskIOCounter: Equatable {
    let readBytes: UInt64
    let writeBytes: UInt64
    let sampledAt: Date
}

enum ProcessIORanking {
    static func diskRows(
        previous: [Int: DiskIOCounter],
        current: [Int: DiskIOCounter],
        names: [Int: String],
        limit: Int = 5
    ) -> [DiskProcInfo] {
        guard !previous.isEmpty else { return [] }

        return current.compactMap { pid, sample -> DiskProcInfo? in
            guard let earlier = previous[pid], let name = names[pid] else { return nil }
            let elapsed = sample.sampledAt.timeIntervalSince(earlier.sampledAt)
            guard elapsed > 0 else { return nil }

            // A lower counter means the PID was reused or the kernel counter reset.
            guard sample.readBytes >= earlier.readBytes,
                  sample.writeBytes >= earlier.writeBytes else { return nil }

            let readBps = Int64(Double(sample.readBytes - earlier.readBytes) / elapsed)
            let writeBps = Int64(Double(sample.writeBytes - earlier.writeBytes) / elapsed)
            guard readBps + writeBps > 0 else { return nil }

            return DiskProcInfo(
                pid: pid,
                name: name,
                readBps: readBps,
                writeBps: writeBps
            )
        }
        .sorted { ($0.readBps + $0.writeBps) > ($1.readBps + $1.writeBps) }
        .prefix(limit)
        .map { $0 }
    }

    static func networkRows(from output: String, limit: Int = 5) -> [NetworkProcInfo] {
        var latestSample: [NetworkProcInfo] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = csvColumns(in: String(line))
            guard columns.count >= 3 else { continue }

            // nettop emits a header before every sample. Clearing here discards its
            // first cumulative snapshot and retains only the final delta snapshot.
            if columns[0].isEmpty && columns[1] == "bytes_in" {
                latestSample.removeAll(keepingCapacity: true)
                continue
            }

            guard let separator = columns[0].lastIndex(of: "."),
                  let pid = Int(columns[0][columns[0].index(after: separator)...]) else { continue }

            let name = String(columns[0][..<separator])
            let down = max(0, Int64(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0)
            let up = max(0, Int64(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0)
            guard !name.isEmpty, down + up > 0 else { continue }

            latestSample.append(NetworkProcInfo(
                pid: pid,
                name: name,
                downBps: down,
                upBps: up
            ))
        }

        return latestSample
            .sorted { ($0.downBps + $0.upBps) > ($1.downBps + $1.upBps) }
            .prefix(limit)
            .map { $0 }
    }

    static func csvColumns(in line: String) -> [String] {
        var columns: [String] = []
        var field = ""
        var quoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                columns.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        columns.append(field)
        return columns
    }
}
