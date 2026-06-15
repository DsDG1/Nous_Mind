# 用户协议 / Terms of Service

最后更新 / Last updated: 2026-06-15

> **本项目说明**:Nous 记事(又称"提醒事项")是一款开源移动应用,源代码以 **MIT 许可证**发布,源代码托管在 GitHub。
> 本协议由两部分组成:**第一部分**是 MIT 许可证全文(中英);**第二部分**是关于本应用**预编译版本**的补充说明,仅在您使用应用商店下载的安装包时适用。
>
> **About this project**: Nous 记事 (a.k.a. "Reminders") is an open-source mobile application whose source code is released under the **MIT License**, hosted on GitHub. This Agreement consists of two parts: **Part 1** is the full text of the MIT License (Chinese and English); **Part 2** is a supplementary notice for users of the **pre-compiled application**, applicable only when you install the build distributed via the app stores.

## 简体中文

### 第一部分:MIT 许可证

本项目(包括源代码、文档、相关资源文件)以 **MIT 许可证** 开源发布。

- **项目仓库**:<https://github.com/DsDG1/Nous_Mind>
- **问题反馈**:<https://github.com/DsDG1/Nous_Mind/issues>
- **许可协议**:MIT License
- **版权所有**:Copyright © 2026 DsDogs

#### MIT 许可证全文(中文译本)

本译文仅供参考,正式法律文本以英文原版为准。

特此免费授予任何获得本软件及相关文档文件(以下统称"本软件")副本的人,不受限制地处理本软件的权利,包括但不限于使用、复制、修改、合并、发布、分发、再许可和/或出售本软件副本的权利,以及授予本软件接收者同等权利的权利,前提是满足以下条件:

上述版权声明和本许可声明应包含在本软件的所有副本或主要部分中。

本软件按"原样"提供,不作任何明示或暗示的担保,包括但不限于对适销性、特定用途适用性和非侵权性的担保。在任何情况下,作者或版权所有人均不对任何因本软件、本软件的使用或其他涉及本软件的行为而产生的索赔、损害或其他责任负责,无论该责任基于合同、侵权或其他法律理论。

#### MIT License (Original English Text)

```
MIT License

Copyright (c) 2026 DsDogs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 第二部分:关于预编译应用的补充说明

以下条款仅适用于本项目的 **预编译移动应用**(即您从应用商店安装的 iOS / Android 安装包),**不适用于** 源代码本身。源代码的使用、修改、复制、再分发完全受第一部分 MIT 许可证约束。

#### 1. 服务说明

本应用是上述开源项目的官方预编译分发,提供:

- 创建、编辑、删除日程提醒
- 系统通知定时推送
- 文本灵感与配图记录
- 可选的本地中文 OCR 文字识别(`google_mlkit_text_recognition`,模型内置)
- 可选的第三方 AI 文字润色与一键调整(由用户自行填入 DeepSeek API Key)
- 数据本地备份与恢复
- 30 天回收站

#### 2. 本地数据与隐私

本应用严格遵守"本地优先"原则,所有数据保存在您设备本机的 SQLite 数据库中。**开发者无法访问您的数据**,卸载 App 即清空。详细的数据处理实践见《隐私政策》:

- 应用内入口:设置 → 关于 → 协议 → 隐私政策
- 文档地址:本应用资产 `assets/privacy_policy.md`

#### 3. AI 服务

本应用集成的 AI 文字润色与一键调整功能 **由第三方 API 提供商 DeepSeek 提供**。开发者不直接运营生成式 AI 模型,亦不构成生成式 AI 服务提供者。

- DeepSeek 用户协议:<https://www.deepseek.com/agreements/terms-of-service>
- 触发时机:仅在您主动点击 AI 按钮时调用,需您自行填入 DeepSeek API Key
- 数据流向:本应用 → HTTPS → DeepSeek API(传输您的提醒文本、描述、OCR 文本、当前时间、自定义提示词)
- 关闭方式:设置 → AI 助手 → 关闭开关 + 清除 API Key

#### 4. 第三方服务一览

| 服务 | 用途 | 提供商 | 链接 |
|------|------|--------|------|
| DeepSeek Chat Completions | AI 文字润色 | 深度求索 | <https://www.deepseek.com> |
| Google ML Kit Text Recognition | 本机 OCR | Google | <https://developers.google.com/ml-kit> |
| 系统日历 | "加入日历"功能 | 操作系统 | 各 OS 厂商条款 |
| 系统通知 | 提醒推送 | 操作系统 | 各 OS 厂商条款 |

第三方服务的可用性、内容、隐私实践与中断由该第三方负责,开发者不承担因第三方原因造成的损失。

#### 5. 免责声明

在适用法律允许的最大范围内,本应用按"原样"提供,作者及贡献者 **不承担任何明示或暗示的担保或责任**,包括但不限于:

- 不保证服务不中断、及时、安全、无错误
- 不保证 AI 输出结果的准确性、可靠性、完整性、适用性
- 不对因使用或无法使用本应用而造成的任何直接、间接、偶然、特殊或衍生性损害负责
- AI 输出由您自行判断与采用,作者不对其后果负责

#### 6. 协议变更

本协议可能随项目演进而更新。重大变更会在 GitHub Releases 与应用内更新日志中说明。源代码本身的许可条款(MIT)不可撤销,本部分仅约束"预编译应用"相关补充说明。

#### 7. 法律适用

本协议第二部分的解释、效力及争议解决适用 **中华人民共和国法律**(不含港澳台)。因本部分条款产生的争议,提交 **开发者所在地有管辖权的人民法院** 解决。

#### 8. 联系方式

- **项目仓库**:<https://github.com/DsDG1/Nous_Mind>
- **问题反馈**:<https://github.com/DsDG1/Nous_Mind/issues>
- **Pull Request**:欢迎提交贡献,详见 `CONTRIBUTING.md`(如有)
- **邮箱**:【开发者邮箱】

我们尽量在 GitHub Issues 中公开回复常见问题。涉及个人隐私或安全漏洞,请通过邮箱或 GitHub Security Advisories 私密联系。

#### 9. 中英文版本

如本协议的简体中文版本与其他语言版本存在任何不一致,**以简体中文版本为准**。MIT 许可证的正式法律文本以 **英文原版** 为准。

---

## English

### Part 1: MIT License

This project (including source code, documentation, and related resources) is released under the **MIT License**.

- **Repository**:<https://github.com/DsDG1/Nous_Mind>
- **Issue tracker**:<https://github.com/DsDG1/Nous_Mind/issues>
- **License**:MIT License
- **Copyright**:Copyright © 2026 DsDogs

#### MIT License (Full Text)

```
MIT License

