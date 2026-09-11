# Sentryboo M0–M4 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 `/Users/luhonglin/Desktop/java/Sentryboo` 新建 macOS 菜单栏应用 Sentryboo：一期通过 15s 轮询 Zabbix `problem.get` 展示未恢复问题。

**Architecture:** SwiftUI `MenuBarExtra` + 独立 Settings `Window`；`AlertSession` 调度同步；`AlertSource` 协议 + `ZabbixSource`；Token 存 Keychain。详见 `docs/plans/2026-09-11-zabbix-menubar-alert-design.md`。

**Tech Stack:** Swift 5.9+ / SwiftUI / macOS 13+ / URLSession / Security.framework (Keychain) / Xcode project

**App name / bundle:** `Sentryboo` / `app.sentryboo.Sentryboo`  
**UI reference:** `总结.md`（仅交互借鉴）

---

> **进度（2026-09-11）：** M0–M4 已落地并通过 `xcodebuild` Debug 编译。待真机连 Zabbix 按 README 验收清单验收。

### Task 1: M0 工程骨架 ✅

**Files:**
- Create: `Sentryboo/SentrybooApp.swift`
- Create: `Sentryboo/ContentView.swift`
- Create: `Sentryboo/SettingsView.swift`
- Create: `Sentryboo/AlertSession.swift`
- Create: `Sentryboo/Models/AlertModels.swift`
- Create: `Sentryboo/Sources/AlertSource.swift`
- Create: `Sentryboo/Sources/ZabbixSource.swift`
- Create: `Sentryboo/Services/KeychainStore.swift`
- Create: `Sentryboo/Assets.xcassets/*`
- Create: `Sentryboo.xcodeproj/project.pbxproj`
- Create: `README.md`

**Step 1:** 创建 `LSUIElement` 菜单栏 App：MenuBarExtra 弹层 + Settings 窗口 + 空状态文案。

**Step 2:** 放入协议/模型/Keychain/Zabbix 空实现（编译通过，不真连网）。

**Step 3:** `xcodebuild -scheme Sentryboo -configuration Debug build` 验证编译。

**Step 4:** 提交前不自动 commit（除非用户要求）。

---

### Task 2: M1 Keychain + 测试连接 ✅

**Files:**
- Modify: `KeychainStore.swift`, `ZabbixSource.swift`, `SettingsView.swift`, `AlertSession.swift`

**行为:** 保存 URL/Token；`apiinfo.version` 或等价校验；错误归一文案。

---

### Task 3: M2 轮询 + 列表 ✅

**行为:** `problem.get` → `[AlertProblem]`；15s 调度；角标数字；弹层列表；手动刷新。

---

### Task 4: M3 过滤与证书 ✅

**行为:** 最低严重级别；自签证书开关；空态/错态打磨；可选打开 Zabbix Web。

---

### Task 5: M4 文档与验收 ✅

**行为:** 更新 README、已知限制、手工验收清单；标记二期项。

---

## 验证命令

```bash
xcodebuild -project Sentryboo.xcodeproj -scheme Sentryboo -configuration Debug build
```
