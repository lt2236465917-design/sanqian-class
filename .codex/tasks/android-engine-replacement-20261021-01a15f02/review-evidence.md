# 独立产物与证据审查

最终交付包以文末「第四轮」为准（SHA256 00cb1775…9d3428）。前三轮候选、发现与整改记录保留供追溯，不作为最终包结果。

Reviewer: /root/review_engine_evidence
Task-ID: android-engine-replacement-20261021-01a15f02
审查范围：只读当前 release APK、R8 mapping、合并 manifest、依赖输出、原始 benchmark、模型与许可证、iOS/plugin 源码；未操作 emulator-5582，未更改产品文件。此报告不是运行质量总体验收 PASS。主代理后续改变 APK 后需要复验。

## 已独立验证

- 本轮 APK：`build/app/outputs/flutter-apk/app-release.apk`，73,829,977 bytes，SHA256 `9e2635cb9167fa5fc90365dac0cf8e8ee5d9df5bad6d1186f6871178a3e56c62`。旧包备份 58,083,159 bytes，SHA256 `1c2f3a90a747e7dcc82d55adc103f6f8c86b4c22130b2e2afee3ccd2ecfef42e`。增加 15,746,818 bytes（约 15.02 MiB）。
- 实际 APK package `love.sanqian.schedule`，versionName `1.0.0`，versionCode `1`。新旧 `apksigner verify --print-certs` 的 signer certificate SHA256 均为 `0bf510279f816cf61685be14a24dd09547577b9bd14406f6927a208cd8fc688a`，签名校验成功。
- APK 所有 DEX 搜索 `com/google/mlkit`、`com/google/android/gms`、点分名称与 `barhopper` 均未命中；R8 mapping 和本次 release runtime dependency 输出也未命中 ML Kit / Play Services。模型、原生库名单没有原 ML Kit/Barhopper。
- 三种 release ABI（arm64-v8a、armeabi-v7a、x86_64）均完整包含 ONNX Runtime、ORT JNI、ZXing-C++。全部 24 个 ELF 的每个 LOAD 段 `p_align >= 16384`，且 `p_offset % 16384 == p_vaddr % 16384`。`zipalign -c -P 16 -v 4` 成功。库均为压缩 ZIP 条目且应用启用 extractNativeLibs；这里确认静态对齐，不等于 16 KB 页设备运行通过。
- 合并 manifest 保留 `com.google.android.gms.metadata.ModuleDependencies`，`enabled=false`、`exported=false`。manifest-merger-release-report.txt 第 517 行起追溯为 `image_picker_android` 的 Photo Picker backport 元数据，非 ML Kit 引入的 SDK；成品无对应 GMS DEX 类。不能宣称 manifest 完全无 Google 字符串，也不应因此删除现有相册行为。
- APK 中 det 模型 4,745,517 bytes / SHA256 `d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9`，rec 模型 10,857,958 bytes / SHA256 `48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b`，与 assets manifest 和下载发布清单一致。模型来源是 RapidAI 的 PaddleOCRv4 ONNX 转换，不能称作 Paddle 官方原生 Android runtime。
- 已见 RapidOCR/PaddleOCR/ZXing Apache-2.0 与 ONNX Runtime MIT 主许可证；mobile_scanner 的 BSD-3-Clause 已出现在 Flutter `NOTICES.Z`。
- `git diff -- ios` 为空；本地 fork 与 pub-cache 原 7.1.3 的 `lib/` 53 个文件和 `darwin/` 8 个文件逐一哈希完全一致。这证明 Apple Vision/plugin 源未改，不是 iOS 编译/真机回归通过。
- old.json 与 shared.json 四张输入 SHA256 一一相同。shared 原始耗时为 746/920/725/958 ms；初始 PSS 10,362 KiB、采样峰值 153,948 KiB，差值 140.22 MiB。20 ms 采样是观测峰值，不保证抓住更短瞬态峰值。

## 需要整改/补证

### [P2] 字段包含匹配不能替代精确率和人工修正量

定位：`benchmark/LocalOcrProbe.template.java:58` 使用拼接后的全文 `observed.contains(gold)`。例如旧引擎输出 `|教学楼A101`，仍算该字段 exact，extra 字符不会扣分；正文顺序变化也使 `orderedCharacterEdits` 混入阅读顺序差异。当前 51/51 和 49/51 只能叫“期望字段包含匹配”，不能用作 >=95% 字符准确率、>=99% 数字字段准确率或人工修正量门槛的证明。

