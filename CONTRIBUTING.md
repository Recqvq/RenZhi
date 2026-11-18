# 修改与贡献

Fork 后直接修改源码，运行 `./test.sh && ./build.sh`。开发依赖只有 macOS 与 Xcode Command Line Tools；发布审计脚本使用 Python 3 标准库。保持原生、小窗口、低频只读查询，不引入浏览器运行时、后台服务或新的遥测依赖。

## 常见修改

- 改文字和颜色：`Sources/Views.swift`。
- 改尺寸、刷新间隔：`Sources/AppConfiguration.swift`。
- 改提醒目标：优先理解 `normalAttendanceMins` 的服务端口径，勿把固定阈值写成官方出勤结论。
- 适配其他组织：调整配置、会话来源、认证和 `DayData` / `MonthData`。把凭证留在用户自己的机器上，不写入源码；如组织提供官方 OAuth/API，优先使用官方流程。
- 图标：修改 `Scripts/GenerateIcon.swift`，下次构建自动生成。

演示界面使用虚构数据，且不会发通知或访问飞书：

```sh
ATTENDANCE_SENTINEL_DEMO=1 dist/认知统计.app/Contents/MacOS/AttendanceSentinel
```

请先退出正常应用再启动演示。内部 Bundle ID 和可执行文件名保留旧名称，以延续本机升级时的设置；Fork 作为独立应用发布时可自行修改 `Info.plist` 及构建脚本。

## 检查

```sh
./test.sh
./build.sh
python3 Scripts/audit.py
./package.sh
```

离线测试覆盖来源隔离、CRC 校验、日志截断和分片、删除、新旧序列以及上海时区跨日/跨月/跨年。不会扫描本机会话。改动请求或解析逻辑时，应增加能发现真实错误的测试；小文案改动可用构建和 UI 检查验证。

`./test.sh --live` 仅在你主动选择时查询当前本人账号，输出成功与否，不输出身份信息或个人数值。不要在 CI 启用它。

## 发布（维护者）

1. 更新 `Info.plist` 的版本号和构建号、`CHANGELOG.md`，运行上述检查。
2. 正常提交并推送到 `main`。
3. 创建与版本号一致的标签，例如 `git tag v0.4.0 && git push origin v0.4.0`。
4. GitHub Actions 为该标签重新构建，生成 DMG、ZIP、SHA256SUMS，并发布 Release。出错时检查 Actions，不要发布未经检查的本机目录。

不要提交 `dist/`、飞书资料、个人报告、真实截图、密钥或登录令牌。Git 历史只保存源码和合成示例。
