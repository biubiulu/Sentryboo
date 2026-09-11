# Long-term Memory

## 本仓库方向（2026-09-11 起）

- 新产品名：**Sentryboo**（`app.sentryboo.Sentryboo`），工程在本目录；原 CodexMeter 已清空。
- 保留文档：`总结.md`、`docs/plans/2026-09-11-zabbix-menubar-alert-design.md`、`docs/plans/2026-09-11-sentryboo-m0-implementation.md`、`README.md`。
- 收告警：客户端 **15s 轮询** `problem.get`；Token 存 Keychain；`LSUIElement` 菜单栏 + 独立 Settings Window。
- 架构：`AlertSession` + `AlertSource` / `ZabbixSource`。
- M0–M4 已落地并通过 Debug 编译：Keychain、测试连接、15s 轮询、列表/角标、最低严重级别、自签证书开关、打开 Web、README 验收清单。待真机连 Zabbix 验收。
- 一期已提交到本地 `main`：`8df00fd`（未 push）；`.codebuddy/` 保持未跟踪。
- 菜单栏打开设置窗必须先 `NSApp.activate(ignoringOtherApps: true)`，否则 `openWindow` 会静默无反应；已有窗用 `makeKeyAndOrderFront`。
- 默认最低严重级别：`warning`；自签开关默认关，开后用 `URLSessionFactory` + `InsecureTLSDelegate`。
