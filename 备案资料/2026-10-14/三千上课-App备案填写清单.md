# 三千上课 App 备案填写清单

核对日期：2026-10-14（北京时间）。对象：`local.sanqian.schedule`。
当前状态：安卓签名字段已验证；联网与 SDK 已完成静态核对；接入方式仍待确认；iOS 普通分发证书已创建、导入并验证，最终发布包签名尚未核对。未提交任何备案申请。

## 1. 已核验的安卓填写值

| 字段 | 内容 | 依据 |
|---|---|---|
| App 名称 | 三千上课 | APK / 当前产品源码 |
| 平台 | Android | 实际 release APK |
| 软件包名称 | `local.sanqian.schedule` | APK Manifest |
| 版本 | `1.0.0`，版本号 `3` | APK Manifest |
| 证书 MD5 指纹 | `d69a21f2b351a885c8f5e8ed0b070e4c` | APK 签名证书 DER 的 MD5 |
| 公钥 | 下方完整 RSA 模数（十六进制），或同目录 `android-public-key-modulus.txt` | APK 公开证书 |
| 是否对外提供 SDK | 建议填“否” | 当前项目是独立 App，未发现对外 SDK 产品 |
| 服务内容分类 | 建议按实际目录选择“工具”下的课表/日程相关分类 | 建议，最终以后台选项及真实业务为准 |
| 功能简介草稿 | 个人课表管理工具，支持课程录入、课表图片识别导入、学校网页课表导入、多课表管理、日历提醒及桌面小组件。课程数据保存在设备本地。 | 当前源码，提交前确认与交付版本一致 |

公钥模数（512 个十六进制字符，整行复制）：

```text
92fd972dffd22ce061635e8c94571e9af67aca814e908cc25b7d5dfaa11402b0d6a105246a2c90ddfc310e59f3009799377afc53e1f2dd66251e54d87714ec4f926ef93338fd7afd612443a505bed0e1c843dd2ffada1b7af225024fb2ac535cd568015f5c8367d6638b86505af2de44a0acea91c00aa8bb5f21d0e7af2b8e6974535062c0d6b41f1e859efe0c4089402da2813ac921ae62146b6a78f711f732177d23df199f03f28fc1e4832c1805862ea958b2c536aecfc71b671a6efef5ac80cd341b5e0e78c2a291278bd97ca4141f2752478a72291446f29f05a552bb418c3ece90d663f145a8081f466a37b76996c0e20d57ce540e36b392e1e1443df5
```

这里的 MD5 是**证书 MD5**，不是 APK 文件 MD5，也不是公钥 MD5。`android-public-key.pem` 是通用公钥备份；备案字段按模数填写，不直接粘贴 PEM 标题或整个证书。

产物：`/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual/build/app/outputs/flutter-apk/app-release.apk`

APK SHA-256：`93ff590945358f22f92568b1745f932013014da0a2315bcabd49e1051a790c36`。

签名校验通过，单一签名者，v2 签名有效。APK 内证书与 `android/key.properties` 指向的 keystore / alias 导出的公开证书逐字节一致。只导出公开材料，无私钥、密码或 API Key。APK 与当前源码提交的构建对应关系未独立验证；本清单不代表功能或商店审核通过。

## 2. 实际联网与服务器

用户确认：阿里云服务器仅部署官网和下载页面，没有 App 后端接口。

| 域名 | 源码中的用途 | 证据边界 / 填写建议 |
|---|---|---|
| `api.deepseek.com` | Android HttpURLConnection / iOS URLSession 直接请求识别接口 | 源码及 APK 字符串命中；属于第三方 API，不是自有阿里云后台 |
| `iam.zgysyjy.org.cn` | 学校登录 | 源码及 APK 字符串命中；学校运营的服务 |
| `access.zgysyjy.org.cn` | 学校登录跳转允许域名 | 源码及 APK 字符串命中；允许列表不等于每次必定访问 |
| `wxt.zgysyjy.org.cn` | 学校教务网页，包含 7792 端口来源配置 | 源码及 APK 字符串命中；不填为自有域名 |
| `platform.deepseek.com` | 用户打开 API Key 管理网页 | 外部网页跳转，不是自建后台 |
| `github.com` | 打开上游项目网页 | 外部网页跳转，不是自建后台 |
| `sanqianshangke.top` | 用户确认作为官网和下载页面 | 扫描的 App 当前源码及 APK dex/libapp 中未发现该域名，不能据此把官网主机写成 App 接口服务器 |

