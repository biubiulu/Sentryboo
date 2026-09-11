# Zabbix 菜单栏告警客户端 — 设计文档

日期：2026-09-11  
状态：已定稿（§1–§5 已确认）  
产品方向：全新 macOS 菜单栏工程；借鉴 CodexMeter 的 UI/交互壳，不复用其业务代码。

---

## 背景与核心结论

用户配置远程监控 API Key（一期为 Zabbix API Token）后，在菜单栏展示对应告警。

**关键事实：Zabbix API Token 不会主动把告警推到客户端。**  
Token 只表示「有权限调用 API」。告警到达客户端必须由产品选择：

1. **拉取（轮询）**：客户端定时调用 `problem.get`
2. **推送**：Zabbix Webhook → 自建中转 → WebSocket/APNs 等

一期场景为个人/小团队、客户端可直连内网或 VPN 可达的 Zabbix，因此采用方案 1。

---

## 已确认决策

| 项 | 选择 |
|----|------|
| 产品形态 | 全新 macOS 菜单栏（SwiftUI），只借鉴 UI/交互 |
| 部署 | 个人/小团队，直连内网或 VPN 可达的 Zabbix |
| 收告警方式 | 客户端固定 **15 秒** 轮询 `problem.get` |
| 一期体验 | **未恢复问题列表**（角标 + 弹层），不做事件流通知 |
| 架构 | `AlertSource` 协议 + `ZabbixSource`；壳与源解耦 |

---

## §1 整体架构（一期）

- 全新 SwiftUI macOS 菜单栏工程（`LSUIElement`），无 Dock 图标。
- 借鉴交互壳：`MenuBarExtra`、独立 Settings Window、Keychain 存密钥、轻量状态项绘制。
- **配置**：Zabbix Base URL + API Token（Keychain）+ 可选 Host Group 过滤。
- **同步器**：后台每 **15 秒** 拉取；App 激活或手动「刷新」立即拉取。
- **状态机**：`未配置` → `校验中` → `正常（N 条问题）` → `网络/鉴权错误`。
- **UI**：菜单栏问题数或最高严重级别色点；弹层列表：主机、问题名、严重级别、持续时长；可选跳转 Zabbix Web。
- **模块边界**：`AlertSource` 协议 + `ZabbixSource` 实现；一期只注册 Zabbix。

```text
菜单栏 App ──每 15 秒──► Zabbix API
                         problem.get（未恢复问题）
                         ↓
                   角标数字 + 弹层列表
```

### 方案对比（演进）

| 方案 | 做法 | 优点 | 缺点 | 适用 |
|------|------|------|------|------|
| A 轮询（一期） | `problem.get` 定时拉取 | 零服务器、实现快、贴合 Problem 视图 | 最坏延迟约一个轮询周期 | 直连小团队 |
| B Webhook 中转 | Webhook → 中转 → 推客户端 | 更接近实时 | 运维与鉴权成本高 | 公网/多端/秒级 |
| C 混合 | 一期 A，二期差分通知，三期可选中转 | 渐进增强 | 需预留模块接口 | 推荐路径 |

---

## §2 数据流与 API

### 鉴权

- HTTP Header：`Authorization: Bearer <API Token>`
- 设置页「测试连接」：调用轻量接口（如 `apiinfo.version` 或受限 `problem.get`）验证 URL + Token

### 主同步

- 方法：`problem.get`
- 语义：当前**未恢复**问题（Problem 视图），不是历史事件流
- 建议字段：`eventid`/`objectid`、主机名、问题名、严重级别、开始时间、确认状态、可拼 Web URL 的 id
- 过滤（一期）：最低严重级别；Host Group 可选（实现成本高可放到 1.1）
- 排序：严重级别降序，其次开始时间

### 调度

- 固定间隔 **15 秒**
- 手动刷新、从后台回前台：立即拉一次
- 进行中请求未完成时跳过下一 tick 或合并，避免堆积
- 超时：单次请求硬超时（建议 10–15 秒），失败进入错态，下轮重试

### 差分（一期不做，预留）

- 两次快照对比：新增 problem → 二期可触发本地通知
- 一期只全量替换列表与角标，保证与 Zabbix 当前态对齐

### 错误处理

| 情况 | 表现 |
|------|------|
| Token 无效 / 权限不足 | 错态：「API Token 无效或权限不足」 |
| 网络/VPN 不可达 | 错态：「无法连接 Zabbix」 |
| 超时 / 非 JSON | 错态 + 保留上一份成功快照（可选，需标注陈旧） |
| 未配置 | 引导打开设置 |

禁止在 UI/日志中展示原始 Token 或完整 Authorization 头。

---

## §3 模块化接口（AlertSource）

目标：菜单栏壳只认统一告警模型，不绑死 Zabbix。

```text
UI (MenuBar + Popover)
    → AlertSession / Store
        → AlertSource 协议
            → ZabbixSource（一期）
            -.-> Prometheus（二期）
            -.-> Webhook 中转（三期）
```

### 统一模型（壳层依赖）

