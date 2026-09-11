# Sentryboo

macOS 菜单栏应用：配置 Zabbix API Token 后，定时拉取未恢复问题并在菜单栏展示。

## 一期能力

- 菜单栏角标 + 弹层问题列表（点击条目可打开 Zabbix Web）
- 独立设置窗口：Base URL、API Token（Keychain）、最低严重级别、自签证书开关
- 固定 **15 秒** 轮询 `problem.get`；手动刷新 / 打开弹层时立即拉取
- `AlertSource` / `ZabbixSource` 模块边界
- 空态 / 鉴权 / 网络 / 证书失败可读提示

设计文档：`docs/plans/2026-09-11-zabbix-menubar-alert-design.md`  
实现计划：`docs/plans/2026-09-11-sentryboo-m0-implementation.md`  
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
2. 填写 Zabbix Base URL（如 `https://zabbix.example.com` 或带路径的前端根）与 API Token
3. 按需设置最低严重级别；内网自签 HTTPS 可开启「信任此主机证书」
4. **测试连接** → **保存**
5. 弹层显示未恢复问题；每 15 秒自动刷新；可点 **打开 Web** 或单条问题跳转前端

## 安全说明

- Zabbix API Token **不会主动推送**告警；一期采用客户端轮询
- Token 只存 Keychain，不写 UserDefaults；日志不打印 Token / Authorization
- 默认校验证书；「信任此主机证书」默认关闭，仅在明确需要时开启
- 建议为 Token 配置最小只读权限

## 已知限制（一期）

- 轮询间隔固定 15 秒，最坏延迟约一个周期
- 不做新告警本地通知（差分）、告警确认/关闭等写操作
- 不做 Host Group 过滤 UI、多 Zabbix 实例、Webhook 中转
- 自签开关会对该会话放宽 TLS 校验，仅适合可信内网
- Web 跳转链接按常见 `tr_events.php` 路径拼接，个别定制前端路径可能需手工打开根地址

## 手工验收清单

- [ ] 未配置时弹层为空态，可进入设置
- [ ] 有效 URL + Token：测试连接成功并显示 API 版本
- [ ] 保存后 ≤15s 内角标与列表反映未恢复问题（受最低严重级别过滤）
- [ ] 错误 Token：明确「无效或权限不足」，应用不崩溃，日志无 Token
- [ ] 断网 / VPN 断开：错态提示；恢复后下一轮询自动恢复
- [ ] 无问题：空态清晰，不误报
- [ ] 自签环境：默认失败有证书提示；开启开关后可连
- [ ] 「打开 Web」与点击问题行能打开浏览器（路径合理时）

## 二期预告

- 快照差分 → 本地通知
- 可选告警确认（`AcknowledgeableSource`）
- 可配置轮询间隔
- 第二数据源或 Webhook 中转实验
