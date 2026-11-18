import AppKit
import Foundation

// Read only the attendance site's token from the active Feishu profile.
// Never open a password database, copy the profile, or persist a credential.
enum FeishuSession {
    enum Failure: LocalizedError {
        case closed, unavailable, ambiguous
        var errorDescription: String? {
            switch self {
            case .closed: return "请先登录飞书，再连接"
            case .unavailable: return "请在飞书打开一次考勤签到，再点连接"
            case .ambiguous: return "检测到多个飞书会话，请保留一个账号后连接"
            }
        }
    }
    static func activeProfile() throws -> URL {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: AppConfiguration.feishuBundleID).first else { throw Failure.closed }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", String(app.processIdentifier), "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let paths = Set(String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            let value = String(line.dropFirst())
            guard line.first == "n", value.contains("/LarkShell/aha/users/"), value.hasSuffix("/profile_explorer/History") else { return nil }
            return String(value.dropLast("History".count))
        })
        guard paths.count <= 1 else { throw Failure.ambiguous }
        guard let path = paths.first else { throw Failure.unavailable }
        return URL(fileURLWithPath: path)
    }
    static func token(in profile: URL) throws -> String {
        let folder = profile.appendingPathComponent("Local Storage/leveldb")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var latest: (UInt64, String?)?
        for file in files where file.pathExtension == "log" {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 32_000_000,
                  let data = try? Data(contentsOf: file) else { continue }
            for record in LogReader.attendanceTokens(Array(data)) {
                if latest == nil || record.0 > latest!.0 { latest = record }
            }
        }
        guard let token = latest?.1, !token.isEmpty else { throw Failure.unavailable }
        return token
    }
}

// Chromium LevelDB write-ahead log parser. Bounded, read-only; ignores every
// origin/key except https://ecard.sii.edu.cn / token. SST compaction falls back
// to asking Feishu to create a fresh session instead of guessing old values.
enum LogReader {
    static let wanted = Array(("_" + AppConfiguration.serviceOrigin + "\0\u{1}token").utf8)
    static func attendanceTokens(_ b: [UInt8]) -> [(UInt64, String?)] {
        var position = 0, fragments: [UInt8] = [], result: [(UInt64, String?)] = []
        while position + 7 <= b.count {
            if position % 32768 > 32761 { position = (position / 32768 + 1) * 32768; continue }
            let size = Int(b[position+4]) | Int(b[position+5]) << 8
            let type = b[position+6]
            let room = 32768 - position % 32768 - 7
            guard size <= room, position + 7 + size <= b.count else { break }
            let storedCRC = uint32(b, position)
            position += 7
            let payload = Array(b[position..<position+size]); position += size
            if type == 0 && size == 0 { position = ((position-7)/32768+1)*32768; continue }
            guard maskedCRC([type] + payload) == storedCRC else { fragments = []; continue }
            switch type {
            case 1: result += batch(payload); fragments = []
            case 2: fragments = payload
            case 3: if !fragments.isEmpty { fragments += payload }
            case 4: if !fragments.isEmpty { result += batch(fragments + payload) }; fragments = []
            default: fragments = []
            }
        }
        return result
    }
    static func batch(_ b: [UInt8]) -> [(UInt64, String?)] {
        guard b.count >= 12 else { return [] }
        var seq: UInt64 = 0
        for i in 0..<8 { seq |= UInt64(b[i]) << (8*i) }
        let count = Int(uint32(b, 8))
        guard count <= 100_000 else { return [] }
        var p = 12, output: [(UInt64, String?)] = []
        for index in 0..<count {
            guard p < b.count else { return output }
            let kind = b[p]; p += 1
            guard kind <= 1, let key = field(b, &p) else { return output }
            var value: [UInt8] = []
            if kind == 1 { guard let v = field(b, &p) else { return output }; value = v }
            guard key == wanted else { continue }
            let text: String?
            if value.first == 1 { text = String(bytes: value.dropFirst(), encoding: .isoLatin1) }
            else if value.first == 0 { text = String(bytes: value.dropFirst(), encoding: .utf16LittleEndian) }
            else { text = nil }
            output.append((seq &+ UInt64(index), text))
        }
        return output
    }
    static func field(_ b: [UInt8], _ p: inout Int) -> [UInt8]? {
        var length = 0
        for shift in stride(from: 0, through: 28, by: 7) {
            guard p < b.count else { return nil }
            let byte = b[p]; p += 1; length |= Int(byte & 127) << shift
            if byte < 128 {
                guard length <= b.count - p else { return nil }
                defer { p += length }
                return Array(b[p..<p+length])
            }
        }
        return nil
    }
    static func uint32(_ b: [UInt8], _ p: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[p+$1]) << (8*$1) }
    }
    private static let table: [UInt32] = (0..<256).map { number in
        var c = UInt32(number)
        for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 1 ? 0x82f63b78 : 0) }
        return c
    }
    static func maskedCRC(_ b: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in b { crc = table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
        crc = ~crc
        return ((crc >> 15) | (crc << 17)) &+ 0xa282ead8
    }
}