- `AlertProblem`：`id`、`title`、`host`、`severity`、`startedAt`、`url?`、`acknowledged`
- `SourceStatus`：`idle` / `syncing` / `ok(count)` / `error(message)`
- 各源自有 `SourceConfig`（Zabbix：URL + Token + 过滤）

### 协议（示意）

```swift
protocol AlertSource: Sendable {
  var id: String { get }           // "zabbix"
  var displayName: String { get }
  func validate() async throws
  func fetchOpenProblems() async throws -> [AlertProblem]
}
```

一期**不**把 `acknowledge` / `subscribe` 放进主协议。  
二期用扩展协议（如 `AcknowledgeableSource`）按能力可选实现。

### Zabbix 适配器职责

- JSON-RPC、Bearer 鉴权
- `problem.get` → `AlertProblem` 映射
- 错误归一为壳层可读文案
- Token 仅经 Keychain 读取，不进日志

### 注册

- `SourceRegistry` 一期硬编码注册 `ZabbixSource`
- 设置页「添加数据源」只露出已注册类型

### 与 CodexMeter 的对应（只借壳概念）

| CodexMeter | 本产品 |
|------------|--------|
| `CodexUsageService` | `AlertSession` |
| 配额模型 | `AlertProblem` |
| 独立 Settings Window | 同上，避免挂在 MenuBarExtra sheet |

---

## §4 UI 与安全

### UI

| 区域 | 行为 |
|------|------|
| 菜单栏 | 无问题：平静图标；有问题：角标数字或最高严重级别色点。状态项保持轻量。 |
| 弹层 | 上：连接状态 / 上次同步时间；中：未恢复问题列表；下：设置、手动刷新、退出。列表过长仅中间滚动。 |
| 设置 Window | **独立 Window**（勿把复杂表单挂在 MenuBarExtra sheet）。URL、Token、测试连接、可选 Host Group、最低严重级别。 |
| 空态/错态 | 未配置引导设置；鉴权/超时/证书失败给出可操作文案。 |

一期不做：本地通知差分、确认告警、多数据源切换 UI、Webhook 配置页。

视觉可延续紧凑信息密度（分区清晰、固定底栏、中间可滚），但代码重写。

### 安全

1. API Token 只存 **Keychain**；UserDefaults 仅存 URL、过滤等非机密项  
2. 日志禁止打印 Token / Authorization  
3. 默认 HTTPS；内网自签需显式「信任此主机证书」开关，默认关闭  
4. 文档提示 Token 最小读权限；一期只调只读 API  
5. 配置导出若做：不含 Token 或需二次确认  
6. `LSUIElement` 菜单栏应用，无 Dock 图标  

---

## §5 一期范围与里程碑

### 一期做（Must）

1. 全新 SwiftUI MenuBarExtra 工程（`LSUIElement`）
2. 设置窗：Base URL、API Token（Keychain）、测试连接
3. 固定 15s 轮询 + 手动刷新 + App 激活刷新
4. 菜单栏角标/状态 + 弹层未恢复问题列表
5. 状态机：未配置 / 同步中 / 正常 / 错误
6. `AlertSource` + `ZabbixSource` 模块边界落地
7. 基础过滤：最低严重级别；Host Group 可选（成本高可放 1.1）
8. 错误可读：鉴权失败、超时、证书问题

### 一期不做（Non-goals）

- Webhook / 自建中转 / WebSocket 推送  
- 新告警本地通知（差分）——二期  
- 告警确认 / 关闭（写操作）  
- 多 Zabbix 实例、多数据源并存 UI  
- Prometheus / 其他源  
- Windows / 跨平台  
- 账号体系、SaaS 后端  

### 里程碑

| 里程碑 | 交付 |
|--------|------|
| M0 | 空菜单栏 App、独立 Settings/About 骨架、本地化占位 |
| M1 | Keychain、测试连接、错误归一 |
| M2 | `problem.get` → 统一模型 → 角标 + 列表、15s 调度 |
| M3 | 严重级别过滤、自签证书开关、空态/错态、可选跳转 Zabbix Web |
| M4 | README、已知限制、手工验收清单；标记二期项 |

### 验收标准（一期完成定义）

- 配好可达 Zabbix + 有效 Token 后，≤15s 内角标与列表反映未恢复问题  
- Token 错误不崩溃，明确提示，日志无 Token 泄露  
- 断网/VPN 断开有错态；恢复后下一轮询自动正常  
- 无问题时空态清晰，不误报  

### 二期预告

- 快照差分 → 本地通知  
- `AcknowledgeableSource`（可选确认）  
- 可配置轮询间隔  
- 第二 `AlertSource` 或 Webhook 中转实验  

---

## 仓库现状说明（2026-09-11）

本仓库已清理原 CodexMeter 源码与工程文件。  
当前保留：

- `总结.md` — 原 CodexMeter UI/配置梳理，供交互借鉴  
- `docs/plans/2026-09-11-zabbix-menubar-alert-design.md` — 本文档  

下一步：按 M0 新建独立菜单栏工程骨架（可仍在本目录或新目录，实现前再定）。
