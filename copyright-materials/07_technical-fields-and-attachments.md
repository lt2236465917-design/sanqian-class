# 07 技术字段与附件说明

## 可从源码支持的技术摘要

| 字段 | 源码支持的草稿 | 边界 |
| --- | --- | --- |
| 开发平台 | Flutter/Dart 跨平台 UI；Android Java/Kotlin；iOS Swift；仓库含 OpenHarmony ETS | 申请是否纳入 OpenHarmony 由用户确认 |
| 运行平台 | README 标示 Android、iOS；项目有 OpenHarmony 目录 | 不能据目录推断已发布 |
| 主要存储 | SQLite 相关组件，本地保存课程和课表 | 具体版本按 `pubspec.yaml`/构建环境确认 |
| 识别技术 | Android ML Kit 中文 OCR；iOS Vision；用户确认后可调用 DeepSeek 识别 | 不放 API key、账号、密码；网络服务/账户归属由用户确认 |
| 主要功能 | 日/周/月查看、手动新增编辑、多课表、图片/学校网页导入复核、二维码导入导出、系统日历、提醒、小组件、离线查看 | 表单文字由用户最终确认 |
| 技术特点 | 导入后复核再保存；二维码压缩/校验；原生桥接；凭据安全存储；Widget/Live Activity | 不把测试、真实数据或上游思想写成独立权利 |
| 编程语言 | Dart、Swift、Kotlin、Java；若纳入 OpenHarmony 再确认 ETS | “全部语言”按最终申请范围确认 |
| 源程序量 | 生成清单记录当前选材行数；另有 Dart/Swift/Kotlin/Java/ETS 业务统计 | 用户选择统计口径并复核总行数 |
| 版本号 | `pubspec.yaml` 为 `1.0.0+77`；Xcode 工程有 `4.0.1` | **必须统一**，页眉随之重生成 |

## 附件说明草稿

1. 在线申请表及官网生成的申请确认签章页 PDF：用户在线完成。
2. 源程序鉴别材料：`generated/source-identification-material.html` 打印 PDF，附 `source-selection-manifest.json` 作为内部审计记录；提交前用户检查脱敏和版本。
3. 文档鉴别材料：用户确认后的设计说明书/用户手册；当前 HTML 只是模板。
4. 身份证明：按 `05_identity-documents.md` 由用户提供。
5. 权利归属/修改许可：`LICENSE`、上游 URL、修改说明，以及用户自行取得的许可证明（如适用）。
6. 其他合同/任务书/转让或继承证明：仅在实际存在并适用时由用户提供。

## 已验证的仓库检查

- `flutter test` 159 项通过；Android `:app:testDebugUnitTest` 通过；`git diff --check` 通过；`flutter analyze` 为 79 条 info、0 warning、0 error（这些不是官网软著门槛）。
- 当前仓库没有 APK/AAB/IPA；不据此填写发表状态。
- `res/schedules/zgysyjy_2026_fall.json` 含真实课程、教师、教室数据；已从生成源程序材料排除。
- 未在跟踪源码中发现硬编码生产密钥；代码仍包含账号、密码、API key 的处理逻辑和测试用 `SECRET`，所以材料生成明确排除测试、fixture、本机配置、签名文件，并要求最终 PDF 再扫一遍。

## 建议最终复核命令

```bash
git grep -n -i -e '南哪课表' -e 'NJU-Class' -e 'wheretosleepinnju' -e '友盟' -e 'umeng'
git ls-files | rg -i '(nan|nanj|nju|sleep|whereto|chaoxi|umeng|analytics)'
python3 copyright-materials/scripts/generate_materials.py --version V1.0
cat copyright-materials/generated/validation-report.json
git diff --check -- copyright-materials
```

这些命令只用于本地审计；不上传、不提交外部网站、不读取账号或证件。
