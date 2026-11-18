import AppKit
import Combine
import Foundation
import UserNotifications

struct DayData: Decodable {
    let date: String
    let workMins: Int
    let normalAttendanceMins: Int
}
struct MonthData: Decodable {
    let actualAttendance: Int
    let normalAttendance: Int
    let statisticsEnd: String
}
struct Envelope<T: Decodable>: Decodable {
    let code: Int
    let data: T?
}
private struct ResponseCode: Decodable { let code: Int }
private final class AttendanceTransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // A credential-bearing request must never follow an unexpected redirect.
        completionHandler(nil)
    }
}

enum AttendanceAPI {
    enum Failure: LocalizedError {
        case login, server, date
        var errorDescription: String? {
            switch self {
            case .login: return "登录已过期，请打开飞书考勤页后重新连接"
            case .server: return "暂时无法连接考勤服务，稍后自动重试"
            case .date: return "服务返回的日期不匹配，稍后重试"
            }
        }
    }
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 20
        c.urlCache = nil
        c.httpCookieStorage = nil
        return URLSession(configuration: c, delegate: AttendanceTransport(), delegateQueue: nil)
    }()
    static func fetch<T: Decodable>(_ path: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: AppConfiguration.apiBase + path)!)
        request.setValue(token, forHTTPHeaderField: "authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, [401,403].contains(http.statusCode) { throw Failure.login }
        let code = try JSONDecoder().decode(ResponseCode.self, from: data).code
        if [401,403].contains(code) { throw Failure.login }
        guard code == 0 else { throw Failure.server }
        let result = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard result.code == 0, let value = result.data else { throw Failure.server }
        return value
    }
    static func nextDayBoundary(_ now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AppConfiguration.timeZone
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }
    static func today(_ now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppConfiguration.timeZone; f.dateFormat = "yyyyMMdd"
        return f.string(from: now)
    }
}

