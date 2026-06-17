# 用户协议 / Terms of Service

最后更新 / Last updated: 2026-06-17

> **本项目说明**:Nous记事是一款开源移动应用,源代码以 **MIT 许可证**发布,源代码托管在 GitHub。
> 本协议由两部分组成:**第一部分**是 MIT 许可证全文(中英);**第二部分**是关于本应用**预编译版本**的补充说明,仅在您使用应用商店下载的安装包时适用。
>
> **About this project**: Nous Mind is an open-source mobile application whose source code is released under the **MIT License**, hosted on GitHub. This Agreement consists of two parts: **Part 1** is the full text of the MIT License (Chinese and English); **Part 2** is a supplementary notice for users of the **pre-compiled application**, applicable only when you install the build distributed via the app stores.

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
- 系统下拉「快捷截图分析磁贴」:基于 Android 无障碍服务一键截屏,并通过本地 ML Kit 提取文字后导入 AI 调整流程;用户可随时在系统设置中关闭该无障碍服务

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
| Android 无障碍服务 | 快捷截图分析磁贴(一键截屏) | 操作系统 | 各 OS 厂商条款 |

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
- **邮箱**:dsdogs@outlook.com

我们尽量在 GitHub Issues 中公开回复常见问题。涉及个人隐私或安全漏洞,请通过邮箱或 GitHub Security Advisories 私密联系。

#### 9. 用户行为规范

您承诺不得利用本应用从事下列行为:

- 违反中华人民共和国法律法规、危害国家安全的活动
- 侵犯他人知识产权、隐私权、名誉权等合法权益
- 制作、传播违法或不良信息
- 对本应用进行反向工程、反编译、反汇编以破解、复制、盗用核心功能(法律明文允许的合理使用除外)
- 未经开发者书面许可,将本应用或其部分功能用于商业转售、二次分发或服务化运营
- 干扰或破坏本应用的正常运行、服务器或相关网络

如有违反,开发者有权暂停或终止您对本应用的使用,并保留追究法律责任的权利。

#### 10. 内容归属

- **您的内容**:您在本应用内创建、编辑、上传或以其他方式产生的全部提醒、灵感、文字、图片等内容,其所有权及知识产权均归您本人所有,开发者不主张任何权利。
- **本应用**:本应用的源代码以 **MIT 许可证**发布,详见本协议第一部分;预编译版本所附带的 UI 设计、品牌资产、商标等非源代码要素,版权归开发者所有,未经许可不得复制、再分发或商业使用。
- **AI 输出**:AI 助手基于第三方 API 生成的内容仅供参考,您对其采纳与使用后果承担全部责任。

#### 11. 未成年人保护

- 本应用不面向 14 岁以下未成年人。
- 14 至 18 岁的未成年用户,应在监护人指导下阅读本协议并在取得监护人同意后使用本应用。
- 如您是未成年人的监护人,发现被监护人在未经您同意的情况下使用了本应用的相关功能,请通过本协议第 8 条联系方式与我们联系。

#### 12. 投诉举报

任何投诉、举报或权利通知(包括但不限于:违法违规内容、知识产权侵权、未成年人不当使用等),请通过以下渠道提交:

- **邮箱**:dsdogs@outlook.com
- **GitHub Issues**:<https://github.com/DsDG1/Nous_Mind/issues>(不涉及个人隐私的问题)

我们会在收到通知后 **15 个工作日内** 回复并视情况采取必要措施。请在投诉中提供充分的身份与事实证据,以便我们核实处理。

#### 13. 可分割性

本协议任一条款被有管辖权的人民法院或仲裁机构认定为无效、非法或不可执行的,其他条款的效力不受影响。该等无效、非法或不可执行的条款将在适用法律允许的最大范围内,以最接近原意的有效条款予以替换。

#### 14. 完整协议