独立依据 Canvas 布局和 token 框中心做前三张空间归组后，旧严格匹配为 33/36，新为 36/36。旧错项是 `|教学楼A101`、`|第1-16周`、`课程各称`。建议固定每个 gold 字段区域，按区域配对计算插入/删除/替换及数字/时间/教室 exact；旋转图 gold 框使用同一旋转矩阵变换。不要用全文阅读顺序作为唯一 OCR 字符误差。

### [P2] 位置框与 confidence 合同证据不完整

定位：同一 probe 第 50–56 行初始化 valid=true；缺 box 时仍可能保持 true；第 55 行仅检查范围，没有匹配实际文字区域，不证明定位正确率 >=95%。confidence 未输出未验证。需每 token 强制存在 box，4 数值 finite 且合法；confidence 应是 null 或 finite [0,1]；用 gold 区域测定位。现有实际输出的 51 个 token 都有合法范围框，但该事实不补齐定位门槛。

### [P2] 首次离线使用与产物绑定仍需补证

`benchmark/shared.txt` 没有 APK hash 或安装证书标识，靠构建/安装顺序关联。此前 optimized 运行已创建 noBackupFilesDir/ocr-v4 缓存，因此 shared 首轮不能直接叫首次安装冷用。需在本任务专属模拟器的新安装/已清测试模型缓存状态下，固定 APK hash，验证首次离线复制模型、推理、空图/坏图/取消以及随后重复运行。不可清真实用户数据。

### [P2] ONNX Runtime 二进制第三方 notices

当前 APK 和下载的 onnx.aar 均未发现 ONNX Runtime `ThirdPartyNotices.txt`，仅有 Microsoft MIT 主许可证。上游 `https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.2/ThirdPartyNotices.txt` 可读，包含第三方版权和再分发条件。需核对并保留相关 notices（可完整附入同版本 notices，以避免遗漏）；不能据主许可证就宣称商业分发手续完整。

## 不得升级的边界

- 四张都是 Canvas 合成数据，含网格/小字/7° 旋转；没有真实课表图片和人工修正标注，真实课程质量 NOT_VERIFIED。
- 本报告只复核现存运行原始记录，没有重新执行 OCR；新模型 API 全流程仍经过同一 DeepSeek 调用而本次禁止付费请求，因此“本地方法执行”不能说成完整 AI 导入网络链路已验收。
- 没有国产无 GMS 真机、实际 16 KB 页设备或 x86_64/armeabi-v7a 运行证据。
- 网络记录是 begin/end activeNetwork=null；独立审查不把两个快照描述为持续网络抓包。代码为 assets/file/ORT CPU、无 OCR 下载/云调用，可结合专属 AOSP 模拟器网络配置说明离线环境。
- 主代理正在补相机三课程/多分片、相册、拒绝权限恢复、前后台及取消。第一轮存在的基础0课程确认截图不可独自证明完整导入通过。


## 第二轮：固定最终包复验

复验对象：`release/sanqian-android-local-engines.apk`，SHA256 `534ffc8e500b568754a57a58fd08454c10bb488be92a0cf63bab75603a73ef02`，73,869,009 bytes。直接重新读取二进制核算，不只引用 audit.json。相比旧包增加 15,785,850 bytes（约 15.05 MiB）。

### 产物静态结论

- 无 ML Kit / GMS / Barhopper DEX 字符串；三 ABI 共 24 个 ELF 的每个 LOAD 段对齐及 offset/vaddr 同余继续通过，zipalign 和签名验证继续成功，证书 SHA256 与旧包相同。
- 模型实际 APK 字节哈希仍与固定发布模型一致。
- `assets/ocr/licenses/onnx-ThirdPartyNotices.txt` 已加入 APK，326,866 bytes，SHA256 `e9e90971a8e75a9a8ac0c6412e29c1202d079998389915aa485f46c816c3b4cc`。独立重新请求 ONNX Runtime v1.23.2 上游文件所得 SHA256 一致。第一轮 notices 缺口已整改。
- iOS `darwin/` 继续未变；Dart 已不再全部 byte-identical：`lib/src/method_channel/mobile_scanner_method_channel.dart` 增加 generation/stop/dispose 保护，实质行为均限定 `defaultTargetPlatform == TargetPlatform.android`。不得沿用第一轮“全部 Dart 字节未改”陈述；iOS 原生及非 Android 分支静态未误伤，未执行 iOS 构建。
- 合并 manifest 的 image_picker disabled Photo Picker metadata 解释保持不变，非 ML Kit SDK 残留。