Copyright (c) 2026 DsDogs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

#### MIT License (Chinese Translation — for reference only)

The English text above is the legally binding version. The following Chinese translation is provided for convenience.

特此免费授予任何获得本软件及相关文档文件(以下统称"本软件")副本的人,不受限制地处理本软件的权利,包括但不限于使用、复制、修改、合并、发布、分发、再许可和/或出售本软件副本的权利,以及授予本软件接收者同等权利的权利,前提是满足以下条件:

上述版权声明和本许可声明应包含在本软件的所有副本或主要部分中。

本软件按"原样"提供,不作任何明示或暗示的担保,包括但不限于对适销性、特定用途适用性和非侵权性的担保。在任何情况下,作者或版权所有人均不对任何因本软件、本软件的使用或其他涉及本软件的行为而产生的索赔、损害或其他责任负责,无论该责任基于合同、侵权或其他法律理论。

### Part 2: Supplementary Notice for the Pre-Compiled Application

The following provisions apply **only to the pre-compiled mobile application** (the iOS / Android installation packages distributed via the app stores). They do **not** apply to the source code itself, which is governed solely by the MIT License above.

#### 1. Description of Service

This application is the official pre-compiled distribution of the open-source project above and provides:

- Create, edit, and delete scheduled reminders
- System notification delivery
- Text and image inspiration capture
- Optional on-device Chinese OCR text recognition (`google_mlkit_text_recognition`; model bundled)
- Optional third-party AI text polishing and one-tap adjustment (powered by DeepSeek API, using a User-supplied API key)
- Local backup and restore
- 30-day trash

#### 2. Local Data and Privacy

The application strictly follows a "local-first" principle. All data resides in an on-device SQLite database. **The Developer cannot access your data**, and uninstalling the application immediately and irreversibly removes all local data. Detailed data-handling practices are described in the Privacy Policy:

- In-app entry:Settings → About → Agreement → Privacy Policy
- Source asset:`assets/privacy_policy.md`

#### 3. AI Services

The AI text polishing and one-tap adjustment features integrated into the application are **provided by the third-party API provider DeepSeek**. The Developer does not directly operate any generative AI model and does not constitute a Generative AI Service Provider.

- DeepSeek Terms:<https://www.deepseek.com/agreements/terms-of-service>
- Trigger:only when you tap the AI button; requires you to have entered a valid DeepSeek API key
- Data flow:this application → HTTPS → DeepSeek API (transmits your reminder text, description, OCR text, current time, and any custom prompt)
- Opt-out:Settings → AI Assistant → disable the switch and clear the API key

#### 4. Third-Party Services

| Service | Purpose | Provider | Link |
|---------|---------|----------|------|
| DeepSeek Chat Completions | AI text polishing | DeepSeek | <https://www.deepseek.com> |
| Google ML Kit Text Recognition | On-device OCR | Google | <https://developers.google.com/ml-kit> |
| System Calendar | "Add to Calendar" feature | OS vendor | Each OS vendor's terms |
| System Notifications | Reminder delivery | OS vendor | Each OS vendor's terms |

The availability, content, privacy practices, and interruptions of any third-party service are the responsibility of that third party. The Developer is not liable for losses caused by any third party.

#### 5. Disclaimer

To the maximum extent permitted by applicable law, the application is provided "as is". The author and contributors **make no warranties and assume no liability**, including but not limited to:

- That the service will be uninterrupted, timely, secure, or error-free
- That AI outputs are accurate, reliable, complete, or fit for any particular purpose
- Any direct, indirect, incidental, special, or consequential damages arising from the use of, or the inability to use, the application
- AI outputs are evaluated and adopted solely at the User's discretion; the author is not responsible for their consequences

#### 6. Modifications

This Agreement may be updated as the project evolves. Material changes will be announced in GitHub Releases and in the in-app changelog. The source-code license (MIT) is irrevocable; only this supplementary notice for the pre-compiled app may be revised.

#### 7. Governing Law

This supplementary notice (Part 2) is governed by the **laws of the People's Republic of China** (excluding Hong Kong, Macao, and Taiwan). Any dispute arising from this Part shall be submitted to the **people's court with jurisdiction at the Developer's location**.

#### 8. Contact

- **Repository**:<https://github.com/DsDG1/Nous_Mind>
- **Issue tracker**:<https://github.com/DsDG1/Nous_Mind/issues>
- **Pull Requests**:Contributions are welcome; see `CONTRIBUTING.md` if available
- **Email**:[Developer email]

We aim to respond publicly to common questions via GitHub Issues. For privacy-sensitive or security-vulnerability reports, please contact us privately by email or via GitHub Security Advisories.

#### 9. Language Versions

In the event of any inconsistency between the Simplified Chinese version and any other language version of this Agreement, **the Simplified Chinese version shall prevail**. The **English text** of the MIT License is the legally binding version.
