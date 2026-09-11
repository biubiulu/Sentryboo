# 可配置轮询间隔 + 静默刷新呼吸灯 — 设计文档

日期：2026-09-11  
状态：已定稿  
背景：一期轮询固定 15 秒且刷新会切到「同步中」，菜单栏/弹层状态抖动；需要可改间隔，并用绿色呼吸灯表示「刚刚刷过」。

## 已确认决策

| 项 | 选择 |
|----|------|
| 默认间隔 | 15 秒 |
| 间隔 UI | 秒数输入框，范围 5–300 |
| 静默刷新 | 定时 / 激活 / 手动均不切 `.syncing`（保留上一状态与列表） |
| 刷新反馈 | 弹层 header 状态文案右侧：绿色小点呼吸灯 |
| 呼吸时机 | 刷新开始闪；结束后约 1.5 秒停 |
| 菜单栏图标旁 | 不做呼吸灯 |

## §1 行为与 UI

### 轮询间隔

- UserDefaults key：`zabbix.pollIntervalSeconds`
- 默认：`15`
- 合法范围：`5...300`；非法或越界时 clamp 到合法值
- 设置页「同步」区：用输入框替换「15 秒（一期固定）」文案
- 修改后尽快生效：循环下次 `sleep` 使用新值

### 静默刷新

- `refresh(reason:)` **不再**在开始时无条件 `status = .syncing`
- 刷新过程中保持上一 `status` / `problems`；结束后再更新
- 若 `problems` 为空且尚无成功状态，可保留极轻量占位（可选 ProgressView），避免完全空白
- 并发：已在刷新时，`.timer` 跳过
- `MenuBarLabel` 的 `.syncing → ↻` 基本不再出现；刷新时图标保持上一态

### 绿色呼吸灯

- 位置：`ContentView` header 中，状态文案（如「已连接 · 无问题」）右侧
- 样式：约 6–8pt 绿色圆点，opacity 呼吸动画
- 状态：`AlertSession.isRefreshingPulse`
  - `refresh` 开始 → `true`
  - 成功或失败结算后 → 再延迟约 **1.5s** → `false`
- `.idle`（未配置）可不显示

## §2 实现要点与改动范围

### AlertSession

- 新增 `@Published private(set) var isRefreshingPulse: Bool`
- 新增 `pollIntervalSeconds` 读写（UserDefaults + clamp）
- `startLoop`：`Task.sleep` 使用当前间隔，不再写死 15
- `setPollInterval(_:)`：校验、持久化
- `refresh`：开始置 pulse；不切 syncing；结束更新数据后再延迟关 pulse
- 用 `isRefreshInFlight` 代替依赖 `.syncing` 的并发门闩

### SettingsView

- 「同步」Section：`TextField`（整数秒）绑定到 session 的间隔
- Footer 说明：对齐 Zabbix 最近问题；范围 5–300；改完立即用于下一轮

### ContentView

- header：状态文案右侧绿色呼吸灯
- 弱化依赖 `.syncing` 打断中间列表的逻辑
- 「刷新」按钮用 `isRefreshingPulse` / in-flight 禁用，而非 `.syncing`

### SentrybooApp（可选）

- `MenuBarLabel`：`.syncing` 分支保留作兜底，与无问题态同显「◎」

### 不做

- 不改 Token 存储 / 多账号模型
- 不做菜单栏图标旁呼吸灯
- 不做复杂刷新队列 UI

### 验收

1. 默认间隔 15 秒；设置改为 30 后，下一轮按约 30 秒轮询
2. 输入 &lt;5 或 &gt;300 被 clamp，不崩溃
3. 定时刷新时弹层不闪「正在同步…」、菜单栏不频繁变 ↻
4. 刷新开始时状态文案右侧绿点呼吸；结束后约 1.5 秒停
5. 手动点「刷新」同样静默 + 呼吸灯
