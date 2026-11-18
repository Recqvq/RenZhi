import SwiftUI

struct FloatingWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AttendanceModel
    let openAttendance: () -> Void
    private var accent: Color {
        if (model.minutes ?? 0) >= model.target {
            return colorScheme == .dark ? Color(red: 0.40, green: 0.88, blue: 0.70) : Color(red: 0.08, green: 0.47, blue: 0.33)
        }
        return colorScheme == .dark ? Color(red: 0.65, green: 0.72, blue: 1) : Color(red: 0.32, green: 0.43, blue: 0.85)
    }
    private var dateLabel: String {
        let f = DateFormatter(); f.timeZone = AppConfiguration.timeZone; f.dateFormat = "M月d日"
        return f.string(from: model.currentDate)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(model.connected ? accent : .orange).frame(width: 6, height: 6)
                Text("认知统计").font(.system(size: 12, weight: .semibold))
                Text(dateLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin.slash")
                        .foregroundStyle(model.pinned ? accent : .secondary).frame(width: 24, height: 24)
                }.buttonStyle(.plain).help(model.pinned ? "取消置顶" : "窗口置顶")
                    .accessibilityLabel(model.pinned ? "取消置顶" : "窗口置顶")
                Menu {
                    Button("立即同步") { model.refresh() }.disabled(model.isRefreshing || model.needsConnection)
                    Button("打开飞书考勤", action: openAttendance)
                    if !model.notificationEnabled { Button("开启到点提醒") { model.enableNotifications() } }
                    Divider()
                    Toggle("窗口置顶", isOn: $model.pinned)
                    Button("断开连接") { model.disconnect() }
                    Divider()
                    Button("退出认知统计") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 21, height: 24)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多")
            }
            .padding(.bottom, 11)

            if model.needsConnection && model.minutes == nil {
                onboarding
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日认知提升").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(model.minutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "—:—")
                            .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(accent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 1, height: 54).padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本月认知提升").font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(model.monthDays.map(String.init) ?? "—").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("天").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(width: 85, alignment: .leading)
                }.help("本月仅计算考勤系统判定的正常出勤天数。")
                GeometryReader { g in
                    Capsule().fill(Color.primary.opacity(0.06))
                        .overlay(alignment: .leading) {
                            Capsule().fill(accent).frame(width: g.size.width * min(Double(model.minutes ?? 0) / Double(model.target), 1))
                        }
                }.frame(height: 3).padding(.top, 9)
                Spacer().frame(height: 9)
                HStack(spacing: 4) {
                    if model.isRefreshing { ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 10, height: 10) }
                    Text(status).font(.system(size: 10)).foregroundStyle(model.connected ? Color.secondary : Color.orange).lineLimit(1)
                    Spacer(minLength: 2)
                    Button {
                        if model.needsConnection { openAttendance() } else { model.refresh() }
                    } label: { Image(systemName: model.needsConnection ? "arrow.up.right.square" : "arrow.clockwise").font(.system(size: 11)) }
                        .buttonStyle(.plain).disabled(model.isRefreshing).help(model.needsConnection ? "重新连接飞书" : "同步最新数据")
                }.help(model.message)
            }
        }
        .padding(16)
        .frame(width: AppConfiguration.windowWidth, height: model.needsConnection && model.minutes == nil ? AppConfiguration.connectionHeight : AppConfiguration.windowHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("你的打卡，一眼就够").font(.system(size: 17, weight: .semibold))
            Text("连接本机已登录的飞书，仅读取一卡通考勤会话。不需要屏幕录制权限。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.isRefreshing ? "正在连接…" : "连接飞书") { model.connect() }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(model.isRefreshing)
                Button("打开考勤", action: openAttendance).buttonStyle(.plain).font(.system(size: 11))
            }
            Text(model.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var status: String {
        if AttendanceModel.demo { return "演示数据" }
        guard let date = model.lastUpdated else { return model.isRefreshing ? "正在同步…" : "尚未更新" }
        let f = DateFormatter(); f.timeZone = AppConfiguration.timeZone; f.dateFormat = "HH:mm"
        return "最后更新 \(f.string(from: date))"
    }
}