这是静态核对，不是抓包结果，也不是全部实际联网域名的穷尽清单。SDK 遥测及学校页面子资源仍可能产生其他访问；代码中的 URL/字符串也不等于已经发出了网络请求。

**接入方式待确认：**阿里云文档把接入域名定义为 App 实际访问后台服务器的域名。现有架构不满足“已证明 App 后台部署在阿里云”这个前提。需向阿里云备案专员确认无自建后台、直连第三方服务的受理方式及域名填写规则；必要时核对目标应用分发平台提供的备案渠道。不能仅凭官网已备案推断 App 可沿用该服务器，也不应为了填表临时编造接口或自有关系。

可复制的咨询草稿（尚未发送）：

> 我准备备案个人课表 App“三千上课”，Android 包名为 local.sanqian.schedule。课程数据保存在手机本地，联网功能是直接请求第三方 DeepSeek API 和访问学校教务网页。本人阿里云服务器只承载已备案的官网与下载页面，目前 App 不调用该服务器的后台接口。请确认这种架构能否通过阿里云办理 App 备案；如可以，App 全部后台服务域名、接入阿里云服务器的域名及运行平台域名应如何按实际情况填写？是否需要第三方服务说明或其他材料？

## 3. 第三方 SDK 与 API 的区别

| 组件 | 实际核对结果 | 表单处理 |
|---|---|---|
| Google ML Kit 中文 OCR | Android 直接依赖 `text-recognition-chinese:16.0.1` | 确有嵌入 SDK；根据后台实际 SDK 类型和厂商选项填写，无法匹配时向备案专员确认 |
| Google ML Kit 扫码 | `mobile_scanner 7.1.3` 间接引入 `barcode-scanning:17.3.0` | 与 OCR 一并核对 Google/ML Kit 项；不可笼统声称“无第三方 SDK” |
| Google DataTransport / Firebase 基础组件 | release 依赖树存在传输、编码、组件注册依赖 | 不等于集成 Firebase Analytics；不能仅凭 Firebase 字样填成统计服务 |
| DeepSeek | 使用系统 HTTP 客户端直接调用 API，未发现 DeepSeek SDK 依赖 | 应描述为第三方 AI 接口；不要只因调用 API 就填成嵌入 DeepSeek SDK |
| Flutter 插件 | 图片选择、扫码、日历、SQLite、偏好存储、视频、外部链接等 | 具体插件与用途见下；是否对应备案后台 SDK 服务目录需逐项匹配 |
| iOS OCR / 扫码 | Vision / AVFoundation 与 mobile_scanner 插件 | 当前 Podfile.lock 未见 Google ML Kit；不要把安卓 Google ML Kit 直接照填到 iOS |

关键 Flutter 依赖（当前 pubspec.lock）：`mobile_scanner 7.1.3`、`image_picker 1.2.2`、`device_calendar 4.3.3`、`sqflite 2.4.2`、`shared_preferences 2.5.5`、`url_launcher 6.3.2`、`video_player 2.10.1`、`fluttertoast 8.2.14`。完整 Android release 依赖树在 `android-release-dependencies.txt`，这是当前配置解析结果，不是对 APK 依赖版本的完整反编译证明。

Google 官方说明 ML Kit 会采集诊断/使用情况数据；本地 OCR 不等于整个 SDK 完全不联网。本次未执行动态抓包或隐私验收，仅将该事实作为 SDK 填写依据。APK 扫描未命中 `com/umeng` 或 `com/google/firebase/analytics`，这是有限的静态证据，不是全面排除报告。

## 4. iOS 已确认与缺项

