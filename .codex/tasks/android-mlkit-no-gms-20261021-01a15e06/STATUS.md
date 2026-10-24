# 任务状态

Task-ID: android-mlkit-no-gms-20261021-01a15e06
Owner-Session: 01a15e06-a282-7652-909b-21d95cc33774

状态：本轮验证与方案交付完成；国内真机 NOT_VERIFIED；SDK 迁移未实施，待用户决策
已完成：读取适用 AGENTS.md；确认当前 App 目录与共用 Git 存储边界。
当前：里程碑 1–4 已完成（运行结论限本次 AOSP/合成样本，真机缺口已交付）。
未验证：国内真机/OEM Camera HAL、真实课表与密集分片码质量、真实设备速度/峰值内存、16KB 页运行、联网 SDK 指标行为、付费 DeepSeek 完整导入、替代方案 A/B。
记录：未恢复或覆盖其他任务状态。

里程碑 1 已验证：main/HEAD=0e95b3187d418744613c5c45bb9f3148f72b2893；origin/main=db31944caa515abe7e6f3ff1fdd805c363ebc372；本地领先 3 提交。已跟踪源码干净；原有根 PLAN.md、STATUS.md、备案资料和 .codex 内容均不读取为当前状态、不覆盖。APK SHA256=1c2f3a90a747e7dcc82d55adc103f6f8c86b4c22130b2e2afee3ccd2ecfef42e，58,083,159 bytes。adb 当前无设备；3 个已有 AVD 均 google_apis 镜像。

里程碑 2 已验证：releaseRuntimeClasspath 离线解析成功；中文 OCR 16.0.1 和 barcode-scanning 17.3.0 为随包入口；传递依赖确含 play-services-mlkit 同名客户端，不可据名称认定必须设备 GMS。APK 内可见中文/Latin OCR 模型、barcode 模型和 3 ABI OCR 原生库。mobile_scanner 7.1.3；zxing2 实际锁定 0.2.4；CameraX 1.5.1。

执行决定：安装纯 AOSP API 35 arm64 镜像并创建本次专用 AVD；不改动/卸载已有 GMS。OCR 路径会继续调用收费 DeepSeek，因此仅调用 release APK 内的本地识别方法作为探针，不启动付费链路；探针与 App UI 验证分别报告。

探针准备：仅含反射调用的 instrumentation APK 已编译并验证签名，原 release APK 未改动。首次 QR 生成器因项目 codec 间接依赖 dart:ui 不能在 Dart CLI 运行，改为独立生成符合现有协议的合成载荷，最后由原 App 解码验证。SDK manager 默认未使用环境代理，2 分钟无进展后终止本次进程，按现有 Gradle 的本机代理重新下载；仍为官方同源 CLI。

关键基线变化：只读 git ls-remote origin refs/heads/main 返回 0e95b3187d418744613c5c45bb9f3148f72b2893。实际远端现已与本地一致；本机 origin/main=db31944 是过时跟踪引用。报告已更新，本次未推送/重置。

静态补充：实际 APK 的 arm64 libbarhopper_v3.so 与 libmlkit_google_ocr_pipeline.so LOAD 段均为 0x4000 对齐；仅静态条件，未升级为 16KB 设备运行 PASS。纯 AOSP 镜像仍由 sdkmanager 下载。

环境里程碑：纯 AOSP API 35 default/arm64-v8a r2 镜像安装成功（系统镜像官方大小 769099654 bytes）。avdmanager 首次按 Homebrew 根目录找 SDK 失败，进程级 AVDMANAGER_OPTS 指向实际 SDK 后成功创建专用 sanqian_nogms_01a15e06，端口 5580。已有 AVD 未修改。摄像头将直接输入合成二维码 PNG。

运行里程碑（本地 OCR）：新装原 release APK 与同签名小型 instrumentation；纯 AOSP Android 15/API35 arm64，包列表包含卸载记录仍无 gms/vending/gsf，飞行模式且 activeNetwork=null。直接反射调用 release 的 MlKitChineseTimetableOcr.recognize 成功，合成 1600x900 中文文本 JPEG，两次耗时 105/40ms，课程名/时间/教室识别到，但教学楼前多出竖线字符。证据 ocr-result.json / ocr-instrumentation.txt。仅证明原 release 本地方法，不是 OCR UI→DeepSeek 付费链路/真实课表质量。

运行里程碑（相册）：原 release UI 经系统 Photo Picker 选择合成 QR 成功，出现正确“无 GMS 离线验证”导入确认页；未确认写入。证据 gallery-result.xml/png。
摄像头第一轮：日志已选择本地 barcode Dynamite 模块，无 GMS 下载；CameraX 因专用 AVD 缺前摄重试，随后后摄打开。注入图被放大裁切，画面缺 QR 定位角，尚未扫码成功。仅调整专用模拟器前摄及合成输入留白，不改产品源码。

运行里程碑（摄像头）：调整专用模拟器前摄及输入图位置后，原 release App 通过真实 CameraX 帧回调→ML Kit→Dart onDetect→协议解析进入同名导入确认页。日志 Selected local version of com.google.mlkit.dynamite.barcode。没有点击导入或写课表。模拟器摄像头输入为合成 PNG，不能代表真实光学/对焦或 OEM 驱动。最终设备仍无 GMS/GSF/Play Store、飞行模式、无活动网络；设备安装 APK 的 sha256 与原成品一致。证据已写 results.json。

交付里程碑：REPORT.md 已包含基线、官方资料、三路径证据矩阵、失败记录、方案比较、保留建议及真机缺口。results.json 为结构化汇总。专用 AVD 与同签名探针 APK/编译中间物已删除；仅保留官方 AOSP SDK 镜像供复用、证据和复现实验源码。最终 git tracked/staged diff 均空，HEAD 和 APK hash 与开始一致；原有状态文件及备案资料未改动。

2026-10-21 真机续验：用户已连接手机，恢复本任务。先核对设备/GMS/现有 APK，再执行安全本地探针及相册、摄像头验收；保留用户数据，不卸载或禁用 GMS，不消费付费 API。

真机基线：Xiaomi 14 / 23127PN0CC / Android16 API36 / HyperOS OS3.0.307.0.WNCCNXM / arm64 / 4KB 页。GMS、Play 商店、GSF 均存在且启用；因此只能验该机离线能力，不能补齐无 GMS 真机。设备有旧 local.sanqian.schedule，无当前 love.sanqian.schedule；并行安装当前版，不覆盖旧版。Wi-Fi=1、mobile_data=0、airplane=0；仅临时关闭 Wi-Fi并收尾恢复。

真机执行受阻：adb install 当前 release 返回 INSTALL_FAILED_USER_RESTRICTED: Install canceled by user；尚未安装成功或运行 OCR。已将 Wi-Fi 恢复开启，旧包依然存在。需用户在手机允许 USB 安装/安装确认后继续。此为设备安装策略拒绝，不是 Codex 自动审批拒绝。

用户已开启 USB 安装，继续同一真机验证；保留已有旧包和数据。

小米真机安装完成，当前 APK hash 与基线完全一致，旧包保留。临时探针运行成功，应用内 activeNetwork=null；合成图本地 OCR 两次 371/112ms，读到课程名/时间/A101，存在“课程表→裸程表”“星期一→呈期一”“教师→教数师”等误字，不能记质量 PASS。双卡 global mobile_data=0 未可靠代表无网络，随后显式开启临时飞行模式用于 UI 验证，收尾恢复飞行模式0/Wi-Fi1。GMS 仍存在并启用。
