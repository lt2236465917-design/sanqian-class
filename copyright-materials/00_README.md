# 三千上课软件著作权申请材料准备包

本目录是本地审阅用的准备材料，不是已提交的登记申请，也没有向中国版权保护中心官网上传任何文件。

## 当前结论

| 材料 | 当前状态 | 用户下一步 |
| --- | --- | --- |
| 在线申请表 | 已整理字段清单；未登录、未填报、未提交 | 由申请人注册/实名认证并在线填报、确认软件全称、版本号、权利人和发表状态 |
| 申请确认签章页 | 不能代办 | 在线打印原页面，按官网原比例打印，申请人签字/盖章后扫描为 PDF 并上传 |
| 源程序鉴别材料 | 已生成 HTML 草稿、选材清单、结构报告和浏览器实际导出的 60 页 PDF | 审阅源码取样和脱敏；逐页目检 PDF 后由申请人最终确认 |
| 文档鉴别材料 | 已生成 20 页结构模板、功能说明草稿和浏览器实际导出的 20 页 PDF | 20 页只有在它构成完整最终文档时才可提交；申请人需逐条核实并补齐真实设计/使用说明 |
| 身份证明 | 不能代收集或伪造 | 按申请主体准备证件原件照片/扫描件 |
| 修改软件权利链 | 已保留 Apache-2.0、上游 URL 和修改说明草稿 | 用户自行核实权利人，并补办/取得原软件著作权人许可证明（如官网要求适用） |
| 技术字段与附件说明 | 已从源码抽取；版本、开发方式、发表状态等有待确认 | 申请人逐项确认并以在线表单为准 |

## 官网核验记录（与项目事实分开）

访问时间：2026-10-11（Asia/Shanghai）。只读访问以下页面，未登录、未上传、未提交：

