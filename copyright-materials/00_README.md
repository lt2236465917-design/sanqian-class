# 三千上课软件著作权申请材料准备包

本目录是本地审阅用的准备材料，不是已提交的登记申请，也没有向中国版权保护中心官网上传任何文件。

## 当前结论

| 材料 | 当前状态 | 用户下一步 |
| --- | --- | --- |
| 在线申请表 | 已整理字段清单；未登录、未填报、未提交 | 由申请人注册/实名认证并在线填报、确认软件全称、版本号、权利人和发表状态 |
| 申请确认签章页 | 不能代办 | 在线打印原页面，按官网原比例打印，申请人签字/盖章后扫描为 PDF 并上传 |
| 源程序鉴别材料 | 已生成可打印 HTML 草稿、选材清单和结构校验报告 | 先统一版本号；审阅源码取样和脱敏；用浏览器打印为 PDF 后由申请人最终确认 |
| 文档鉴别材料 | 已生成 20 页结构模板和功能说明草稿 | 申请人逐条核实、补齐真实设计/使用说明；确认其作为文档鉴别材料 |
| 身份证明 | 不能代收集或伪造 | 按申请主体准备证件原件照片/扫描件 |
| 修改软件权利链 | 已保留 Apache-2.0、上游 URL 和修改说明草稿 | 用户自行核实权利人，并补办/取得原软件著作权人许可证明（如官网要求适用） |
| 技术字段与附件说明 | 已从源码抽取；版本、开发方式、发表状态等有待确认 | 申请人逐项确认并以在线表单为准 |

## 官网核验记录（与项目事实分开）

访问时间：2026-10-11（Asia/Shanghai）。只读访问以下页面，未登录、未上传、未提交：

- [所需文件](https://www.ccopyright.com.cn/index.php?optionid=1080)：申请文件包括软件著作权登记申请表、软件的鉴别材料和相关证明文件；在线填报、在线打印申请确认签章页，勿擅自更改内容、格式和打印比例，签章后上传 PDF。一般交存时，程序和任一文档前、后各连续 30 页；不足 60 页提交全部；通常程序每页不少于 50 行、文档每页不少于 30 行。修改他人软件须提交原软件著作权人许可证明原件照片或扫描件。身份证明按申请主体类型提交。
- [填表说明](https://www.ccopyright.com.cn/index.php?optionid=1081)：软件全称应简短明确且在材料中保持一致；版本号建议 `V1.0` 或 `1.0`；修改软件填写修改说明；开发完成日期是全部固定在有形载体的日期；发表状态填写首次公之于众的日期/地点或未发表；开发方式、权利取得方式和硬件/软件环境等按实际情况填写。申请人签章处，自然人应本人签名或人名章，机构应加盖公章且为鲜章。
- [问题问答](https://www.ccopyright.com.cn/index.php?optionid=1087)：文档是描述程序内容、组成、设计、功能规格、开发情况、测试结果或使用方法的文字/图表，例如程序设计说明书、流程图、用户手册。鉴别材料需要页眉页脚；页眉建议软件名称和版本号，右上角标注页码；源程序正文从第 1 页编到第 60 页，文档从目录开始编到第 60 页。在线流程为注册、实名认证、在线填报上传、确认提交、受理审查和登记/补正。问答分页还说明受理后 60 日内审查、收到补正通知后 30 日内补正，具体以官网当前流程为准。

“前后各连续 30 页”“通常不少于 50/30 行”是官网的一般交存规则；官网还列有例外交存方式。此目录没有把一般规则写成适用于所有案件的绝对结论，最终以申请人案情和官网当前表单为准。

## 项目事实（来自源码，不等于官网要求）

- 当前仓库：`/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`，分支 `main`，HEAD `c69122325dc2e28dbabe650313b48f9fc43fe16b`。
- `pubspec.yaml` 当前为 `sanqian_class`、版本 `1.0.0+77`；iOS Xcode 工程另有 `MARKETING_VERSION = 4.0.1`。申请表和页眉版本号不能同时沿用两套值，必须由申请人先统一。
- 用户可见品牌为“三千上课”；Android applicationId 与 iOS Bundle ID 主要配置为 `local.sanqian.schedule`。
- 主要实现使用 Flutter/Dart、Android Java/Kotlin、iOS Swift；仓库还包含 OpenHarmony ETS 工程。代码量应按申请人选定的源程序口径确认，不能把测试、第三方、生成文件或真实数据当作纯业务源程序量。
- 当前仓库没有 APK、AAB 或 IPA 产物；发表状态、首次发表日期/地点不能据此推断。
- `res/schedules/zgysyjy_2026_fall.json` 是已跟踪的真实课程数据（含课程、教师、教室等），本准备包排除它，材料审核时仍要检查 PDF 是否误带入。
- About 页面保留上游地址 `https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter` 和 Apache-2.0 说明。`wheretosleepinnju`/`NJU` 在少量兼容通道、学校模板或来源链接中仍可能出现；这些是上游来源或技术兼容标识，不等于当前用户可见品牌。Android manifest 还保留注释掉的旧 Umeng URI，材料选页时应排除或标注。

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
- `generated/validation-report.json`：HTML 结构的页数、行数、页眉页脚页码和生成物敏感模式检查；`pdfRenderNotVerified: true` 表示尚未证明浏览器打印出的物理 PDF 页数。
- `scripts/generate_materials.py`：可重复生成脚本，默认使用占位版本 `V1.0`。
- `scripts/check_sensitive.py`：对生成目录执行私钥、token、密钥形状扫描。

## 重生成与检查

在仓库根目录执行：

```bash
python3 copyright-materials/scripts/generate_materials.py --version V1.0
python3 -m json.tool copyright-materials/generated/validation-report.json >/dev/null
git diff --check -- copyright-materials
```

用户确定版本后，将 `V1.0` 替换成申请表最终版本（例如 `1.0`），重新生成并重新打印；申请表、页眉、版本证书必须保持一致。

## 明确不能由本准备包完成的事项

账号注册/实名认证、在线申请提交、首次发表事实确认、自然人签字、机构鲜章、证件扫描、原权利人书面许可证明、外部网站上传、缴费、补正和最终法律/权利人判断均留给用户或有权代理人。本目录不代替这些动作，也不保存用户账号、密码、API key、签名文件或证件。
