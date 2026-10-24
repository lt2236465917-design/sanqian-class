# 独立代码与依赖复核（第一轮）

审查范围：本次 Android 识别引擎替换源码、Flutter Android 生命周期分支、本地 mobile_scanner fork、release APK/manifest/mapping/模型与许可证。只写本报告；未操作 emulator-5582，未读写其他任务状态。结论不等于实际相机或真实课表质量通过。

审查快照：HEAD 0e95b3187d418744613c5c45bb9f3148f72b2893；工作区改动仍在迭代。读取 APK SHA-256 `9e2635cb9167fa5fc90365dac0cf8e8ee5d9df5bad6d1186f6871178a3e56c62`，73,829,977 bytes。主代理之后的新构建须重做成品核对。

## 退回整改

### P1 — 相机启动未完成时退出扫码页不会取消 pending start

位置：`lib/Pages/Share/QRScanView.dart:77`；`packages/mobile_scanner/lib/src/mobile_scanner_controller.dart:583`；`packages/mobile_scanner/lib/src/method_channel/mobile_scanner_method_channel.dart:394`、442；`packages/mobile_scanner/android/src/main/kotlin/dev/steenbakker/mobile_scanner/MobileScanner.kt:313`。

可确定的执行序列：已有相机权限 → 开启相机 → 原生 ProcessCameraProvider future 尚未完成 → 用户立即返回上一页 → QRScanView.dispose 调 controller.dispose → platform.dispose 调 stop()，因 `_textureId == null` 直接返回，不向 Android 发送停止 → future 完成后 `scanGeneration` 没变化，仍绑定 Activity 并启动相机。Activity 属于整个 Flutter App，离开扫码 route 不会销毁它，因此会在扫码页面已关闭后仍持有相机。这个问题源自上游停机契约，当前 fork 的 generation 尚未覆盖此路径，用户指定的取消验收不能因此通过。

建议：Android route 退出时明确取消 pending start；不要只检查已经获得 texture 的 running 状态。原生 stop 也应将 pending scanner/start 纳入判断，保证 generation 失效并回复未完成 start。添加延迟 provider 回调的竞态回归，随后实际 release 快速开启/返回及再次进入扫码。

证据级别：源码可确定的 interleaving；未执行设备复现。

### P2 — 排队旧帧可能在新一次 start 下被接受

位置：`packages/mobile_scanner/android/src/main/kotlin/dev/steenbakker/mobile_scanner/MobileScanner.kt:105`、376、540。

分析器是单个共享 `captureOutput`，在帧任务真正开始时才读取全局 `scanGeneration`。stop 使用 executor.shutdown（不会清除已排队任务），再 start 使用新 executor。如果旧 use case 的任务在新 start 后才被调度，它读到的是新 generation 和新 scanner；其后两次 generation 检查都相等，旧画面识别结果可发给新扫码会话。当前 generation 只拦截“已经开始解码后被 stop”的帧，不能拦截“尚未执行的旧任务”。

建议：setAnalyzer 时捕获该 start 的 ticket，在 decode 前/后及主线程发布时均验证绑定 ticket；旧帧始终 close。用阻塞旧 executor → stop/start → 释放旧队列的回归证明旧 QR 不再发出。

证据级别：源码可确定的 interleaving；未执行设备复现。

### P2 — ONNX Runtime 第三方声明未随包

位置：`android/app/src/main/assets/ocr/licenses/`。当前只有 Microsoft 主 MIT 许可证；官方 `https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.2/ThirdPartyNotices.txt` 另有 Eigen/MPL2、flatbuffers、SafeInt 等声明。独立检查 AAR 不含 notices；APK Flutter NOTICES.Z 无 Eigen/SafeInt/ONNX 文本。仅含主许可不足以支撑已经覆盖全部二进制分发声明的结论。

建议：附上该版本官方 ThirdPartyNotices.txt 并保留来源。若裁剪声明，必须有实际构建依赖证据，不凭主许可证推断。此处不是禁止商业使用的结论。

## 已独立确认