### 质量指标独立重算

读取 `benchmark/old-contract.json` 和 `benchmark/final-cold.json`，自行按 gold 区域分配 token、按 x 归并文字、算 Levenshtein 与 IoU；未执行主代理 score.py（避免覆盖其文件）。全部 4 张输入哈希新旧一致。

| 指标 | 旧 ML Kit | 新固定包 |
|---|---:|---:|
| 严格字段匹配 | 46/51 | 50/51 |
| 空白归一化后的字符编辑错误 | 5/311 | 1/311 |
| 字符准确率 | 98.3923% | 99.6785% |
| 含阿拉伯数字的字段严格匹配 | 21/23 | 23/23 |
| 含星期字样的字段严格匹配 | 8/8 | 7/8 |
| gold/pred union box IoU >=0.5 | 51/51 | 51/51 |
| 四图耗时 ms | 85/64/63/69 | 657/635/692/655 |
| 采样 PSS 增量 MiB | 103.31 | 124.37 |

第一轮 contains 统计和坐标范围缺口已经通过空间归组严格指标整改；最终 51 个新 token 均存在框，置信度均为 finite [0,1]，实际框符合范围约束。goldBoxes 由 Canvas 的 measureText/ascent/descent 生成，旋转图使用同一个 7° 矩阵并平移 bitmap 旋转外接框，足以支持这组合成定位比较。

唯一新错项是旋转图 `星期一` 被识别成 `星期—`。这是真实测出的日期字段识别错误，不能用“含阿拉伯数字字段 23/23”掩盖或称所有数字/时间语义都准确；建议在交付对比中明确列出。该组合成样本整体字符指标提高，但星期字段比旧版退步，需要真实样本验证，不能声明新引擎普遍更优。表内“需修正字段”仅为严格不等字段的代理量，不是实际用户操作次数。

### 首次离线证据复验

`final-cold.txt/json` 内由已安装 APK 的 `ApplicationInfo.sourceDir` 直接计算 SHA256，与固定包吻合；调用前 `modelCacheBefore=[]`，因此这次首图包含没有提取模型缓存时的 assets→本地文件准备和推理。GMS/GSF/PlayStore 检查为不存在，networkStart/End 均 null。初始 PSS 10,761 KiB、20 ms 采样峰值 138,114 KiB，运行取消29 ms后返回 Cancelled，非法JPEG返回 InvalidImage。第一轮产物绑定/首用缓存缺口已整改。边界仍是专属 AOSP 模拟器的本地方法，而非实体相机或完整付费 API 流程。

### 剩余问题与验收范围

1. **[P2，证据待补]** 最终固定 APK 下尚未见空白图/预取消原始结果；早先 candidate/ocr3.txt 属于另一个包，不可无说明移植结果。最终报告应补测或标明这两项未在最终包复验。
2. **已知效果限制** 旋转图星期一→星期—需要明示；真实课表、真实拍摄与人工修正量仍 NOT_VERIFIED。23/23 的口径必须写“含阿拉伯数字字段”，并单列星期错误。
3. 最终 QR 相机/相册/多分片/权限恢复/前后台/取消运行由主代理执行，本审查没有操作模拟器；只对所见原始记录作复核，不独立宣称其效果 PASS。
4. 16 KB、x86_64/armeabi-v7a 仍只做静态兼容审计；真实 16 KB 页运行与 iOS 构建未验证。

第二轮结论：固定包静态产物检查及已提交的合成本地 OCR 指标可接受，首轮四项主要补证均有整改；上述剩余效果与最终包空白/预取消边界必须保留。本报告不出具整体验收 PASS。


## 第三轮：960 检测与复用缓冲后的固定包复验

最新对象：`release/sanqian-android-local-engines.apk`，直接读取二进制算得 **73,869,037 bytes**，SHA256 **`27070ffa727e55c8db9aa1ab1b3fc857d32282f938d680666e445745a60b3c54`**。此哈希取代第二轮包作为本报告的最新审查对象。历史错误保留，旧第二轮 OCR 原始记录另存 `benchmark/reviewed-previous-cold.txt/json`。

