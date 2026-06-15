# 用户协议 / Terms of Service

最后更新 / Last updated: 2026-06-15

## 简体中文

> **重要提示**:请您仔细阅读本协议。**下载、安装或以任何方式使用本应用即视为您已充分理解、同意并接受本协议全部条款**。如您不同意任何条款,请立即停止使用并卸载本应用。

### 1. 接受条款

本《用户协议》(以下简称"本协议")是您(以下简称"用户")与本应用开发者(以下简称"开发者")之间就使用本应用所订立的具有法律约束力的协议。

下载、安装、注册、登录或以任何方式使用本应用,均视为用户已阅读、理解并同意接受本协议全部条款,以及本协议所引用的《隐私政策》等配套文件。

本应用面向具备完全民事行为能力的自然人。如您未满 14 周岁,请在法定监护人陪同下阅读本协议并在征得其同意后使用本应用。

### 2. 服务说明

本应用("Nous 记事" / "提醒事项")是由开发者独立维护的一款**本地优先**的待办提醒与灵感记录工具,主要功能包括:

- 创建、编辑、删除日程提醒
- 通过系统通知定时推送提醒
- 记录文本灵感与配图
- 可选启用本机端中文 OCR 文字识别(`google_mlkit_text_recognition`,模型内置,联网仅在使用 AI 润色时发生)
- 可选启用第三方 AI 文字润色与一键调整(由用户自行填入 DeepSeek API Key)
- 数据本地备份与恢复
- 30 天回收站(误删保护)

本应用**为免费个人作品,不提供商业级 SLA**。开发者保留随时修改、升级、暂停或终止部分或全部功能的权利,无需事先通知。

### 3. 账号与本地数据

本应用**不设云端账号系统**,不使用邮箱、手机号或第三方登录。

所有用户数据(提醒、灵感、设置、AI Key 等)均存储于用户设备本机 SQLite 数据库 `reminders.db` 内,位于操作系统分配的 App 沙盒目录中。卸载 App 或清除应用数据将**立即且不可逆**地删除所有本地数据。

因数据仅存于本机,**开发者无法访问、无法恢复用户数据**。请用户自行通过"设置 → 数据管理 → 导出备份"定期备份。

### 4. 用户行为规范

用户在使用本应用过程中承诺不得从事以下行为:

- 输入、上传、生成任何违反中华人民共和国法律、违反公共秩序与善良风俗、侵害他人合法权益的内容
- 试图对本应用进行反向工程、反编译、破解、篡改
- 绕过或破坏本应用的安全机制、访问控制、限流策略
- 利用本应用从事任何商业化转售、批量数据爬取、二次封装
- 利用本应用对任何第三方进行骚扰、欺诈、传播谣言
- 利用本应用的 AI 功能生成违法、违规、危害国家安全或他人权益的内容

### 5. 知识产权与许可

本应用(包括但不限于源代码、UI 设计、品牌、Logo、图标、文档)的所有知识产权归开发者所有,受著作权法及国际公约保护。

本应用依据本协议授予用户一项**有限的、不可转让的、不可再许可的、可撤销的个人非商业使用许可**,仅供用户在本机安装并按本协议约定使用本应用。

### 6. 用户输入内容授权

用户对其自行输入、上传、通过本应用产生的提醒文本、灵感文本、灵感图片等内容(以下简称"用户内容")拥有完整权利。

用户授予开发者一项**非独占、全球、免费、可再许可的使用权**,用于:

- 提供本应用的核心功能(提醒调度、AI 润色、数据备份等)
- 改进本应用服务质量(如错误诊断、去重、聚合统计)
- 履行法律法规规定的协助义务

上述授权在用户内容被删除后自动终止(但已分发的备份副本不受此限)。

### 7. AI 服务特别条款

本应用集成的 AI 文字润色与一键调整功能,**由第三方 API 提供商 DeepSeek(深度求索) 提供,开发者不直接运营生成式 AI 模型,亦不构成《生成式人工智能服务管理暂行办法》项下的"生成式 AI 服务提供者"**。