- `packages/mobile_scanner/lib/` 和 `darwin/` 对比本机上游 mobile_scanner 7.1.3 对应文件，所有文件字节一致；`git diff -- ios` 为空。Android observer 不注册到 iOS。未运行 iOS 构建，运行行为仍 NOT_VERIFIED。
- APK DEX 无 `Lcom/google/mlkit/`、`Lcom/google/android/gms/`、`Lcom/google/android/libraries/barhopper/`；R8 mapping 中对应源类记录为 0；APK 路径无 MLKit/barhopper/Play Services native/model。release dependency 报告无 com.google.mlkit/com.google.android.gms/play-services。
- 全部 release ELF（arm64-v8a、armeabi-v7a、x86_64）LOAD 对齐 >=16KB；zipalign -c -P 16 4 与 apksigner verify 成功。该结论是静态兼容性证据，不等于 16KB 设备运行通过。
- 实际 APK 内 det/rec 模型、字典哈希与随包 manifest 匹配；模型总量 15,603,475 bytes。来源为版本固定 RapidAI ModelScope 路径；项目研究 model card 声明 Apache 2.0。主许可证已随包。
- OCR 无网络代码，模型从 APK 解包到 noBackupFilesDir 并校验哈希；识别 session、input/output tensor、bitmap 关闭路径可追踪；RunOptions watchdog 在关闭前取消并 join；共享张量缓冲由可取消锁保护。原图 JPEG 和 OcrGeometry/64,000-byte 下游验证保护保留。

## 必须准确披露的边界

合并 manifest 仍有禁用的 `com.google.android.gms.metadata.ModuleDependencies` 服务和 `photopicker_activity:0:required` metadata。manifest merger report 指向 `image_picker_android`，不是本次已移除 ML Kit 的传递 SDK；没有对应 GMS 类打进 APK。其作用是请求有 Play 服务的设备安装后向兼容 Photo Picker。可以说 ML Kit 及其 Play Services SDK 已移除，不能说 manifest 完全没有 GMS 名称。删除该标记属于是否保留系统 picker backport 的明确产品选择，应由主代理据范围决定。

本轮不以源码、测试绿或主代理合成报告替代真实样本与真实扫码效果；尚需整改后复审及主代理运行证据。

## 第二轮整改复验

已重新读取实现并独立运行 `flutter test test/Pages/Share/android_scanner_lifecycle_test.dart --reporter expanded`。

- P1：Android stop/dispose 现在始终 force:true；permission 和 native start 的 await 后均验证 generation；native pending provider 被 stop 失效后回复错误。两项受控延迟回归通过，源码层该项修复成立。该结论不自动代表真机快速退出已跑过。
- 许可证项：新增 `onnx-ThirdPartyNotices.txt` 与官方 v1.23.2 字节一致，SHA-256 `e9e90971a8e75a9a8ac0c6412e29c1202d079998389915aa485f46c816c3b4cc`；新 APK 内存在 326,866 bytes 文件。此项关闭。
- P2 尚未关闭：setAnalyzer 外层虽捕获 bound ticket，但在比较后调用 captureOutput，后者重新把全局 scanGeneration 赋给 ticket；main stop/start 可在该检查与读取之间插入。应把 bound ticket 直接传给解码函数并用于所有阶段。另解码主线程回调检查 ticket 后，BarcodeHandler.publishEvent 又排一次主线程任务；stop/start 可插在两次 post 之间。建议 main thread 上直接 eventSink.success，dispose 清空 sink，使最后一次 generation 检查与实际发出事件在同一主线程任务内完成。
- 第一轮“lib 全部字节未变”不再适用于当前整改快照：唯一预期变化是 method-channel 文件中的 Android 条件分支；darwin 仍应保持一致。需交付时重验 iOS 非 Android 路径。

## 第三轮整改复验

再次独立读取 Android analyzeFrame / setAnalyzer / BarcodeHandler 的实际文件，未依据主代理描述直接关闭问题。

- P2 旧扫码数据项关闭（源码层）：`setAnalyzer` 捕获本次 start ticket，交给 `analyzeFrame(frame, ticket)`；后者不重新生成 ticket，解码后及最终主线程发送前均校验同一个 ticket。即使 stop/start 插在外层检查和函数入口之间，旧 ticket 仍会在解码后失败；旧帧在所有返回路径由 finally close。
- `BarcodeHandler.publishEvent` 已在 main thread 同步调用 sink，最后一次 generation 检查和成功事件发出之间不再有第二次 Handler 排队；dispose 清空 sink。先前报告的旧 QR 投递窗口已闭合。
- P1 的第二轮结论保持：Android-only generation + force stop 路径和两项受控延迟回归已通过。本轮未新增运行这些回归，因为对应 Dart 修复未再改动。
- `darwin/` 与 upstream 7.1.3 仍字节一致；`lib/` 唯一差异为 Android-only generation/stop/dispose 修改所在的 method-channel 文件。git diff --check 无错误。

本轮结论：已报告的 P1、P2 旧数据和第三方声明缺口均已按上述证据关闭；本轮未发现新的足以阻止当前源码交付的确定性缺陷。没有操作模拟器，没有声称真实课表或真机验收通过。最终构建 artifact 的哈希/依赖/成品检查由成品证据 reviewer 对固定包执行，本报告的第一轮 APK 哈希不能沿用为最终包结论。

