# Token 本地加密文件存储 — 设计文档

日期：2026-09-11  
状态：已定稿  
背景：Xcode 调试启动反复弹出钥匙串访问授权，影响日常使用。

## 已确认决策

| 项 | 选择 |
|----|------|
| 存储位置 | Application Support 加密文件 |
| 加密 | AES-GCM + 应用内派生密钥（CryptoKit） |
| 旧 Keychain | 迁移成功后删除（含 legacy） |
| API 形状 | 保持 `saveToken` / `readToken` / `deleteToken` |
| 调用方 | `AlertSession` 几乎只换 store 类型 |

## §1 存储与加密

### 文件

```
~/Library/Application Support/app.sentryboo.Sentryboo/zabbix-tokens.json.enc
```

明文 JSON（加密前）：

```json
{
  "version": 1,
  "tokens": {
    "<account-uuid>": "<api-token>"
  }
}
```

整份 JSON 使用 AES-GCM 加密后落盘（nonce + ciphertext + tag）。

### 密钥

- `SHA256(固定盐 + Bundle Identifier)` → 256-bit key
- 不进 Keychain，不再弹授权
- 目标：防随手打开文件看到 Token；不宣称防逆向

### 组件

新增 `TokenStore`（替代 `KeychainStore`）：

- `saveToken(_:accountID:)`
- `readToken(accountID:) -> String?`
- `deleteToken(accountID:)`
- `migrateFromKeychainIfNeeded(accountIDs: [UUID])`

## §2 迁移、错误处理与改动范围

### 启动迁移

在 `AlertSession.init` 中，于旧单账号→多账号迁移之后：

1. 读加密文件（无则空表）
2. 对每个账号：文件无 Token 则尝试 Keychain `zabbix.apiToken.<id>`
3. legacy `zabbix.apiToken` 可补「默认」账号缺 Token
4. 有迁入则写回加密文件
5. 删除已迁 Keychain 项（分槽 + legacy）

迁移失败不阻断启动。

### 日常读写

- 保存/删除只改加密文件；并 `try?` 清理对应旧 Keychain 残留
- 迁移完成后日常路径不再读 Keychain

### 错误处理

- 自动创建 Application Support 目录
- 解密/JSON 失败：当空表 + DEBUG 日志
- 写盘失败：抛给 `AlertSession` 显示错误
- 日志继续脱敏 Token

### 改动文件

| 文件 | 改动 |
|------|------|
| 新增 `Services/TokenStore.swift` | AES-GCM 存取 + Keychain 迁移清理 |
| `AlertSession.swift` | 改用 `TokenStore` |
| `project.pbxproj` | 加入 TokenStore；移除 KeychainStore |
| 删除 `KeychainStore.swift` | 避免双实现 |
| README / 相关 docs | 一句说明存储变更 |

不改：`SettingsView`、`ZabbixAccount`、轮询与 UI。

### 验收

1. 已有 Keychain Token：升级后告警仍可用，钥匙串对应项消失
2. 之后 Xcode Run 不再弹钥匙串权限
3. 删账号/清空 Token 后文件内对应项消失
4. 清空 Application Support 后需重新填 Token
