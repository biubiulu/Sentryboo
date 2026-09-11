# 多 Zabbix 账号 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 支持配置多台 Zabbix，菜单栏合并展示带来源名的问题列表，部分失败仍显示成功结果。

**Architecture:** UserDefaults 存账号元数据数组；Keychain 按 `zabbix.apiToken.<id>` 分槽；`AlertSession` 并行拉取多 `ZabbixSource` 后合并排序；设置页为列表+编辑。

**Tech Stack:** SwiftUI macOS、Keychain、现有 Zabbix JSON-RPC

---

### Task 1: 模型

**Files:**
- Modify: `Sentryboo/Models/AlertModels.swift`
- Create: `Sentryboo/Models/ZabbixAccount.swift`

**Steps:** 新增 `ZabbixAccount`（Codable, Identifiable）；`AlertProblem` 加 `sourceID`/`sourceName`；`SourceStatus` 加 `partial(okCount:failedNames:)`。

### Task 2: Keychain 分槽

**Files:**
- Modify: `Sentryboo/Services/KeychainStore.swift`

**Steps:** `saveToken(_:accountID:)` / `readToken(accountID:)` / `deleteToken(accountID:)`；保留旧 `zabbix.apiToken` 读写供迁移。

### Task 3: ZabbixSource 绑定账号

**Files:**
- Modify: `Sentryboo/Sources/ZabbixSource.swift`

**Steps:** `id`/`displayName` 来自账号；`AlertProblem.id = "\(accountID):\(eventid)"`；填充 source 字段。

### Task 4: AlertSession 多账号

**Files:**
- Modify: `Sentryboo/AlertSession.swift`

**Steps:** 账号 CRUD；迁移旧单配置；并行 refresh；合并排序；partial 状态。

### Task 5: Settings UI

**Files:**
- Modify: `Sentryboo/SettingsView.swift`

**Steps:** NavigationStack 列表+编辑；测试连接按账号；DEBUG 区保留。

### Task 6: ContentView + 编译

**Files:**
- Modify: `Sentryboo/ContentView.swift`
- Modify: `README.md`

**Steps:** 行显示来源名；partial 文案；`xcodebuild` Debug 通过。