使用 AI 功能时,本应用将通过 HTTPS 将用户的提醒文本、描述、OCR 文本、当前时间与时区、自定义提示词(如有)发送至 DeepSeek API,用于生成调整建议。该过程由用户**主动触发**(`点击 AI 按钮`),且需用户已自行填入 DeepSeek API Key。

**用户理解并同意**:

- AI 输出结果**按"现状"提供**,开发者与 DeepSeek 不保证其准确性、可靠性、完整性、适用性
- AI 输出可能包含错误、偏见、误导性内容,**用户应自行判断并对最终采用的内容负责**
- 用户**不得**利用本应用 AI 功能输入任何违法、违规、危害国家安全、侵犯他人权益或违反 DeepSeek 用户协议的内容
- 用户理解 AI 输出可能与其他用户的输出相似,本应用不提供 AI 输出的"独家性"保证
- 开发者不会将用户输入用于训练任何自有 AI 模型
- 用户可随时在"设置 → AI 助手"中关闭 AI 功能开关或清除 API Key,以撤回对 AI 数据处理的同意

### 8. 第三方服务

本应用集成的第三方服务包括:

| 服务 | 用途 | 提供商 | 用户协议 / 隐私政策 |
|------|------|--------|-------------------|
| DeepSeek Chat Completions API | AI 文字润色 | 深度求索 | <https://www.deepseek.com/agreements/terms-of-service> |
| Google ML Kit Text Recognition | 本机 OCR 文字识别 | Google | <https://developers.google.com/ml-kit/terms> |
| 系统日历 | "加入日历"功能 | 操作系统 | 各 OS 厂商条款 |
| 系统通知 | 提醒推送 | 操作系统 | 各 OS 厂商条款 |

第三方服务的可用性、内容、隐私实践、变更与中断由该第三方负责,开发者不承担因第三方原因造成的损失。

### 9. 隐私与个人信息处理

本应用严格遵守"本地优先"原则,详细的数据处理实践见《隐私政策》。

根据《个人信息保护法》第 17 条,本协议作如下最小披露:

- **处理者**:开发者 DsDogs
- **联系方式**:见本协议第 16 条
- **处理目的**:提供提醒调度、灵感记录、AI 文字润色等本协议第 2 条所列功能
- **处理方式**:本地存储 + 用户主动触发时经 HTTPS 加密传输至第三方 API
- **个人信息种类**:用户主动输入的提醒文本、灵感文本、配图;经 OCR 识别的文字;用户填入的 DeepSeek API Key;**不收集**设备唯一标识、位置、通讯录
- **保存期限**:本地数据保存至用户删除或卸载;API Key 随设置清除而清除;备份文件由用户自行管理
- **用户权利**:查看、复制、更正、删除、撤回同意,均可在本应用内或通过"设置 → 数据管理"实现
- **法定其他事项**:详见《隐私政策》

用户输入本应用即视为同意上述处理。

### 10. 免责声明

本应用**按"现状"(AS IS)和"可提供"(AS AVAILABLE)基础提供**。在适用法律允许的最大范围内,开发者**不作出任何明示或暗示的担保或承诺**,包括但不限于:

- 不保证服务不中断、及时、安全、无错误
- 不保证服务满足用户的特定需求
- 不保证服务所含信息准确、可靠、完整
- 不保证服务缺陷一定会被修正
- 不保证本应用不含病毒、木马或其他有害成分

### 11. 责任限制

在适用法律允许的最大范围内,**开发者及其关联方、供应商、合作伙伴不对任何间接的、偶然的、特殊的、惩罚性的或衍生性的损害承担责任**,包括但不限于数据丢失、利润损失、商誉损失、业务中断等。

如有赔付义务,赔付上限为用户**最近 12 个月**为本应用支付的金额。由于本应用为免费服务,该上限为 **0 元**。

### 12. 不可抗力

因不可抗力(包括但不限于自然灾害、战争、网络攻击、电信运营商故障、第三方服务中断、政府行为)导致本应用无法正常运行的,开发者在该不可抗力影响范围内免责。

### 13. 协议变更

