# 三千上课 Android 无 GMS 验证与 SDK 方案比较

日期：2026-10-21（Asia/Shanghai）
Task-ID: android-mlkit-no-gms-20261021-01a15e06
Owner-Session: 01a15e06-a282-7652-909b-21d95cc33774

结论：建议暂时保留当前随包 ML Kit OCR/摄像头扫码，以及既有 zxing2 相册二维码路径。当前 release 在纯 AOSP、无 GMS、断网条件下已经取得三条路径的运行证据，不能以“Google 产品”为由认定必须 GMS 或翻墙。国内真机全面兼容仍未验证；更换 SDK 的质量、性能和体积收益也未验证。

本次为验证与方案比较，未修改任何产品源码、SDK、包名、正式签名或 iOS 配置，未使用收费 API。

## 已验证基线

- 实际目录 `/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`，分支 `main`。
- 本地 `0e95b3187d418744613c5c45bb9f3148f72b2893`。开始时本机 `origin/main` 跟踪引用仍为 `db31944caa515abe7e6f3ff1fdd805c363ebc372`，显示本地领先 3 提交；但本轮 `git ls-remote origin refs/heads/main` 现场查询远端已是 `0e95b31`，与本地一致。跟踪引用已过时；本次没有 push/fetch/reset。
- release APK：`build/app/outputs/flutter-apk/app-release.apk`；SHA256 `1c2f3a90a747e7dcc82d55adc103f6f8c86b4c22130b2e2afee3ccd2ecfef42e`；58,083,159 bytes（约 55.39 MiB）。本次使用已有同哈希成品，没有重编译或改签正式 App。
- 包名 `love.sanqian.schedule`；版本 `1.0.0(1)`；实际 `minSdk=24`、`targetSdk=36`。Android 7.0 以下无法安装当前 App，此限制独立于 GMS。
- 第一阶段开始时 `adb devices -l` 无连接设备，当时没有国内真机证据；后续 Xiaomi 14 结果见文末补充。现有 3 个 AVD 都是 `google_apis`，没有通过卸载 GMS 将其伪装成无 GMS 环境。

## 源码与实际依赖

| 路径 | 当前实现 | release 依赖和行为 |
|---|---|---|
| 中文 OCR 辅助复核 | `MlKitChineseTimetableOcr.kt` | `com.google.mlkit:text-recognition-chinese:16.0.1`，随包模型 |
| 摄像头实时扫码 | `QRScanView.dart` → `mobile_scanner 7.1.3` | CameraX 1.5.1 + `com.google.mlkit:barcode-scanning:17.3.0`，当前随包默认路径 |
| 相册二维码 | `QRScanView.dart` → `image_picker` + `image` + `zxing2 0.2.4` | Dart 本地二维码解码，不调用 ML Kit 的 `analyzeImage` |

`release-dependencies.txt` 是现场 `:app:dependencies --configuration releaseRuntimeClasspath --offline` 成功输出。随包入口仍传递依赖 `play-services-mlkit-*` 客户端以及 tasks 等库；依赖名称不是设备安装 GMS 的证明。插件可切换 `dev.steenbakker.mobile_scanner.useUnbundled=true`，本次实际解析为随包路径。

实际 APK 模型与原生库见 `release-audit.json`：OCR 模型压缩约 1.92 MB，OCR 三 ABI 原生库合计约 12.39 MB；扫码模型约 0.88 MB，三 ABI barhopper 原生库合计约 6.34 MB。这些是 ZIP 条目压缩大小相加，非完整 SDK 占用，也不能直接当作替换后的 APK 净变化。另检查了两个 arm64 ML Kit 原生库的 ELF LOAD 段，均为 `0x4000`（16 KB）对齐，见 `native-alignment.json`；这只是静态必要条件，不代表整 App 在 16 KB 页设备上已完成运行验证。

OCR 不是默认照片导入的主识别器。`ScheduleImportPlugin.kt:150` 的 OCR 复核先生成本机文字，再调用 `client.recognizeImages(images, pages)`；默认照片路径直接调用 DeepSeek。即使本地 OCR 离线可用，完整 AI 课表导入依然需要网络、配置和付费服务。本次不触发该网络链路。

