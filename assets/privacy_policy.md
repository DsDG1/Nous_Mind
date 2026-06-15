# 隐私政策 / Privacy Policy

最后更新 / Last updated: 2026-06-15

## 简体中文

### 1. 概述

本应用由 DsDogs 开发，是一款本地优先的提醒与灵感记录工具。我们不收集您的个人数据用于商业目的，不投放广告，不向任何第三方出售您的信息。本政策说明本应用如何处理您设备上的数据，以及您在哪些场景下与第三方服务交互。

### 2. 我们不收集什么

- 不收集使用统计、点击事件、停留时长等遥测数据
- 不收集崩溃日志上报；崩溃日志仅保存在您设备内存中
- 不收集设备标识符（IMEI / Android ID / IDFA / 推送 token）
- 不接入任何广告或营销 SDK

### 3. 我们在设备本地存储什么

所有数据保存在 App 沙盒内的 SQLite 数据库 `reminders.db`：

| 数据 | 用途 | 保留 |
|------|------|------|
| 提醒（标题、时间、描述） | 提醒调度与通知 | 直到您删除或卸载 |
| 灵感文本 | 记录灵感 | 直到您删除或卸载 |
| 灵感图片 | 配套灵感 | 直到您删除或卸载 |
| DeepSeek API Key | AI 调用凭证 | 直到您清除或卸载 |
| 自定义提示词 | AI 调用的 system prompt | 直到您清除或卸载 |
| 应用设置（主题、限额等） | 个性化 | 直到您卸载 |
| 回收站（30 天） | 误删恢复 | 30 天后自动清除 |

### 4. 第三方服务（仅在您主动触发时）

| 服务 | 触发条件 | 传输内容 |
|------|---------|---------|
| DeepSeek Chat Completions | 您点 "AI 自动调整" 或 "AI 错误分析" | 您填写的标题、描述、OCR 文本、当前时间与时区、自定义提示词（如有） |
| 系统日历 | 您点 "加入日历" 图标 | 提醒标题、描述、起止时间 |
| 系统通知 | 提醒触发 | 提醒标题与描述（本地发送，不联网） |

DeepSeek 调用使用您自己填写的 API Key（`Authorization: Bearer`），请求体仅包含您本次的输入与上文提示词，**不包含**您的设备信息、API Key 本身或账号标识。请求走 HTTPS。

### 5. 权限说明

| 权限 | 用途 | 是否必选 |
|------|------|---------|
| 相机 | 拍摄灵感配图 | 否 |
| 相册 | 从相册选灵感配图 | 否 |
| 通知（Android 13+） | 提醒到时通知 | 否（关闭后无法接收通知） |
| 精确闹钟 | 定时发送通知 | 否 |
| 日历读写 | "加入日历"功能 | 否 |

### 6. AI Key 安全声明

- DeepSeek API Key 以明文存储于本地数据库，**仅供本机使用**
- 备份导出 JSON 中包含该 Key（方便您在新设备恢复），但从备份恢复时**不会**自动写回新设备的数据库
- 我们在任何日志、崩溃、提示中都不会打印 API Key
- 若您更换设备或不愿再使用 AI，请到「设置 → AI 助手」清除 Key

### 7. 数据备份与导出

「设置 → 数据管理 → 导出备份」会生成一个 JSON 文件，包含您所有提醒、灵感、设置与 API Key，存到您选择的位置。该文件**不上传**到任何服务器，分享路径由您决定（系统分享面板）。

### 8. 数据删除

- 单条删除 → 进入 30 天回收站，30 天后自动清除
- 卸载 App → 全部本地数据立即清除（系统级操作）
- 重置用量 → 仅重置 AI 今日调用次数，不删除任何数据

### 9. 儿童隐私

本应用不面向 13 岁以下儿童，不主动收集未成年人信息。

### 10. 您的权利

无论您身处何地，您可以：

- 查看所有数据：通过导出备份获取 JSON 副本
- 修改数据：在 App 内直接编辑
- 删除数据：单条删除或卸载 App
- 撤回 AI 同意：关闭「设置 → AI 助手」开关并清除 API Key

### 11. 联系信息

