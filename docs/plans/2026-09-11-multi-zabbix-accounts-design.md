# 多 Zabbix 账号配置 — 设计文档

日期：2026-09-11  
状态：已定稿  
前置：一期单账号 Sentryboo 已可用

## 背景

当前设置只能配置 1 套 Zabbix（单 URL + 单 Token）。用户有多套环境，需要同时监控。

## 已确认决策

| 项 | 选择 |
|----|------|
| 菜单栏展示 | 合并成一份列表，每条标出来源名称 |
| 配置粒度 | 每台独立：名称、URL、Token、最低严重级别、自签证书 |
| 部分失败 | 仍显示成功台结果；状态提示「部分失败：XX」 |
| 设置 UI | 账号列表 + 编辑页 |
| 实现路径 | 多账号配置 + 并行拉取合并（方案 A） |

## §1 数据模型与存储

### ZabbixAccount

| 字段 | 存储 | 说明 |
|------|------|------|
| `id` | UserDefaults | UUID，稳定主键 |
| `name` | UserDefaults | 展示名（生产 / 测试） |
| `baseURL` | UserDefaults | API Base URL |
| `minimumSeverity` | UserDefaults | 每台独立 |
| `allowInsecureTLS` | UserDefaults | 每台独立 |
| `apiToken` | Application Support 加密文件（见 `2026-09-11-token-file-store-design.md`） | 不进 UserDefaults；旧 Keychain 启动迁入后删除 |

账号元数据数组键：`zabbix.accounts`（JSON）。

### AlertProblem 扩展

- 增加 `sourceID`、`sourceName`
- 问题 `id` 改为 `"\(accountID):\(eventid)"`，避免多台撞车

### SourceStatus 扩展

- 增加部分失败态：`partial(okCount: Int, failedNames: [String])`

### 迁移

启动时若存在旧键 `zabbix.baseURL` / `zabbix.apiToken` / `zabbix.minimumSeverity` / `zabbix.allowInsecureTLS`：

1. 创建一条账号，`name = "默认"`
2. Token 迁到 `zabbix.apiToken.<newID>`
3. 删除旧键

## §2 设置 UI 与同步

### 设置窗

- **主页**：账号列表（名称、URL 摘要）；添加 / 删除；点行进入编辑
- **编辑页**：名称、URL、Token、最低严重级别、自签；测试连接、保存、删除
- DEBUG / 轮询说明与账号列表同级，不绑在某一台

### 同步

- 15s 对所有「URL + Token 非空」账号并行 `problem.get`
- 合并后按严重级别降序，再按开始时间
- 行点击仍用问题自带 Web URL
- 「打开 Web」：依赖问题行自带 URL；全局按钮在仅一台时可打开该台前端，多台时隐藏或打开第一台

### 状态

| 情况 | 表现 |
|------|------|
| 无账号 | `idle` → 引导添加 |
| 全部成功 | `ok(N)` |
| 部分成功 | 列表保留成功结果；「部分失败：测试」 |
| 全部失败 | `error` |
| 同步中且无缓存 | 「正在同步…」 |

## §3 改动范围与验收

### 改动文件

- `Models`：`ZabbixAccount`；`AlertProblem` / `SourceStatus`
- `KeychainStore`：按 accountID 分槽；迁移旧 Token
- `AlertSession`：CRUD、并行刷新、合并、迁移
- `SettingsView`：列表 + 编辑
- `ContentView`：来源名、部分失败文案
- `ZabbixSource`：绑定账号 id/displayName；问题 id 前缀

### 不做

- 启用/禁用开关、按来源筛选/折叠、拖拽排序、导入导出、每台独立轮询间隔

### 验收

1. ≥2 台账号，Token 分槽 Keychain
2. 合并列表可见来源名；角标为合并总数
3. 每台独立严重级别与自签
4. 一台失败另一台仍显示 + 部分失败提示
5. 旧单账号迁成「默认」
6. Debug 编译通过；日志脱敏 Token

## 架构示意

```text
Settings（列表+编辑）
    → AlertSession（账号 CRUD + 15s 循环）
        → [ZabbixSource(生产), ZabbixSource(测试), ...]  并行 fetch
            → 合并 [AlertProblem]（带 sourceName）
                → MenuBar 角标 + ContentView 列表
```