- 重新扫描实际 APK：ML Kit / GMS / Barhopper DEX 字符串无命中；三 ABI 共 24 个 ELF 的所有 LOAD 段均符合 >=16KB 及 offset/vaddr 同余；zipalign、APK 签名验证成功。signer SHA256 继续为 `0bf510279f816cf61685be14a24dd09547577b9bd14406f6927a208cd8fc688a`。
- 两个模型及 ONNX ThirdPartyNotices 的 APK 内 SHA256 与第二轮完全一致，许可证补齐未退化。当前源使用 960 检测上限，按行复用 pixels，并复用 visited/queue；本轮没有设备操作，源码检查不冒充另一次运行。
- `benchmark/final-cold.txt` 的原始 instrumentation JSON 与 `final-cold.json` 完全一致；其运行时读取已安装包 SHA256 与本轮固定包一致，modelCacheBefore 为 []。因此首图 708 ms 含首次无提取模型缓存的本地准备；后续三图 709/694/726 ms。
- 运行开始/结束 activeNetwork=null，GMS/GSF/PlayStore 查询 absent；继续限定为已有 AOSP 离线探针证据，非持续抓包或无 GMS 真机结论。
- 初始 PSS 10,634 KiB、20ms 采样峰值 152,943 KiB，增量 **138.97 MiB**，在预设150MiB增量门槛内。仍是采样峰值，不能声称排除所有更短瞬态峰值。
- 最终包本地方法：运行取消35ms返回 Cancelled、预取消返回 Cancelled、无效JPEG返回 InvalidImage、空白图0 token。本轮已补齐第二轮最后的固定包空白/预取消证据缺口。

### 独立指标重算

独立解析 raw JSON 后，再次自行执行空间配对、Levenshtein、IoU 和 finite 检查，未调用会覆写文件的 score.py；重算结果逐项断言与当前 comparison.json 一致。四张输入哈希仍与旧包一致，51个新token均有有限合法框和有限 [0,1] confidence。

| 指标（4张合成图） | 旧 ML Kit 固定基线 | 最新固定包 |
|---|---:|---:|
| 严格字段匹配 | 46/51 | **51/51** |
| 空白归一化字符编辑错误 | 5/311 | **0/311** |
| 含阿拉伯数字字段严格匹配 | 21/23 | **23/23** |
| 含星期字样字段严格匹配 | 8/8 | **8/8** |
| IoU >=0.5 定位字段 | 51/51 | **51/51** |
| 四图耗时 ms | 85/64/63/69 | **708/709/694/726** |

第二轮旋转图“星期一→星期—”在本轮相同输入上已修正；不删除该历史失败，也不据本轮全匹配推导真实照片普遍优于旧引擎。新引擎在这批样本上仍明显慢于旧版，资源门槛虽达到，性能差异应保留在交付对比。

### 第三轮结论

本审查提出的四项第一轮问题及第二轮最终包空白/预取消补证，**均已在上述明确范围内整改复验**。最新固定包静态 SDK 去除、签名/ABI/对齐、随包模型/许可证、这批合成本地 OCR 的字段/位置/置信度/首用/取消/空图/坏图证据通过。**真实课表、真实拍摄、用户人工修正量、国产无GMS真机、实际16KB页设备和iOS运行仍未验证**。本审查不操作模拟器，QR UI 实测以主代理最终证据为准；不以此报告代替整个产品效果验收。

第三轮后状态：代码 reviewer 发现 openAppSettings 返回 false 未清标志，主代理已修复并重新构建。上述27070哈希只表示第三轮已审候选，不称最终交付；新包需要重新绑定验收证据。


## 第四轮：最终交付包独立复核

**审查对象固定为** `release/sanqian-android-local-engines.apk`：直接读取所得 **73,871,033 bytes**，SHA256 **`00cb1775d79a21bd24cb08a6d5398be4358f37e542067f5bcf3f761da59d3428`**。它包含主代理修复的设置返回 false 标志处理，取代前三轮候选；本节是当前结论。

### 包与原始证据绑定

`final-cold.txt` 的原始 instrumentation JSON 与 `final-cold.json` 完全一致，运行时已安装 APK SHA256 与上述二进制逐字匹配。modelCacheBefore=[]；GMS/GSF/PlayStore absent，networkStart/End=null。首次无提取缓存的本地准备及推理710ms，后续图694/689/714ms。运行取消30ms返回Cancelled，预取消返回Cancelled，坏JPEG返回InvalidImage，空白图0 token。

初始PSS为10,699KiB，20ms采样峰值161,374KiB，**增量147.14MiB**，本次测量低于150MiB预设线。余量只有约2.86MiB；这是指定模拟器和样本的单次采样结果，不能扩展为所有设备、真实大课表或瞬态峰值均不超线。

### 质量与静态检查结果