第三轮所审查文件 SHA-256：
- `packages/mobile_scanner/android/src/main/kotlin/dev/steenbakker/mobile_scanner/MobileScanner.kt`: `83c6a6088b7c0f6c98ecd4acb87a9fd7fd22c245ce60436ffc65e5cd8fee667e`
- `packages/mobile_scanner/android/src/main/kotlin/dev/steenbakker/mobile_scanner/BarcodeHandler.kt`: `d81ff124bb40eadcaf335fd1b0bf2558578c11e243bcf577fd9173816d929d3b`
- `packages/mobile_scanner/lib/src/method_channel/mobile_scanner_method_channel.dart`: `dfdc741031031106f37abf1100e9d63831820ff15dc129b95463d33dd86f6915`

## 第四轮增量复核：权限恢复与 OCR 缓冲复用

独立读取 QRScanView、MobileScannerController/State、Android settings method handler 和 PaddleChineseTimetableOcr；未操作模拟器，未读写 PLAN/STATUS。

- 权限恢复主路径：拒绝权限后 controller 保存 permissionDenied，hasCameraPermission 为 false；普通 resumed 在未显式进入设置时返回，启动中的生命周期回调也跳过。用户点击设置后允许一次恢复启动，标志在 start 前清除。因此源码支持“普通权限拒绝不自动再次弹框”的目标；本轮没有以此替代实际交互验证。之前两项 method-channel 回归覆盖 pending permission/native start 的退出取消，不覆盖本轮权限 UI。
- P3 返回值遗漏：MainActivity 的 openAppSettings 在 startActivity 异常时返回 false，而 QRScanView 只在调用抛异常时清除 `_returningFromSettings`。这会使设置未打开时的标志保留到下一次普通 resumed，并允许一次原本应跳过的 start。建议检查 bool 返回值，非 true 时清标志并展示已有提示；属于确定的失败分支遗漏，尚未复现设备上设置启动失败。
- OCR 容量：检测输入两边按 32 对齐且最大 960；识别输入为 height=48、width<=2048。逐行像素缓冲 2048 足够；直接 float 缓冲可容纳 960×960×3，识别最多 2048×48×3。absolute put 的通道索引仍为 c×size+row×width+column，位置保持 0、limit 为 size×3；没有因逐行读取而改变 BGR/CHW 布局。
- visited/queue 复用：依赖当前固定且校验哈希的检测模型输出不超过 960×960；每轮仅清有效 visited 区域，所有入队节点在入队时标记，同一连通域最多 h×w 个元素，旧 queue 内容由 head/tail 排除。recognize 的静态锁覆盖整段识别，input/result 在下次 tensor 覆写前关闭，因此未发现新的缓冲竞争或容量缺陷。若将来替换模型，需要重新确认输出形状契约。
- 资源与取消：等待锁可取消；watchdog 终止 ORT run，并在 RunOptions 关闭前 join；输入/结果/session/bitmap 的已有清理仍保留。张量预处理和单个连通域 BFS 内部没有新增取消检查，扩大至 960 后的实际取消延迟与峰值内存必须重新实测，不能从“复用缓冲”推导性能 PASS。共享 scratch 为进程期保留内存，也不能表述成 OCR 退出后全部内存释放。

本轮 git diff --check 通过。除上述低优先级设置失败分支外，当前增量未发现新的确定性资源释放或边界缺陷；真实课表质量、最新 release 资源/取消延迟及模拟器权限交互继续由实际验收证据判定。

第四轮审查快照 SHA-256：
- `lib/Pages/Share/QRScanView.dart`: `7f8f47eaab65b264ef67f64ff11d7e3e8445e8dbab28ceb96e94e378f7cbbec2`
- `android/app/src/main/kotlin/love/sanqian/schedule/PaddleChineseTimetableOcr.kt`: `19be44341c6008153204be3c8dc2be8744ebc0692de6fedd8718b6f2441da392`

### 第四轮修复复验

已重新读取 settings 回调：保存 opened 返回值；opened != true（含 false/null）时清除 `_returningFromSettings` 并在 mounted 时展示现有错误提示；抛异常分支同样清除标志。上述 P3 在源码层关闭，当前已报告问题均已完成源码整改；未把该检查声明为系统设置启动失败的设备复现。最新 QRScanView SHA-256 为 `dbd9b36bcca4e86df9592fafb64b5870f3eb531947495d6dc7a995c59b395012`；git diff --check 仍通过。第四轮 OCR 容量、资源和实际验收边界结论保持。