本协议(含第一部分 MIT 许可证原文及第二部分全部条款)构成您与开发者之间就本应用达成的完整协议,取代此前就同一主题达成的任何口头、书面或电子形式的约定。对本协议任何条款的修改,须以书面形式(包括电子邮件)经双方确认后,方可生效。

#### 15. 中英文版本

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
- Quick-settings screenshot analysis tile: one-tap screenshot via the Android Accessibility Service, on-device ML Kit OCR, then handed to the AI adjust flow. The accessibility service can be disabled at any time in system settings

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
| Android Accessibility Service | Quick-settings screenshot tile (one-tap capture) | OS vendor | Each OS vendor's terms |

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
- **Email**:dsdogs@outlook.com

We aim to respond publicly to common questions via GitHub Issues. For privacy-sensitive or security-vulnerability reports, please contact us privately by email or via GitHub Security Advisories.

#### 9. User Code of Conduct

You agree not to use the Application to:

- Engage in any activity that violates the laws of the People's Republic of China or endangers national security
- Infringe upon the legitimate rights and interests of others, including intellectual property, privacy, and reputation
- Produce, disseminate, or facilitate illegal or harmful content
- Reverse engineer, decompile, or disassemble the Application to circumvent, copy, or misappropriate its core functionality, except to the extent expressly permitted by applicable law
- Use the Application or any portion of it for commercial resale, redistribution, or service operation without the Developer's prior written consent
- Interfere with or disrupt the operation of the Application, its servers, or related networks

Violation of the above may result in suspension or termination of your access to the Application, and the Developer reserves the right to pursue legal remedies.

#### 10. Content Ownership

- **Your Content**: You retain full ownership of, and all intellectual property rights in, any reminders, inspirations, text, images, or other material you create, edit, or upload through the Application. The Developer claims no rights over such content.
- **The Application**: The source code of the Application is released under the **MIT License**, as set out in Part 1 of this Agreement. UI designs, brand assets, trademarks, and other non-source-code elements of the pre-compiled build are the property of the Developer and may not be copied, redistributed, or used commercially without permission.
- **AI Output**: Any content generated by the AI assistant via the third-party API is provided for reference only. You bear full responsibility for evaluating and acting on such output.

#### 11. Protection of Minors

- The Application is not directed at children under 14 years of age.
- Users aged 14 to 18 should review this Agreement under the guidance of, and use the Application only with the consent of, a parent or legal guardian.
- If you are the guardian of a minor and become aware that the minor has used features of the Application without your consent, please contact us through the channels listed in Section 8 of this Agreement.

#### 12. Complaint Reporting

Any complaint, report, or notice of right (including but not limited to illegal content, intellectual-property infringement, or inappropriate use by minors) may be submitted through the following channels:

- **Email**: dsdogs@outlook.com
- **GitHub Issues**: <https://github.com/DsDG1/Nous_Mind/issues> (for non-privacy-sensitive matters)

We aim to respond within **15 business days** of receipt and to take any measures we deem appropriate. Please provide sufficient identification and factual evidence so that we can verify and process your submission.

#### 13. Severability

If any provision of this Agreement is held by a court or arbitration body of competent jurisdiction to be invalid, illegal, or unenforceable, the validity, legality, and enforceability of the remaining provisions shall not be affected. Such invalid provision shall, to the maximum extent permitted by applicable law, be replaced by a valid provision that most closely reflects the original intent.

#### 14. Entire Agreement

This Agreement (including the full text of the MIT License in Part 1 and all provisions of Part 2) constitutes the entire agreement between you and the Developer with respect to the Application, and supersedes any prior oral, written, or electronic understandings on the same subject. No modification of any provision shall be effective unless made in writing (including by email) and acknowledged by both parties.

#### 15. Language Versions

In the event of any inconsistency between the Simplified Chinese version and any other language version of this Agreement, **the Simplified Chinese version shall prevail**. The **English text** of the MIT License is the legally binding version.