@MainActor final class AttendanceModel: ObservableObject {
    @Published var pinned = UserDefaults.standard.object(forKey: "sentinel.pinned") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pinned, forKey: "sentinel.pinned") }
    }
    @Published private(set) var minutes: Int?
    @Published private(set) var monthDays: Int?
    @Published private(set) var currentDate = Date()
    @Published private(set) var target = 360
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var message = "连接飞书，自动同步你的考勤"
    @Published private(set) var isRefreshing = false
    @Published private(set) var connected = false
    @Published private(set) var needsConnection = true
    @Published private(set) var notificationEnabled = false
    private var token: String?
    private var profile: URL?
    private var timer: Timer?
    private var dayTimer: Timer?
    private var displayedDay: String?
    private var generation = 0
    static let demo = ProcessInfo.processInfo.environment["ATTENDANCE_SENTINEL_DEMO"] == "1"
    static let debug = ProcessInfo.processInfo.environment["ATTENDANCE_SENTINEL_DEBUG"] == "1"

    func start() {
        if Self.demo {
            minutes = 317; monthDays = 8; connected = true
            needsConnection = false; message = "演示数据"; lastUpdated = Date(); return
        }
        if UserDefaults.standard.bool(forKey: "sentinel.connectAllowed") { connect() }
        checkNotifications()
        timer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 15
        scheduleDayBoundary()
    }
    func stop() { timer?.invalidate(); dayTimer?.invalidate() }
    private func scheduleDayBoundary() {
        dayTimer?.invalidate()
        let interval = max(1, AttendanceAPI.nextDayBoundary().timeIntervalSinceNow + 1)
        dayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.handleClockChange() }
        }
    }
    func handleClockChange() {
        guard !Self.demo else { return }
        currentDate = Date()
        if displayedDay != AttendanceAPI.today(currentDate) {
            // Invalidate any response started yesterday before requesting today's data.
            generation += 1; isRefreshing = false
            minutes = nil; monthDays = nil; lastUpdated = nil; connected = false
            displayedDay = AttendanceAPI.today(currentDate)
        }
        scheduleDayBoundary()
        refresh()
    }
    func connect() {
        UserDefaults.standard.set(true, forKey: "sentinel.connectAllowed")
        refresh(reconnect: true)
    }
    func disconnect() {
        generation += 1
        UserDefaults.standard.set(false, forKey: "sentinel.connectAllowed")
        token = nil; profile = nil; minutes = nil; monthDays = nil
        lastUpdated = nil; connected = false; needsConnection = true
        message = "已断开，点击连接飞书"; isRefreshing = false
    }
    func refresh(reconnect: Bool = false) {
        guard !Self.demo, !isRefreshing, UserDefaults.standard.bool(forKey: "sentinel.connectAllowed") else { return }
        currentDate = Date()
        let date = AttendanceAPI.today(currentDate)
        if displayedDay != date { minutes = nil; monthDays = nil; lastUpdated = nil }
        isRefreshing = true
        let currentGeneration = generation
        Task {
            do {
                // Resolve the active account each refresh; never silently read an old
                // profile after the user switches Feishu accounts.
                if NSRunningApplication.runningApplications(withBundleIdentifier: AppConfiguration.feishuBundleID).first != nil {
                    do {
                        let current = try await Task.detached { try FeishuSession.activeProfile() }.value
                        if let profile, profile != current { token = nil; minutes = nil; monthDays = nil; lastUpdated = nil }
                        profile = current
                    } catch {
                        token = nil; profile = nil; minutes = nil; monthDays = nil; lastUpdated = nil
                        throw error
                    }
                }
                if let profile {
                    let read = Task.detached { try FeishuSession.token(in: profile) }
                    if let value = try? await read.value { token = value }
                }
                guard currentGeneration == generation else { return }
                guard let token else { throw FeishuSession.Failure.unavailable }
                async let dayRequest: DayData = AttendanceAPI.fetch("/att/czxy/passRecords/day?date=\(date)", token: token)
                async let monthRequest: MonthData = AttendanceAPI.fetch("/att/czxy/passRecords/statistics?period=month&date=\(date)", token: token)
                let (day, month) = try await (dayRequest, monthRequest)
                guard currentGeneration == generation else { return }
                guard date == AttendanceAPI.today(), day.date == date, month.statisticsEnd == date else { throw AttendanceAPI.Failure.date }
                guard day.workMins >= 0, day.normalAttendanceMins > 0 else { throw AttendanceAPI.Failure.server }
                minutes = day.workMins; target = day.normalAttendanceMins
                monthDays = month.normalAttendance
                lastUpdated = Date(); displayedDay = date; connected = true; needsConnection = false
                message = "已同步"; notifyIfNeeded()
                if Self.debug { print("API synchronization succeeded"); fflush(stdout) }
            } catch {
                guard currentGeneration == generation else { return }
                if error is FeishuSession.Failure { needsConnection = true }
                if case AttendanceAPI.Failure.login = error { token = nil; needsConnection = true }
                message = (error as? LocalizedError)?.errorDescription ?? "连接失败，稍后自动重试"
                connected = false
                if Self.debug { print("API unavailable (no credential details logged)"); fflush(stdout) }
            }
            isRefreshing = false
        }
    }
    func checkNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in self.notificationEnabled = settings.authorizationStatus == .authorized }
        }
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.notificationEnabled = granted
                if granted { self.notifyIfNeeded() }
                else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!) }
            }
        }
    }
    private func notifyIfNeeded() {
        guard !Self.demo, notificationEnabled, connected, let minutes, minutes >= target else { return }
        let day = AttendanceAPI.today(), key = "sentinel.notifiedDay"
        guard UserDefaults.standard.string(forKey: key) != day else { return }
        let content = UNMutableNotificationContent()
        content.title = "今日已达到时长目标"
        content.body = "已累计 \(minutes / 60) 小时 \(minutes % 60) 分，离开时记得完成出校打卡。"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sentinel-\(day)", content: content, trigger: nil)) { error in
            if error == nil { UserDefaults.standard.set(day, forKey: key) }
        }
    }
}