如对本政策有疑问、行使您的权利或投诉，请联系：

- 邮箱：dsdogs@outlook.com
- 开发者：DsDogs
- 应用名称：提醒事项 / Nous 记事
- 版本：1.5.2

我们会在收到邮件后 15 个工作日内回复。

### 12. 政策更新

本政策可能随 App 升级而调整。重大变更将通过 App 内通知告知，并更新本文档顶部的「最后更新」日期。

---

## English

### 1. Overview

This application is developed by DsDogs as a local-first reminder and inspiration tool. We do not collect your personal data for commercial purposes, do not serve ads, and do not sell your information to third parties. This policy explains how data is handled on your device and when (and only when) third-party services are involved.

### 2. What we do NOT collect

- No usage analytics, click events, or session duration
- No crash log uploads; crashes stay in device memory only
- No device identifiers (IMEI / Android ID / IDFA / push tokens)
- No advertising or marketing SDKs of any kind

### 3. What we store locally

All data is stored in an on-device SQLite database `reminders.db` inside the app sandbox:

| Data | Purpose | Retention |
|------|---------|-----------|
| Reminders (title, time, description) | Scheduling & notifications | Until you delete or uninstall |
| Inspiration text | Capture ideas | Until you delete or uninstall |
| Inspiration images | Accompany ideas | Until you delete or uninstall |
| DeepSeek API Key | AI call credential | Until you clear it or uninstall |
| Custom system prompts | AI call context | Until you clear them or uninstall |
| App settings (theme, quota, etc.) | Personalisation | Until you uninstall |
| Trash (30-day soft delete) | Mistake recovery | Auto-purged after 30 days |

### 4. Third-party services (only when you trigger them)

| Service | When | What is sent |
|---------|------|--------------|
| DeepSeek Chat Completions | You tap "AI 调整" or "AI 错误分析" | Title, description, OCR text, current time & timezone, your custom prompt if any |
| System Calendar | You tap the "加入日历" icon | Reminder title, description, start & end time |
| System Notifications | When a reminder fires | Reminder title and description (local only, no network) |

DeepSeek calls use your own API Key (`Authorization: Bearer`). The request body contains only your input for that call. **No** device information, **no** the API key itself, and **no** account identifiers are included. All requests go over HTTPS.

### 5. Permissions

| Permission | Purpose | Required? |
|-----------|---------|-----------|
| Camera | Capture inspiration photos | No |
| Photo library | Pick inspiration images | No |
| Notifications (Android 13+) | Reminder delivery | No (alerts disabled if denied) |
| Exact alarm | Schedule reminders | No |
| Calendar read/write | "加入日历" feature | No |

### 6. AI Key security

- The DeepSeek API Key is stored in plain text in the local database, used only on this device
- The backup-export JSON contains the key (for device migration), but **is not** automatically restored when importing a backup
- We never log the API key, in any path
- To stop using AI, disable the toggle and clear the key in 「设置 → AI 助手」

### 7. Backup & export

「设置 → 数据管理 → 导出备份」generates a JSON file containing all reminders, inspirations, settings, and the API key. The file is saved wherever you choose and **is not uploaded** to any server. Sharing is entirely under your control via the system share sheet.

### 8. Data deletion

- Per-item delete → enters 30-day trash, auto-purged after 30 days
- Uninstall App → all local data is removed immediately (system action)
- Reset usage → only resets the daily AI call counter; no data is deleted

### 9. Children's privacy

This app is not directed at children under 13. We do not knowingly collect information from minors.

### 10. Your rights

Regardless of your location, you can:

- Access all data: export a backup JSON at any time
- Modify data: edit directly inside the app
- Delete data: per-item delete or uninstall the app
- Withdraw AI consent: turn off the AI assistant switch and clear the API key

### 11. Contact

For questions about this policy, to exercise your rights, or to file a complaint:

- Email: dsdogs@outlook.com
- Developer: DsDogs
- App name: 提醒事项 / Nous 记事
- Version: 1.5.2

We aim to reply within 15 business days.

### 12. Changes to this policy

This policy may be updated as the app evolves. Material changes will be announced in-app and the "Last updated" date at the top will be revised.