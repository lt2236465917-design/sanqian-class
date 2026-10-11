# 01 在线申请表字段清单

状态：字段已整理；账号登录、实名认证、在线填报、上传和提交由用户完成。

## 官网字段依据

来源：[填表说明](https://www.ccopyright.com.cn/index.php?optionid=1081)、[所需文件](https://www.ccopyright.com.cn/index.php?optionid=1080)、[问题问答](https://www.ccopyright.com.cn/index.php?optionid=1087)。官网要求软件全称在材料中保持一致，版本号以申请表为准且页眉版本号一致；修改软件要填写修改说明；开发完成日期、发表状态、开发方式、权利取得方式、环境、编程语言、源程序量和主要功能/技术特点均按实际情况填写。

## 待填写/待确认字段

| 表单字段 | 当前源码依据或建议 | 状态 |
| --- | --- | --- |
| 申请人/著作权人 | 个人或机构名称、证件号码、地址、联系人 | **需用户提供**；本包不收集证件 |
| 软件全称 | 建议统一为 `三千上课`，并在申请表、页眉、附件中完全一致 | **需用户确认** |
| 软件简称 | 无简称可按官网规则留空 | **需用户确认** |
| 软件版本号 | 申请表和材料页眉统一填写 `V1.0`；产品版本名为 `1.0.0`，Android 构建号为 `77`，iOS `MARKETING_VERSION` 已统一为 `1.0.0` | **已按本次登记版本统一；提交时保持完全一致** |
| 软件作品说明 | 选择“修改”并写明基于上游项目的修改范围 | **需用户确认** |
| 前期版本登记号 | 未从当前仓库确认有登记号 | **需用户确认**；没有则留空 |
| 开发完成日期 | 以全部固定在有形载体的日期为准 | **需用户提供/确认** |
| 发表状态 | 当前仓库没有 APK/AAB/IPA，不能推断已发表；按真实首次公之于众的日期/地点或未发表填写 | **需用户确认** |
| 开发方式 | 源码显示个人仓库开发，但合作/委托/下达任务不能凭源码推断 | **需用户确认** |
| 权利取得方式 | 申请人应按原始/继受及实际合同证明填写；Apache-2.0 上游许可不等于已取得单独书面授权 | **需用户确认并补证明** |
| 修改说明 | 见 `06_rights-chain.md`，应由用户按实际贡献和权利关系核实 | **草稿，需用户确认** |
| 硬件环境 | 运行 Android/iOS 的兼容设备；具体最低型号由申请人按真实测试/发布口径填写 | **需用户确认** |
| 软件环境 | Flutter/Dart；Android 与 iOS；Android 原生 Java/Kotlin，iOS Swift；必要时填版本 | **源码已核对，版本仍需用户确认** |
| 编程语言 | Dart、Kotlin、Java、Swift；若将 OpenHarmony 版本纳入申请，另确认 ETS 是否列入 | **需用户确认口径** |
| 源程序量 | 生成清单给出选材行数；不能把测试、fixture、生成文件、依赖或文档算入 | **需用户确认统计口径** |
| 主要功能 | 日/周/月课表、手动编辑、图片/学校网页导入复核、二维码、日历/提醒、小组件、离线本地保存 | **源码支持；用户确认表述** |
| 技术特点 | Flutter 跨平台、本地 SQLite、OCR/识别复核、二维码压缩校验、原生桥接、Widget/Live Activity | **源码支持；用户确认表述** |
| 申请办理方式 | 著作权人自行办理或另行委托 | **需用户选择** |
| 代理信息 | 代理人、范围、权限、期限 | **需用户提供；本包不代办** |

## 当前项目事实证据

- 名称/版本：`pubspec.yaml:1-8`。
- Android 标识：`android/app/build.gradle:31,52`。
- iOS 显示名和 Bundle：`ios/Runner/Info.plist:17-31`、`ios/Runner.xcodeproj/project.pbxproj`。
- 功能入口：`lib/Pages/Personal/PersonalHomeView.dart`、`lib/Pages/Import/`、`lib/Pages/Share/`、`lib/Utils/ScheduleCalendarExporter.dart`、`lib/core/widget_data/`、`android/app/src/main/`、`ios/Runner/`、`ios/ScheduleWidget/`。
- 上游及许可证：`lib/Pages/About/AboutView.dart:10,46-50`、根目录 `LICENSE`。

不要把这些源码路径直接粘贴到在线表单的技术说明中；它们是本地审计证据。
