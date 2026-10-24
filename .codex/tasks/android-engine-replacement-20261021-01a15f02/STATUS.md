Task-ID: android-engine-replacement-20261021-01a15f02
Owner-Session: 01a15f02-b020-75e0-aa1a-e03790568c22

状态：执行中，里程碑1。
已验证：两处 AGENTS 已读；HEAD 0e95b3187d418744613c5c45bb9f3148f72b2893；tracked diff 为空；已有 untracked .codex/、根 PLAN.md、STATUS.md、备案资料/2026-10-21/。
设备：adb devices 空；没有网络基线可读。已向用户索取指定真实样本路径和设备连接。
尚未执行：源码修改、候选比较、构建、运行、独立复核。

里程碑1：旧 APK 已独立备份并匹配哈希。用户无真实素材/设备，明确允许先用模拟器验收。已创建专属纯 AOSP API35 arm64 AVD emulator-5582，候选 ORT 1.23.2 / ZXing-C++ 3.0.2 四 ABI ELF 16KB 对齐通过，PaddleOCRv4 det/rec 发布哈希匹配。采用 ONNX 路线是为覆盖既有 x86_64 ABI 并可核验16KB；识别质量未验证，不宣称更优。当前新增候选类与模型，尚未切换旧 OCR 入口。

候选首轮 release 94.1MB 可构建，但实际调用崩溃：ONNX JNI convertToTensorInfo 找不到 R8 重命名类。添加 ai.onnxruntime 全部 JNI 反射保留后复验；失败未判通过。旧引擎同图在新 AOSP 环境 117/42ms，存在 |教学楼 多余竖线。

里程碑2：Android OCR 入口已切换 PP-OCRv4+ORT；mobile_scanner 为本地 Android fork，保留原 Dart/darwin 内容（应用 QRScanView 仅 Android 生命周期修复）。移除 MLKit 初始化/manifest规则/Gradle依赖。release 73.8MB；Gradle release单测和40项相关Flutter测试通过。候选四组合成样本51/51字段包含匹配（旧49/51），框范围合法；这是合成质量，不是真实样本PASS。原方案四图循环进程PSS峰值235237KB，相对初始10171KB超150MiB门槛，退回优化：模型文件加载+复用图像张量缓冲；待复测。旧基线峰值118695KB。权限拒绝恢复发现不自动启动，补Android observer，待新包实测。

实际新包CameraX+ZXing-C++：3课程单码进入正确确认；相册单码确认并导入；相机3分片经Home/前台切换连续接收2/3后正确3课程确认，取消可返回。独立review发现pending-start取消与旧帧generation竞态，已修复并有两项Dart延迟回调回归PASS。ORT ThirdPartyNotices已补随包。最终固定包复验待完成。

复核闭环：review-code 第三轮关闭P1启动取消/P2旧帧竞态与许可证缺口。最终冷测发现960边长内存峰值增量154.7MiB略超门槛，改896待同样本复测；权限拒绝首次导致resumed重弹，现加入仅主动Settings返回才重查未授权状态，待最终包UI验证。所有旧失败记录保留，未升级PASS。