| 项目 | 状态 |
|---|---|
| Bundle ID | 本地归档为 `local.sanqian.schedule` |
| 上架团队 | 用户确认使用 Xinyu Li / `ZPAU8L65J4`，与本地归档一致 |
| 本地归档签名 | 开发描述文件，`get-task-allow=true`，不能据此认定已有正式分发签名 |
| 分发证书 | 已创建 Apple Distribution: Xinyu Li (ZPAU8L65J4)，证书 ID 6SXD8QVGQF；有效期至 2027-10-14，已导入登录钥匙串并验证为有效签名身份 |
| Apple 开发者后台 Identifiers | 已在 Tabbit 登录页面核验主 App local.sanqian.schedule 及 ScheduleWidgetExtension 均存在于 ZPAU8L65J4 团队 |
| 新分发证书公钥 / SHA-1 | 已提取，SHA-1 为 201aac298a78d50039b6a93190aff35ff9d16aba；公钥见 ios-distribution-public-key-hex.txt。后续发布须使用与备案一致的证书信息 |
| App Store Connect 记录 | 未核验，需要核对 App 与该 Bundle ID 的关联 |
| 主体对应关系 | 域名证书姓名为李滔、团队显示名为 Xinyu Li；不能只凭显示名判定关系，提交前核对实际主办者、开发者账号及授权材料 |

早期浏览器控制失败已解决：用户指定 Tabbit 后，通过其已登录页面完成证书创建与下载、Identifiers 读取。已有托管分发证书保留。

已完成：用户授权创建普通 Apple Distribution；CSR 使用 lxy013328@163.com / Xinyu Li，系统钥匙串保存对应私钥。下载证书与 CSR 公钥相同，导入后 security find-identity 显示有效 Apple Distribution 身份。公钥提供 PKCS#1 DER 十六进制与 RSA 模数两种格式，具体字段按备案后台的格式要求选择。尚未用新证书重新导出 App Store 发布包，不代表现有开发归档已变成分发签名。

## 5. 当前可以做与仍需等待

- 可以：填写已核验的安卓包名、公钥和证书 MD5；按真实功能准备名称、分类、说明。
- 待确认：阿里云能否受理当前无自建后台架构及域名具体填法；SDK 目录匹配；iOS 最终发布包签名、App Store Connect 记录及主体对应关系。
- 未上传 APK、未向客服发送消息、未提交 App 备案、未修改产品代码。后续明确授权后已向 Apple 上传 CSR、创建并安装普通分发证书；没有修改项目签名配置。

## 依据与附带证据

官方来源（2026-10-14 查询）：

- [阿里云：填写 App 特征信息](https://help.aliyun.com/zh/icp-filing/basic-icp-service/user-guide/fill-in-app-feature-information)：Android 模数/证书 MD5、iOS 公钥/证书 SHA-1 的获取方式。
- [阿里云：填写 App 信息](https://help.aliyun.com/zh/icp-filing/basic-icp-service/user-guide/fill-in-app-information)：SDK 字段和实际后台接入域名定义。
- [阿里云：SDK 服务类型与厂商](https://help.aliyun.com/zh/icp-filing/basic-icp-service/support/types-and-vendors-of-app-filing-sdk-services-functions)：目录随系统更新，以后台可选项为准。
- [阿里云：App 备案 FAQ](https://help.aliyun.com/zh/icp-filing/basic-icp-service/support/basics-about-icp-filling-for-apps)：网站备案与 App 备案并列、同名 App 添加多平台。
- [Google：ML Kit Android 数据披露](https://developers.google.com/ml-kit/android-data-disclosure)：SDK 数据收集的厂商声明，不等于本次运行实测。
- [工信部：App 备案通知解读](https://www.miit.gov.cn/jgsj/xgj/hlwgl/art/2023/art_564bf0759d7e41d5b4aa8ce4996b9e84.html)：可通过接入商或应用分发平台办理的制度路径，不代表特定商店已受理本 App。

本地证据：`android-filing-info.json`、`android-apk-verification.txt`、`android-signing-certificate.pem`、`android-public-key-modulus.txt`、`android-public-key.pem`、`android-static-network-markers.json`、`android-release-dependencies.txt`、`ios-local-signing-check.json`。

源码定位：`android/app/build.gradle:52`（包名）；`:98`（ML Kit）；`android/app/src/main/kotlin/local/sanqian/schedule/DeepSeekTimetableClient.kt:91`、`:140`（HTTP/API）；`SchoolPortalModels.kt:136`（学校域名）；`ios/Runner/DeepSeekTimetableClient.swift:7`；`ios/Runner/ScheduleImportPlugin.swift:225`；`lib/Pages/Settings/DeepSeekSettingsView.dart:15`；`lib/Pages/About/AboutView.dart:10`；`pubspec.lock`；`ios/Podfile.lock`。