开发者有权根据法律法规变更、产品迭代等情况,随时修改本协议条款。修改后的协议将在本应用内公布,自公布之日起生效。

**重大变更**将通过应用内通知告知用户。若用户不同意变更后的协议,请立即停止使用本应用并卸载;**继续使用即视为接受变更**。

### 14. 终止

出现下列情形之一的,开发者有权暂停或终止向用户提供本应用的部分或全部功能,且无需承担任何责任:

- 用户违反本协议任何条款
- 用户利用本应用从事违法违规活动
- 因法律法规要求、政府命令、技术原因需终止
- 用户长期(连续 12 个月)未使用本应用

用户可随时通过卸载本应用终止本协议。终止后,用户本地数据将随卸载而清除,开发者无需承担数据恢复义务。

### 15. 法律适用与争议解决

本协议的订立、执行、解释及争议解决均适用**中华人民共和国法律**(不含港澳台地区法律)。

因本协议引起的或与本协议有关的任何争议,双方应首先友好协商解决;协商不成的,任一方有权将争议提交**开发者所在地有管辖权的人民法院**通过诉讼方式解决。

### 16. 联系方式

如您对本协议有任何疑问、意见、投诉或需行使您的权利,请通过以下方式联系开发者:

- **开发者**:DsDogs
- **邮箱**:【开发者邮箱】
- **应用名称**:Nous 记事 / 提醒事项
- **当前版本**:1.5.0

开发者将在收到邮件后 **15 个工作日** 内回复。

### 17. 其他

- **可分割性**:如本协议任何条款被有管辖权的人民法院认定为无效或不可执行,其他条款的效力不受影响。
- **完整协议**:本协议(含《隐私政策》)构成用户与开发者之间就本应用达成的完整协议,取代此前任何口头或书面约定。
- **不弃权**:开发者未行使本协议项下任何权利,不构成对该权利的弃权。
- **标题**:本协议各条款标题仅为阅读便利,不影响条款内容的解释。

**如本协议的简体中文版本与其他语言版本存在任何不一致,以简体中文版本为准。**

---

## English

> **Important Notice**: Please read this Agreement carefully. **By downloading, installing, or otherwise using this application, you acknowledge that you have read, understood, and agreed to be bound by all terms of this Agreement.** If you do not agree to any of the terms, please stop using the application immediately and uninstall it.

### 1. Acceptance of Terms

This Terms of Service (the "Agreement") is a legally binding agreement between you ("User") and the developer of this application ("Developer") governing your use of the application.

By downloading, installing, registering, logging in, or otherwise using the application, the User is deemed to have read, understood, and agreed to all terms of this Agreement, as well as the referenced Privacy Policy and other accompanying documents.

This application is intended for natural persons with full civil capacity. If you are under 14 years of age, please read this Agreement with your legal guardian and use the application only with their consent.

### 2. Description of Service

This application ("Nous 记事" / "Reminders") is a **local-first** to-do reminder and inspiration tool independently maintained by the Developer. Its main features include:

- Create, edit, and delete scheduled reminders
- Push reminder notifications via the system notification framework
- Capture text inspirations and accompanying images
- Optional on-device Chinese OCR text recognition (`google_mlkit_text_recognition`; model bundled, network is used only when AI polishing is triggered)
- Optional third-party AI text polishing and one-tap adjustment (powered by DeepSeek API using a user-supplied API key)
- Local backup and restore
- 30-day trash (mistake-recovery)

This application is a **free personal work and does not provide a commercial-grade SLA**. The Developer reserves the right to modify, upgrade, suspend, or discontinue any or all features at any time without prior notice.

### 3. Account and Local Data

This application **does not provide a cloud-based account system** and does not use email, phone number, or third-party login.

All user data (reminders, inspirations, settings, AI key, etc.) is stored in an on-device SQLite database named `reminders.db`, located in the operating-system-assigned app sandbox. Uninstalling the app or clearing app data will **immediately and irreversibly delete all local data**.

Because data resides only on the User's device, **the Developer cannot access or recover user data**. Users are encouraged to back up regularly via "Settings → Data Management → Export Backup".

