import AppKit
import Foundation

@main struct Smoke {
    static func v(_ n: Int) -> [UInt8] { var n = n, out: [UInt8] = []; repeat { var b = UInt8(n & 127); n >>= 7; if n > 0 { b |= 128 }; out.append(b) } while n > 0; return out }
    static func little(_ n: UInt64, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: n >> ($0*8)) } }
    static func batch(key: [UInt8] = LogReader.wanted, value: String = "test-session", sequence: UInt64 = 1, deletion: Bool = false) -> [UInt8] {
        let value = [UInt8(1)] + Array(value.utf8)
        return little(sequence,8) + little(1,4) + [deletion ? 0 : 1] + v(key.count) + key + (deletion ? [] : v(value.count) + value)
    }
    static func record(_ b: [UInt8], type: UInt8 = 1) -> [UInt8] { little(UInt64(LogReader.maskedCRC([type] + b)),4) + little(UInt64(b.count),2) + [type] + b }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let single = record(batch())
        assert(LogReader.attendanceTokens(single).first?.1 == "test-session")
        assert(LogReader.attendanceTokens(record(batch(key: Array("_https://other.example\0\u{1}token".utf8)))).isEmpty)
        assert(LogReader.attendanceTokens(record(batch(deletion: true))).first?.1 == nil)
        var bad = single; bad[0] ^= 255
        assert(LogReader.attendanceTokens(bad).isEmpty)
        for length in 0..<single.count { assert(LogReader.attendanceTokens(Array(single.prefix(length))).isEmpty) }
        let b = batch(); let a = Array(b.prefix(15)), z = Array(b.dropFirst(15))
        assert(LogReader.attendanceTokens(record(a, type: 2) + record(z, type: 4)).first?.1 == "test-session")
        let two = single + record(batch(value: "new-session", sequence: 3))
        assert(LogReader.attendanceTokens(two).max(by: {$0.0 < $1.0})?.1 == "new-session")
        assert(AttendanceAPI.today(ISO8601DateFormatter().date(from: "2026-11-18T16:01:00Z")!) == "20261119")
        let iso = ISO8601DateFormatter()
        for (input, expected) in [
            ("2026-11-18T15:59:59Z", "2026-11-18T16:00:00Z"),
            ("2026-11-30T09:00:00Z", "2026-11-30T16:00:00Z"),
            ("2026-12-31T09:00:00Z", "2026-12-31T16:00:00Z"),
            ("2028-02-29T09:00:00Z", "2028-02-29T16:00:00Z")
        ] {
            assert(AttendanceAPI.nextDayBoundary(iso.date(from: input)!) == iso.date(from: expected)!)
        }
        print("PASS: next Shanghai midnight across daily, monthly, yearly and leap-day boundaries")
        print("PASS: log CRC, fragments, truncation, origin isolation, deletion, newest value, Shanghai date rollover")
        if CommandLine.arguments.contains("--live") {
            let profile = try await Task.detached { try FeishuSession.activeProfile() }.value
            let token = try await Task.detached { try FeishuSession.token(in: profile) }.value
            let date = AttendanceAPI.today()
            async let d: DayData = AttendanceAPI.fetch("/att/czxy/passRecords/day?date=\(date)", token: token)
            async let m: MonthData = AttendanceAPI.fetch("/att/czxy/passRecords/statistics?period=month&date=\(date)", token: token)
            let (day,month) = try await (d,m)
            assert(day.date == date && month.statisticsEnd == date)
            print("PASS: live API and response dates (personal values omitted)")
        }
    }
}
