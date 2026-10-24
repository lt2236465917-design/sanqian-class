# Android 本地识别引擎替换交付

日期：2026-10-22。结论：源码替换和指定 AOSP 模拟器验收完成；真实课表质量、真机运行仍未验证。工作区保留可审查改动，未提交、push 或发布。

## 成品

- 最终 APK：[sanqian-android-local-engines.apk](release/sanqian-android-local-engines.apk)
- SHA256：`00cb1775d79a21bd24cb08a6d5398be4358f37e542067f5bcf3f761da59d3428`
- 大小：73,871,033 bytes；旧包 58,083,159 bytes，增加 15,787,874 bytes（15.06 MiB，27.18%）。旧包保存在 baseline/app-release.apk，原申报产物未覆盖。
- 包名 love.sanqian.schedule，版本 1.0.0(1)；新旧签名证书 SHA256 一致：`0bf510279f816cf61685be14a24dd09547577b9bd14406f6927a208cd8fc688a`。

## 变更及实际验证

Android 相机保留 CameraX，解码替换为 ZXing-C++ 3.0.2；相册仍用 image_picker / image / Dart zxing2。中文 OCR 改为随包 PP-OCRv4 ONNX 模型与 ONNX Runtime 1.23.2，模型从 assets 校验后加载，不下载模型。原有原图权威、用户选择 OCR 复核、取消和下游校验保留。

实际最终 APK 的 DEX、模型、native 和 release 依赖检查未发现 ML Kit 或其 Play Services SDK。manifest 仍有 image_picker 的 disabled Photo Picker backport 元数据名称，非打入 GMS SDK；不声称移除全部 Google 维护的组件。三 ABI 的 24 个 ELF LOAD 对齐及 zipalign 16 KB 检查通过，尚未在 16 KB 页设备运行。

| 最终包验收项 | 实际结果与证据 |
|---|---|
| 无 GMS AOSP API35 arm64 离线本地 OCR | final-cold 原始输出内记录安装 APK 哈希、GMS/GSF/Play Store 不存在、activeNetwork 前后为 null、模型缓存开始为空；本地推理执行成功 |
| 空白图、坏图、预取消、运行中取消 | 空白图 0 token；InvalidImage；Cancelled；运行中取消 30 ms 返回，见 benchmark/final-cold.txt |
| 权限拒绝及恢复 | 拒绝后停在可恢复错误页，不重复弹权限；从系统设置授权返回自动恢复，进入三课程确认页，见 delivery-denied / delivery-permission-return |
| 模拟相机完整导入 | CameraX 读取模拟器 imagefile 相机的合成三课程 QR；确认后数据库字段逐项匹配，见 delivery-db / delivery-qr-results.json |
| 三分片、重复帧及前后台 | 1/3 后持续同帧未重复累计；背景/恢复更换帧至 2/3、3/3，出现正确三课程确认页；取消未新增由操作顺序及相册完成后的课表/课程数量支持；未单独采集取消后的即时数据库快照 |
| 相册完整导入 | 无 GMS 系统照片选择器选择合成 QR，确认导入后新增准确的三课程课表；delivery-gallery-db 与全部标准字段比较通过 |
| 相机释放 | 完成/取消离开扫码后，delivery-camera-closed.txt 的 Active Camera Clients 为空 |
| 相关自动化检查 | 42 项 Flutter 测试通过；针对变更的 analyze 无问题；git diff --check 通过 |

模拟相机的图片输入不等于实体摄像头拍摄。二维码样本和 OCR 图片全部为明确标注的合成数据；数据库逐字段比对证明这一组完整导入，不能替代用户真实课表验收。运行中通过测试探针直接调用实际 release 的本地 OCR 方法，没有把探针或 mock 打入成品，也没有调用付费 DeepSeek API。

## 同图新旧对比

4 张合成图包括普通文字、网格、小字及 7° 旋转，输入图片哈希新旧相同。按标准字段区域分配 token、去空白后计算严格文本编辑和位置 IoU；不是全文 contains 匹配。

| 指标 | 旧 ML Kit | 最终包 |
|---|---:|---:|
| 严格字段匹配 | 46/51 | 51/51 |
| 字符错误 | 5/311 | 0/311 |
| 含阿拉伯数字字段匹配 | 21/23 | 23/23 |
| 星期字段匹配 | 8/8 | 8/8 |
| 位置框 IoU ≥ 0.5 | 51/51 | 51/51 |
| 四图耗时 ms | 85 / 64 / 63 / 69 | 710 / 694 / 689 / 714 |
| 采样 PSS 增量 | 103.31 MiB | 147.14 MiB |

新包首张包含无提取缓存时的模型复制、校验、session 初始化和推理；旧引擎是已运行后的方法测量，不是严格同等首次安装冷启动对比。新引擎明显更慢。20 ms 采样可能漏掉瞬态峰值，最终峰值 161,374 KiB、初始 10,699 KiB，增量离预设 150 MiB 上限只余 2.86 MiB，不能推断真机稳定通过。51/51 只适用于此组合成样本；字段不等数只是修正量代理，不是实际人工操作次数。

此前 896 检测边长出现“星期一→星期—”，已退回 960 并优化缓冲复用，最终同图复测及独立重算均消除该样本错误。历史原始输出保留，不用最终结果改写历史失败。

## 独立交叉验证与整改

- [代码复核](review-code.md)：发现并关闭 pending start 退出仍启动、旧会话帧投递竞态、ONNX 第三方声明缺失，以及打开设置返回 false 未清标志。复查最终增量未发现新增确定性阻断缺陷。
- [产物与证据复核](review-evidence.md)：独立读取最终 APK 和原始结果，复核哈希/签名/24 个 ELF/SDK 去除/模型和 notices；独立重算 51/51；另对最终二维码 UI、两份 SQLite 和标准答案逐字段复核，相机 3 课程、相册再增 3 课程，原数据未变。首次缓存、框与 confidence、空图/预取消、统计口径缺口已补证。
- 独立审查不把源码、测试绿、合成数据或模拟器效果升级为真实课表/真机 PASS。

## 未验证与待同步

真实课表与真实拍摄二维码、Xiaomi14 及国产无 GMS 真机、人工修正量、严格首装新旧性能对比、16 KB 页设备运行、armeabi-v7a/x86_64 运行、iOS 构建/运行均 NOT_VERIFIED。iOS 源码无 diff，darwin 与上游字节一致，Dart 变更行为限定 Android；这只是静态保护证据。

完整 DeepSeek 网络导入未执行，本轮无付费调用。SDK/隐私披露的本地变更说明见 android/LOCAL_RECOGNITION_NOTICES.md；备案、软著、网站披露和商店均未代改。

保留最终及旧 APK、映射、标准样本、原始结果、数据库快照和独立审查供复验。任务专属临时模拟器与探针已清理；真实手机数据未改。