### 4. User Conduct

The User agrees not to engage in any of the following conduct when using the application:

- Inputting, uploading, or generating any content that violates applicable law, public order, or good morals, or that infringes the lawful rights of others
- Attempting to reverse-engineer, decompile, crack, or tamper with the application
- Bypassing or breaking the application's security mechanisms, access control, or rate-limiting measures
- Commercial resale, bulk data scraping, or repackaging of the application
- Using the application to harass, defraud, or spread rumors against any third party
- Using the AI features to produce illegal, non-compliant, or harmful content

### 5. Intellectual Property and License

All intellectual property rights in and to the application (including but not limited to source code, UI design, branding, logo, icons, and documentation) belong to the Developer and are protected by copyright law and international conventions.

Subject to this Agreement, the Developer grants the User a **limited, non-transferable, non-sublicensable, revocable, personal, non-commercial license** to install the application on the User's device and to use it in accordance with this Agreement.

### 6. User Input License

The User retains full rights to all content created, uploaded, or generated through the application ("User Content"), including reminder text, inspiration text, and inspiration images.

The User grants the Developer a **non-exclusive, worldwide, royalty-free, sublicensable license** to use the User Content for the purposes of:

- Providing the core functions of the application (reminder scheduling, AI polishing, backup, etc.)
- Improving the application (e.g., error diagnostics, deduplication, aggregate statistics)
- Fulfilling statutory cooperation obligations

The above license automatically terminates when the User Content is deleted (except for backup copies already distributed).

### 7. AI Services Specific Terms

The AI text polishing and one-tap adjustment features integrated into the application are **provided by the third-party API provider DeepSeek**. The Developer does not directly operate any generative AI model and does not constitute a "Generative AI Service Provider" under applicable Chinese regulations.

When the AI features are used, the application sends, over HTTPS, the User's reminder text, description, OCR text, current time and timezone, and any custom system prompt to the DeepSeek API in order to generate adjustment suggestions. This transmission is **initiated by the User** (by tapping the AI button) and requires the User to have entered a valid DeepSeek API key.

**The User understands and agrees that**:

- AI outputs are provided **"as is"**; the Developer and DeepSeek do not warrant their accuracy, reliability, completeness, or fitness for any purpose
- AI outputs may contain errors, biases, or misleading content; **the User is solely responsible for evaluating and adopting the final content**
- The User **must not** use the AI features to input content that is illegal, non-compliant, harmful to national security, infringing on others' rights, or otherwise in violation of DeepSeek's terms
- The User understands that AI outputs may be similar to outputs provided to other users; the application does not guarantee the uniqueness of AI outputs
- The Developer will not use User inputs to train any proprietary AI model
- The User may disable the AI features or clear the API key at any time via "Settings → AI Assistant" to withdraw consent to AI data processing

### 8. Third-Party Services

The application integrates the following third-party services:

| Service | Purpose | Provider | Terms / Privacy |
|---------|---------|----------|------------------|
| DeepSeek Chat Completions API | AI text polishing | DeepSeek | <https://www.deepseek.com/agreements/terms-of-service> |
| Google ML Kit Text Recognition | On-device OCR | Google | <https://developers.google.com/ml-kit/terms> |
| System Calendar | "Add to Calendar" feature | OS vendor | Each OS vendor's terms |
| System Notifications | Reminder delivery | OS vendor | Each OS vendor's terms |

The availability, content, privacy practices, changes, and interruptions of any third-party service are the responsibility of that third party. The Developer is not liable for losses caused by any third party.

### 9. Privacy and Personal Information

The application strictly follows a "local-first" principle. Detailed data-handling practices are described in the Privacy Policy.

In accordance with applicable data-protection regulations, this Agreement provides the following minimum disclosures:

