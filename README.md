# Sentryboo

macOS 菜单栏应用：配置一台或多台 Zabbix API Token 后，定时拉取未恢复问题并在菜单栏合并展示。

## 能力

- 菜单栏角标 + 弹层问题列表（点击条目可打开对应 Zabbix Web）
- 多 Zabbix 账号：名称 / URL / Token / 最低严重级别 / 自签证书各自独立；列表标来源
- 独立设置窗口：账号列表 + 编辑页、DEBUG 模式
- 固定 **15 秒** 并行轮询各账号 `problem.get`；一台失败时仍显示其他台结果（「部分失败」）
- `AlertSource` / `ZabbixSource` 模块边界
- 空态 / 鉴权 / 网络 / 证书失败可读提示；旧单账号配置自动迁移为「默认」

设计文档：`docs/plans/2026-09-11-zabbix-menubar-alert-design.md`  
多账号设计：`docs/plans/2026-09-11-multi-zabbix-accounts-design.md`  
实现计划：`docs/plans/2026-09-11-multi-zabbix-accounts-implementation.md`  
Token 存储：`docs/plans/2026-09-11-token-file-store-design.md`  
UI 交互参考（非业务代码）：`总结.md`

## 要求

- macOS 13+
- Xcode 15+
- 可达的 Zabbix 5.4+（支持 API Token）

## 构建

```bash
xcodebuild -project Sentryboo.xcodeproj -scheme Sentryboo -configuration Debug build
```

或用 Xcode 打开 `Sentryboo.xcodeproj` 后 Run。

## 使用

1. 运行后点菜单栏图标 → **设置**
2. **添加账号**：填写名称（如「生产」）、Base URL、API Token
3. 按需设置该账号的最低严重级别；内网自签 HTTPS 可开启「信任此主机证书」
4. **测试连接** → **保存**；可继续添加更多账号
5. 弹层合并显示各账号未恢复问题（带来源名）；每 15 秒自动刷新；可点单条问题跳转前端
6. 仅配置一台时可用 **打开 Web**；多台时请点问题行跳转对应前端
7. 排障时可在设置中开启 **DEBUG 模式**，查看脱敏后的 API 请求/响应并复制日志

## 安全说明

- Zabbix API Token **不会主动推送**告警；采用客户端轮询
- Token 存 Application Support 加密文件（AES-GCM，`zabbix-tokens.json.enc`），不写 UserDefaults、不再用钥匙串（避免 Xcode 调试反复弹授权）；旧 Keychain 项启动时自动迁入后删除；DEBUG 日志会对 `auth` / Bearer Token 脱敏
- 默认校验证书；「信任此主机证书」默认关闭，仅在明确需要时开启
- 建议为 Token 配置最小只读权限

## 已知限制

- 轮询间隔固定 15 秒，最坏延迟约一个周期
- 不做新告警本地通知（差分）、告警确认/关闭等写操作
- 不做 Host Group 过滤 UI、按来源筛选/折叠、Webhook 中转
- 自签开关会对该会话放宽 TLS 校验，仅适合可信内网
- Web 跳转链接按常见 `tr_events.php` 路径拼接，个别定制前端路径可能需手工打开根地址
- 多账号时隐藏全局「打开 Web」，依赖问题行自带 URL

## 手工验收清单

- [ ] 未配置时弹层为空态，可进入设置添加账号
- [ ] 可添加 ≥2 台账号，Token 写入加密文件；Xcode 再次 Run 不再弹钥匙串
- [ ] 有效 URL + Token：测试连接成功并显示 API 版本
- [ ] 保存后 ≤15s 内角标与列表反映合并后的未恢复问题；每条可见来源名
- [ ] 每台可设不同最低严重级别与自签开关
- [ ] 一台 Token/网络失败：另一台问题仍显示，状态提示「部分失败：XX」
- [ ] 旧单账号配置升级后自动变成「默认」账号
- [ ] 错误 Token：明确「无效或权限不足」，应用不崩溃，日志无 Token
- [ ] 无问题：空态清晰，不误报
- [ ] 开启 DEBUG：测试连接 / 刷新后设置页出现脱敏日志，可复制

## 二期预告

- 快照差分 → 本地通知
- 可选告警确认（`AcknowledgeableSource`）
- 可配置轮询间隔
- 按来源筛选 / 账号启用开关
- 第二类数据源或 Webhook 中转实验