再次独立实现空间归组、编辑距离、数字/星期字段和IoU计算，逐项与comparison.json断言一致：

- 严格字段 **51/51**，空白归一化字符 **0/311错误**。
- 含阿拉伯数字字段 **23/23**；含星期字样字段 **8/8**。
- IoU>=0.5定位字段 **51/51**；所有实际token都有合法有限框、有限[0,1]置信度。
- 旧包同图仍为严格字段46/51、5/311字符错误，四图85/64/63/69ms。新包在本组合成识别更准但明显更慢。
- 实际APK DEX中未找到MLKit/GMS/Barhopper；三ABI共24个ELF所有LOAD段均满足16KB静态对齐和offset/vaddr同余；zipalign与签名验证成功，证书与旧版一致。
- 模型及ONNX ThirdPartyNotices的实际APK字节哈希与前轮相同；未重复联网下载许可证。
- `git diff -- ios`为空；darwin 8个文件再次逐一哈希对比原mobile_scanner 7.1.3完全一致。Android限定Dart改动的边界沿用前轮代码审查，不据此宣称iOS运行验证通过。

### 最终意见

**本独立证据审查提出的问题均已完成范围内整改复验；未发现此固定包的新静态产物阻断问题。** 可接受的结论限定为：MLKit及其Play Services SDK代码已从此release移除，离线本地OCR在这组AOSP合成探针及合同/资源测试中通过。image_picker原有disabled Photo Picker backport metadata仍存在，非MLKit SDK代码。

**仍为NOT_VERIFIED：真实课表/真实拍摄效果、真实人工修正量、国产无GMS真机、实际16KB页设备运行、x86_64/armeabi-v7a实际运行、iOS构建与设备回归。** QR相机/相册多分片及权限生命周期交互由主代理/代码reviewer的对应运行证据负责；本审查没有操作模拟器，不用静态结果代替QR效果验收。前三轮失败与较差结果继续保留，不改写为始终通过。


## 第四轮补充：最终 QR 证据复核

本轮只读核对最终交付的 UI XML、已有截图、两份 SQLite、`qr/gold.json`、`delivery-qr-results.json` 与 `delivery-camera-closed.txt`，未操作模拟器、未重跑扫码。结果文件绑定的 APK SHA256 为第四轮最终包 `00cb1775d79a21bd24cb08a6d5398be4358f37e542067f5bcf3f761da59d3428`。

- **权限恢复与分片状态已见运行证据：** `delivery-denied.xml` 显示相机暂不可用及打开系统设置入口；`delivery-permission-return.xml` 显示恢复后确认导入 3 条课程。分片 XML 与已查看截图分别显示 1/3、后台恢复后 2/3、全部分片完成后的 3 课程确认。离散截图证明对应状态，不能独自代替连续事件轨迹。
- **相机路径导入数据独立核对通过：** 用 `mode=ro&immutable=1` 读取 `delivery-db/course.db`，默认课表之外恰有 1 个合成课表及 3 条课程。逐字段断言与 gold 一致，weeks 按 JSON 数组比较；唯一预期差异是 gold 的空 course_id 被生成整数 ID。
- **相册路径新增数据独立核对通过：** `delivery-gallery-db/course.db` 恰有默认课表加 2 个合成课表、共 6 条课程；两组课程全部 payload 字段（生成 course_id 除外）与 gold 一致。第一份数据库的全部既有课表及课程行在第二份中逐字段保持一致。相册确认 XML 为 3 课程确认，导入完成 XML 明确显示已导入并切换课表。
- **取消不产生额外课表的证据粒度：** 两次数据库快照相差恰好 1 个课表及 3 条课程，与中途取消分片确认、其后相册单次导入的操作记录相符，未见额外重复写入。现有文件未提供紧随取消动作的独立数据库快照；因此该项是由操作顺序与最终净增量支持，不声称单独直接捕获了取消瞬间数据库状态。
- **相机释放快照通过：** `delivery-camera-closed.txt` 的 Active Camera Clients 为 []，两设备均为 closed/no client instance。历史日志中的更早 DIED 事件不代表本次最终快照仍有活动客户端；也不据此排除所有设备或所有时序中的泄漏。

**结论：新增证据与最终报告的模拟器 QR 导入主结论一致，未发现新增阻断问题。** imagefile 图像输入经过模拟器 CameraX 的路径，属于合成扫码运行证据，不能提升为实体相机、Xiaomi14、真实二维码拍摄或真实用户课表验收。真实数据与真机边界继续保持 NOT_VERIFIED。