## 官方资料（来源陈述）

- [ML Kit 安装路径](https://developers.google.com/ml-kit/tips/installation-paths)：bundled 模型随 App 安装即可用、支持安装后断网；unbundled 模型由 Google Play services 下载管理。
- [中文 OCR Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)：当前中文随包坐标与代码一致；需要满足图片字符尺寸等条件。
- [Barcode Android](https://developers.google.com/ml-kit/vision/barcode-scanning/android)：随包扫码坐标为 17.3.0；动态路径坐标不同。对焦、条码像素密度影响识别。
- [mobile_scanner 7.1.3](https://pub.dev/packages/mobile_scanner/versions/7.1.3)：Android 默认随包；切换 unbundled 后依赖 Play services 下载。
- [ML Kit 隐私说明](https://developers.google.com/ml-kit/terms)：输入和识别输出在本机处理，不发送给 Google；SDK 仍可能向 Google 联系并发送性能/使用指标。因此“离线能识别”不等于“联网时绝无 SDK 通信”。本次无完整网络隐私审计。

## 运行证据

环境：本次新建 `sanqian_nogms_01a15e06`，官方 `system-images;android-35;default;arm64-v8a` r2，Android 15/API35、arm64、4 KB 页。`pm list packages -u`（包含卸载记录）中无 `com.google.android.gms`、`com.google.android.gsf`、`com.android.vending`。先启用飞行模式、关闭 Wi-Fi/移动数据，之后才安装原 release APK。最终 `dumpsys connectivity` 显示 `Active default network: none`。设备内 APK SHA256 与原成品一致。见 [环境记录](device-baseline.json)、[结果摘要](results.json)。

| 路径 | 实际执行与结果 | 证据与验证边界 |
|---|---|---|
| 中文 OCR | 在原 release 进程中调用现有 `MlKitChineseTimetableOcr.recognize`。合成 1600×900 中文课表文字 JPEG，首次 105 ms、第二次 40 ms；读出课程名、时间、A101 | [结果 JSON](ocr-result.json)、[原始输出](ocr-instrumentation.txt)。本地原生方法通过；未走 OCR UI→DeepSeek 全链路。时间仅属此模拟器/样本，不是手机性能指标 |
| 相册二维码 | 原 App 设置→课表导入与导出→导入课表→相册导入二维码→系统 Photo Picker 选 PNG→显示“无 GMS 离线验证”的课表导入确认页 | [UI XML](gallery-result.xml)、[结果截图](gallery-result.png)。原 release UI+真实本地解码路径通过；未确认写入课表 |
| 摄像头扫码 | 原 App 开启相机、授权相机权限，经模拟器 camera `imagefile` 输入→CameraX 帧→mobile_scanner→ML Kit→协议解析→显示相同导入确认页；日志明确选择本地 barcode 模块 | [运行日志](camera-success-runtime.log)、[UI XML](camera-adjusted-result.xml)、[结果截图](camera-adjusted-result.png)。原 release 相机调用链通过；输入是模拟器注入图，没有真实光学、对焦、反光/运动或国产 OEM Camera HAL 证据 |

OCR 探针仅包含 Android instrumentation 和反射调用，不复制 SDK 或另建识别实现；按现有 R8 mapping 定位 release 中的 `love.sanqian.schedule.d.b`，直接读取该 App 的模型/代码。探针与目标同签名，未更改目标 APK；源文件保留于 `probe/`，临时编译输出收尾清除。

合成 OCR 出现“教学楼”前多一个 `|`，空格/分词也有差异。因此结果不是准确率 100%，更不是密集真实课表的质量结论。二维码为符合当前协议的 210 字符、0 课程合成分享串，验证了解码和确认页，不涵盖多分片/高密度二维码或导入持久化。

摄像头验证第一轮未成功：专用 AVD 未配前摄导致 CameraX 重试；无留白的注入二维码被裁切。启用模拟前摄、增加输入画布留白并调整位置后成功，产品源码和 SDK 未修改。这些是本轮模拟器配置/输入的失败记录，不能作为国内手机必现问题，也不能略过后将第一轮记为成功。

这三条运行证据支持“当前随包实现可以在没有 GMS、没有网络的 Android 环境工作”，不支持“所有国内手机均可用”。

## 方案比较

| 方案 | 质量与速度 | 体积与隐私 | 维护成本与判断 |
|---|---|---|---|
| 保留当前随包 ML Kit + 相册 zxing2 | AOSP 无 GMS 运行已通过；仍需真机同样本质量/延迟验证 | 模型随包；识别数据本机处理，但 SDK 指标行为需按官方说明披露 | 无迁移成本；本轮推荐保留，补国内真机再决策 |
| CameraX + ZXing core / zxing-cpp | 可本地实时解码；密集、倾斜、反光、弱光和连续分片码需对照测试，不能预言一定更快/更准 | 无 ML 模型，预期可减少扫码部分体积，净变化需要实际构建；可减少对应 Google ML Kit 指标依赖 | 当前已用 CameraX，核心工作是解码、帧旋转/裁切、背压、生命周期、错误/权限和 Flutter 桥接；Java ZXing 上游维护模式，选型需比较活跃 C++ 分支与 JNI/ABI 成本 |
| PaddleOCR 本机文字识别 | 支持中文端侧模型，但本项目质量、速度、峰值内存未测试；需同一批密集真实课表比较 | 需捆绑推理引擎、检测/识别模型、字典及原生库，不能假定比 ML Kit 小；可由应用控制本地推理流程 | 接入成本较高；模型版本、量化、预后处理、ABI/16KB 页适配、取消语义和 OcrPage/归一化框合同都需维护 |

[PaddleOCR 端侧部署](https://www.paddleocr.ai/v3.0.3/en/version3.x/deployment/on_device_deployment.html)提供 PP-OCRv3/v4/v5 mobile 的 Android CPU 部署流程，需要 Paddle Lite、NDK/CMake、模型和字典；这是可行路线资料，不是本 App 实测。旧 [Paddle Lite 示例](https://github.com/PaddlePaddle/PaddleOCR/blob/main/deploy/lite/readme.md)中的 PP-OCRv3 模型体积 16.2M / slim 5.9M 仅为该旧版模型示例，不含完整 APK 成本，不能代指最新方案。

[ZXing 上游](https://github.com/zxing/zxing)声明 Java 项目主要接受修复和小改动；旧 Barcode Scanner App 不支持 Android 14 的说明不应误解为 ZXing core 算法库不可用于现代 CameraX。上游列出的 [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp)可作为后续候选；本次未接入。CameraX 官方 [ImageAnalysis](https://developer.android.com/media/camera/camerax/analyze)提供逐帧分析及保留最新帧策略。

## 待验证项和决策门槛

- 至少一台真实无 GMS 的国产 Android 手机完成离线首次启动、本地 OCR、相机与相册入口验证；完整 AI 导入单独授权收费调用后验证。
- 根据目标用户补充小米/OPPO/vivo/荣耀/可运行 APK 的华为机型，覆盖不同 Android/API、芯片和低内存设备。仅支持 Android APK 的机型适用；不支持 APK 的 HarmonyOS NEXT 不会因换 OCR/扫码 SDK 获得兼容性。
- 使用同一标注样本比较中文/数字/时间/教室错误、人工修正数、扫码成功率、首用和热用延迟、峰值内存、成品 APK 增量；包含小字密集表格、压缩、倾斜、反光、连续分片二维码。
- 发现可复现的 GMS 依赖/厂商失败、确切体积目标或必须移除 Google SDK 的约束，再考虑对应模块替换。候选尚未同样本 A/B，不宣称更优。
- 用户已提交备案。若决策后更换 SDK，需核对已提交 SDK 信息是否应补正；包名、签名和公钥不随 SDK 替换自动更改。

## 决策建议

1. **当前保留。** 无 GMS/断网运行成功，尚无需要立刻迁移的兼容性证据。保留扫码随包配置，相册 zxing2 路径无需为 GMS 问题更换。完整照片导入仍由 DeepSeek 处理，替换 OCR 不会使这条 AI 链路自动离线。
2. **先补真实无 GMS 手机。** 优先一台目标用户的真实设备，用当前同哈希 release 与标注课表/二维码验收；出问题时先区分模型、相机驱动、权限、照片格式与内存，不把所有问题归为 GMS。
3. **有明确需求再分别替换。** 若出现实际扫码问题或要减少 Google SDK，可先评估 CameraX + ZXing；仅更换扫码仍会保留 OCR 的 Google SDK。PaddleOCR 作为 OCR 备选，先做同样本 A/B，再让用户决定是否承担接入与长期维护成本。本次候选均未接入或实测。

## 可恢复与清理

复核所需源码、模型条目统计、依赖图、结果 JSON、关键日志及两条 UI 成功证据均在本任务目录。任务状态只使用本目录的 PLAN/STATUS；原有其他任务文件未读取为当前状态或覆盖。临时 AVD 和编译中间物在证据保存后清理；官方 AOSP 镜像作为可复用 Android SDK 组件保留。

## Xiaomi 14 真机补充（2026-10-21）

设备为 Xiaomi 14 / 23127PN0CC / houji，Android 16/API36，HyperOS OS3.0.307.0.WNCCNXM，arm64、4 KB 页。GMS、GSF、Play Store 已安装且启用，因此本轮只能验证该真机离线运行，不能作为无 GMS 真机证据。

安装当前 `love.sanqian.schedule` release，手机内 APK 哈希与上述原成品一致；既有 `local.sanqian.schedule` 及其数据保留。安装曾返回 `INSTALL_FAILED_USER_RESTRICTED`，用户开启 USB 安装、恢复 Wi-Fi 后重试成功；不足以确定此前失败的唯一原因。

直接调用原 release 的本地 OCR 方法，两次耗时 371 ms / 112 ms，探针读取的 App activeNetwork 为 null。系统 global mobile_data=0 不代表双卡蜂窝链路全部关闭，初始系统记录仍有蜂窝默认网络；后续二维码阶段显式开启飞行模式并关闭 Wi-Fi，确认 Active default network: none。不能把后续严格断网环境追溯为 OCR 运行时系统环境。

OCR 使用 Android Canvas 生成的合成中文课表图片；返回课程、时间和教室，但将“课程表”识别为“裸程表”、“星期一”识别为“呈期一”、“教师”识别为“教数师”。结论是本地方法执行通过、合成样本质量存在错误；真实密集课表质量尚未验收。手机生成图片与模拟器样本哈希不同，不作公平速度或质量 A/B 比较。完整 OCR 复核→DeepSeek 未运行。

相册二维码：用户报告已出现“导入这份课表？”。随后现场 UI 抓取显示首页课表名为测试样本“无 GMS 离线验证”，确认弹窗已不在屏幕上，因此未现场核对弹窗课程数量。可能已由用户确认导入，未删除任何课表。抓取时飞行模式关闭、Wi-Fi 开启，不能据此认定断网扫码通过。真实相机扫码：用户用手机相机扫描电脑展示的样本后报告确认页出现；现场 UI 核实“导入这份课表？”、“无 GMS 离线验证”、0 条课程，见 `physical-houji/camera-confirmed.xml`。单个合成二维码的真机相机流程通过；未点击导入，未覆盖高密度、连续分片、弱光、反光或运动。弹窗抓取时飞行模式为 0、Wi-Fi 为 0，解码期间未连续监测网络，离线相机结论仍保留未验证。测试课表名称中的“无 GMS”只是样本标题，此手机仍装有 GMS。设备拒绝 ADB 注入点击（INJECT_EVENTS 权限不足），未自动修改安全设置。

证据：[真机 OCR](physical-houji/ocr-result.json)、[真机结果](physical-houji/results.json)、[严格断网记录](physical-houji/offline-network-confirmed.json)。临时 OCR 探针已卸载，正式 App 保留；后续操作与清理状态以真机结果 JSON 为准。

真机收尾：临时 OCR 探针已卸载，手机中的本次二维码测试文件和临时 UI dump 已删除，源码与验收证据保留。上一轮已恢复飞行模式 0、Wi-Fi 1；本轮观察到 Wi-Fi 0，未擅自覆盖后续手机设置。正式新旧 App 及课表均保留，确认弹窗交由用户点取消。
