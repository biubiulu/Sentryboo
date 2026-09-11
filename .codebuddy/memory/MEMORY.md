# Long-term Memory

## 本仓库方向（2026-09-11 起）

- 新产品名：**Sentryboo**（`app.sentryboo.Sentryboo`），工程在本目录；原 CodexMeter 已清空。
- 保留文档：`总结.md`、`docs/plans/2026-09-11-zabbix-menubar-alert-design.md`、`docs/plans/2026-09-11-sentryboo-m0-implementation.md`、`README.md`。
- 收告警：客户端轮询 `problem.get`（默认 **15s**，可在设置改 5–300，`zabbix.pollIntervalSeconds`）；Token 存 Application Support AES-GCM 文件（不再用 Keychain）；`LSUIElement` 菜单栏 + 独立 Settings Window。
- 架构：`AlertSession` + `AlertSource` / `ZabbixSource`。
- 静默刷新：不切 `.syncing`；弹层状态文案右侧绿色呼吸灯（`isRefreshingPulse`）表示刚刷过。
- 菜单栏指示：弃用 MenuBarExtra（会强制 template）；改 `NSStatusItem` + 自绘 `StatusDotView` 彩色呼吸灯 + `NSPopover`。绿呼吸=正常；红呼吸=灾难；静态红=未配置/失败。
- macOS 26：`linkd.autoShortcut` 日志可忽略；`LSUIElement` 应用不进 Dock；若状态栏图标被系统隐藏，需 accessory↔regular 守护，否则会被 Automatic Termination 收掉。
- M0–M4 已落地并通过 Debug 编译：Token 文件存储、测试连接、可配置轮询、列表/角标、最低严重级别、自签证书开关、打开 Web、README 验收清单。待真机连 Zabbix 验收。
- 一期已提交到本地 `main`：`8df00fd`（未 push）；`.codebuddy/` 保持未跟踪。
- 菜单栏打开设置窗必须先 `NSApp.activate(ignoringOtherApps: true)`，否则 `openWindow` 会静默无反应；已有窗用 `makeKeyAndOrderFront`。
- 默认最低严重级别：`warning`；自签开关默认关，开后用 `URLSessionFactory` + `InsecureTLSDelegate`。
- `problem.get` 的 `sortfield` **只能** `eventid`，不能传 `severity`；severity 过滤用 `severities`，排序在客户端做。
- 设置页有 DEBUG 开关（`DebugLog`，UserDefaults `app.debugLogging`），日志脱敏 Token。
- 目标对齐 Zabbix **5.4.1**「监视 → 问题 → 最近问题」：`recent=true`、`suppressed=false`；丢掉无主机残留；严重级别用设置里的「最低严重级别」（用户要灾难则选灾难）。
- 多 Zabbix 账号（2026-09-11）：`ZabbixAccount` 存 UserDefaults `zabbix.accounts`；Token 由 `TokenStore` 存 `~/Library/Application Support/app.sentryboo.Sentryboo/zabbix-tokens.json.enc`（AES-GCM）；启动时从旧 Keychain 分槽/`zabbix.apiToken` 迁入后删除，避免 Xcode 反复弹钥匙串；菜单栏合并列表标 `sourceName`；部分失败 `SourceStatus.partial`；设置页列表+编辑；旧单配置自动迁「默认」。