- **Controller**: Developer DsDogs
- **Contact**: see Section 16 of this Agreement
- **Purposes**: To provide the features described in Section 2 (reminder scheduling, inspiration capture, AI text polishing, etc.)
- **Methods**: Local storage; transmission over HTTPS to third-party APIs only when the User explicitly triggers a feature
- **Categories of personal information**: User-input reminder text, inspiration text, and images; OCR-recognized text; the DeepSeek API key entered by the User. The application **does not collect** device-unique identifiers, location, or contacts
- **Retention**: Local data is retained until the User deletes it or uninstalls; the API key is cleared when the User clears settings; backup files are managed by the User
- **User rights**: Access, copy, correction, deletion, and withdrawal of consent are all exercisable within the app or via "Settings → Data Management"
- **Other statutory matters**: see the Privacy Policy

By using the application, the User consents to the processing described above.

### 10. Disclaimer of Warranties

The application is provided on an **"AS IS" and "AS AVAILABLE" basis**. To the maximum extent permitted by applicable law, the Developer **makes no express or implied warranties or representations**, including but not limited to:

- That the service will be uninterrupted, timely, secure, or error-free
- That the service will meet the User's particular requirements
- That any information obtained through the service is accurate, reliable, or complete
- That defects in the service will be corrected
- That the application is free of viruses, trojan horses, or other harmful components

### 11. Limitation of Liability

To the maximum extent permitted by applicable law, **the Developer and its affiliates, suppliers, and partners shall not be liable for any indirect, incidental, special, punitive, or consequential damages**, including but not limited to loss of data, loss of profit, loss of goodwill, or business interruption.

Where any liability exists, the maximum aggregate liability shall not exceed the amount paid by the User for the application in the **preceding 12 months**. As the application is provided free of charge, this cap is **zero**.

### 12. Force Majeure

The Developer shall be excused from performance to the extent that performance is prevented or delayed by force majeure, including but not limited to natural disasters, war, cyber attacks, telecommunications operator failures, third-party service interruptions, or governmental actions.

### 13. Modifications to Terms

The Developer reserves the right to modify the terms of this Agreement at any time to reflect changes in law, product evolution, or other circumstances. The modified Agreement will be published within the application and will take effect upon publication.

**Material changes** will be communicated to Users via in-app notification. If the User does not agree to the modified Agreement, the User must stop using the application and uninstall it immediately; **continued use constitutes acceptance of the modification**.

### 14. Termination

The Developer may suspend or terminate any or all features provided to the User, without liability, in any of the following circumstances:

- The User breaches any term of this Agreement
- The User uses the application for illegal or non-compliant activities
- Termination is required by law, government order, or technical necessity
- The User has not used the application for an extended period (12 consecutive months)

The User may terminate this Agreement at any time by uninstalling the application. Upon termination, the User's local data will be deleted with the uninstallation, and the Developer has no obligation to recover data.

### 15. Governing Law and Dispute Resolution

The conclusion, performance, interpretation, and dispute resolution of this Agreement are governed by the **laws of the People's Republic of China** (excluding the laws of Hong Kong, Macao, and Taiwan).

Any dispute arising out of or in connection with this Agreement shall first be resolved through friendly negotiation. If negotiation fails, either party may submit the dispute to the **people's court with jurisdiction at the Developer's location** for resolution through litigation.

### 16. Contact Information

For any questions, comments, complaints, or to exercise your rights regarding this Agreement, please contact the Developer via:

- **Developer**: DsDogs
- **Email**: [Developer email]
- **Application name**: Nous 记事 / Reminders
- **Current version**: 1.5.0

The Developer will respond within **15 business days** of receiving your email.

### 17. Miscellaneous

- **Severability**: If any provision of this Agreement is held by a court of competent jurisdiction to be invalid or unenforceable, the validity and enforceability of the remaining provisions shall not be affected.
- **Entire agreement**: This Agreement (including the Privacy Policy) constitutes the entire agreement between the User and the Developer regarding the application, superseding any prior oral or written agreements.
- **No waiver**: Failure by the Developer to exercise any right under this Agreement shall not constitute a waiver of that right.
- **Headings**: Headings in this Agreement are for convenience only and do not affect the interpretation of any provision.

**In the event of any inconsistency between the Simplified Chinese version and any other language version of this Agreement, the Simplified Chinese version shall prevail.**
