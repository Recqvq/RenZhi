import Foundation

/// Public service identifiers, not credentials. Adapt these for another service.
enum AppConfiguration {
    static let serviceOrigin = "https://ecard.sii.edu.cn"
    static let apiBase = serviceOrigin + "/attendance/phone"
    static let feishuBundleID = "com.electron.lark"
    static let miniAppID = "cli_a6494fb30caa900e"
    static let attendanceURL = URL(string: "lark://applink.feishu.cn/client/mini_program/open?appId=\(miniAppID)&mode=window&relaunch=true&path_pc=pages%2Fattendance%2Fattendance")!
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static let refreshInterval: TimeInterval = 300
    static let windowWidth: CGFloat = 256
    static let windowHeight: CGFloat = 164
    static let connectionHeight: CGFloat = 204
}