- [所需文件](https://www.ccopyright.com.cn/index.php?optionid=1080)：申请文件包括软件著作权登记申请表、软件的鉴别材料和相关证明文件；在线填报、在线打印申请确认签章页，勿擅自更改内容、格式和打印比例，签章后上传 PDF。一般交存时，程序和任一文档前、后各连续 30 页；不足 60 页提交全部；通常程序每页不少于 50 行、文档每页不少于 30 行。修改他人软件须提交原软件著作权人许可证明原件照片或扫描件。身份证明按申请主体类型提交。
- [填表说明](https://www.ccopyright.com.cn/index.php?optionid=1081)：软件全称应简短明确且在材料中保持一致；版本号建议 `V1.0` 或 `1.0`；修改软件填写修改说明；开发完成日期是全部固定在有形载体的日期；发表状态填写首次公之于众的日期/地点或未发表；开发方式、权利取得方式和硬件/软件环境等按实际情况填写。申请人签章处，自然人应本人签名或人名章，机构应加盖公章且为鲜章。
- [问题问答](https://www.ccopyright.com.cn/index.php?optionid=1087)：当前分页 1-3 说明文档是描述程序内容、组成、设计、功能规格、开发情况、测试结果或使用方法的文字/图表；鉴别材料需要页眉页脚，页眉建议软件名称和版本号，右上角标注页码；源程序正文从第 1 页编到第 60 页，文档从目录开始编到第 60 页。分页 2 说明注册、实名认证、在线填报上传、确认提交、受理审查和登记/补正流程；分页 3 说明软件著作权保护的是程序及文档的表达形式，不延及思想、处理过程和技术方案。具体以官网当前流程为准。

“前后各连续 30 页”“通常不少于 50/30 行”是官网的一般交存规则；官网还列有例外交存方式。此目录没有把一般规则写成适用于所有案件的绝对结论，最终以申请人案情和官网当前表单为准。

## 项目事实（来自源码，不等于官网要求）

- 当前仓库：`/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`，分支 `main`，材料生成时 HEAD 为 `49e01ac`；用户提供的旧 HEAD `c691223` 是材料生成前的提交。
- 本次登记材料页眉已统一暂定为 `V1.0`，符合官网建议格式。源码仍有 `pubspec.yaml` 的 `1.0.0+77` 和 iOS `MARKETING_VERSION = 4.0.1`；这两个是产品发布元数据，申请人必须确认 `V1.0` 对应的软件快照，并在提交前决定是否另行调整产品配置。
- 用户可见品牌为“三千上课”；Android applicationId 与 iOS Bundle ID 主要配置为 `local.sanqian.schedule`。
- 主要实现使用 Flutter/Dart、Android Java/Kotlin、iOS Swift；仓库还包含 OpenHarmony ETS 工程。代码量应按申请人选定的源程序口径确认，不能把测试、第三方、生成文件或真实数据当作纯业务源程序量。
- 当前仓库没有 APK、AAB 或 IPA 产物；发表状态、首次发表日期/地点不能据此推断。
- `res/schedules/zgysyjy_2026_fall.json` 是已跟踪的真实课程数据（含课程、教师、教室等），本准备包排除它，材料审核时仍要检查 PDF 是否误带入。
- About 页面保留上游地址 `https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter` 和 Apache-2.0 说明。`wheretosleepinnju`/`NJU` 在少量兼容通道、学校模板或来源链接中仍可能出现；这些是上游来源或技术兼容标识，不等于当前用户可见品牌。Android manifest 还保留注释掉的旧 Umeng URI，材料选页时应排除或标注。

### 旧标识排除边界

| 标识 | 当前材料结论 |
| --- | --- |
| `wheretosleepinnju` | **保留必要技术标识**：仍用于部分 Widget/原生通道兼容；不作为软件名称、用户可见品牌或权利人名称。源程序草稿中的通道字面值因此没有伪造替换。 |
| `NJU` / `NJU-Class-Shedule` | **只保留来源链**：上游 GitHub URL 和 Apache-2.0 归属必须保留；用户可见旧品牌文案不作为三千上课材料名称。 |
| `chaoxi` | **保留必要平台通道标识**：源码中是原生导航通道名，不是用户可见软件名称；材料中不将其解释为品牌或权利人。 |
| 旧 Umeng URI | **排除**：仅在 Android manifest 注释中出现，未作为当前功能、统计服务或品牌提交；它不进入本次源程序选页。 |

## 文件索引

- `01_online-application-fields.md`：在线申请表字段、源码证据、待用户确认项。
- `02_signature-scan-guide.md`：打印、签章、扫描和上传步骤；明确不能代办的动作。
- `03_source-identification.md`：源程序取样口径、官网依据、脱敏边界和生成物说明。
- `04_document-identification.md`：文档鉴别材料模板口径和待补文档边界。
- `05_identity-documents.md`：按主体类型的身份证明待提供清单。
- `06_rights-chain.md`：Apache-2.0、上游来源、修改说明和待补许可证明。
- `07_technical-fields-and-attachments.md`：技术字段、附件说明和验证边界。
- `generated/source-identification-material.html`：60 页源程序打印草稿。
- `generated/documentation-identification-material.html`：20 页文档结构草稿，不应直接视为最终用户手册。
- `generated/source-selection-manifest.json`：选入文件、行数和排除规则。
- `generated/source-identification-material.browser.pdf`：浏览器实际打印的 60 页源程序 PDF 草稿。
- `generated/documentation-identification-material.browser.pdf`：浏览器实际打印的 20 页文档 PDF 草稿。
- `generated/validation-report.json`：HTML 和浏览器 PDF 的页数、页眉页脚页码、行数代理与敏感模式检查；`pdfRenderNotVerified: false` 仅表示本地 PDF 已核对，不表示版权中心已接受。
- `scripts/generate_materials.py`：可重复生成脚本，默认使用本次暂定版本 `V1.0`。
- `scripts/check_sensitive.py`：对生成 HTML 和 PDF 文本执行私钥、token、密钥形状扫描。

## 重生成与检查

在仓库根目录执行：

```bash
python3 copyright-materials/scripts/generate_materials.py --version V1.0
python3 copyright-materials/scripts/check_sensitive.py
python3 -m json.tool copyright-materials/generated/validation-report.json >/dev/null
git diff --check -- copyright-materials
```

用户确认最终版本后，按同一版本重新生成并重新打印；申请表、页眉、证书版本号必须保持一致。产品源代码中的发布元数据冲突仍需用户决定，材料包没有擅自修改业务源码。

## 明确不能由本准备包完成的事项

账号注册/实名认证、在线申请提交、首次发表事实确认、自然人签字、机构鲜章、证件扫描、原权利人书面许可证明、外部网站上传、缴费、补正和最终法律/权利人判断均留给用户或有权代理人。本目录不代替这些动作，也不保存用户账号、密码、API key、签名文件或证件。
