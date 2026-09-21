# 三千上课：本地 iOS 开发

基于 [南哪课表](https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter) 的个人版，保留 Apache-2.0 许可与上游署名。上游提交 `25125ef6c7092c47f9341adcfaa7e1dc1974b44d`，版本 `4.0.2+67`，本地分支 `codex/ios-bootstrap`；改动尚未提交或发布。

## 当前功能

- 底部常驻悬浮胶囊提供「日课表 / 周课表 / 月课表」三个入口，冷启动默认日课表；每页独立保留浏览位置。iOS 26 起使用原生 `UITabBar` 的 Liquid Glass，切换时透镜鼓起、折射并放大图标，再弹性回落；材质与交互由系统处理。更早的 iOS 和其他平台保留 Flutter 磨砂底栏。右上角齿轮打开设置。
- 原生底栏经 Platform View / MethodChannel 同步选中项和应用主题，保留 UIKit 的默认选中透镜。无障碍标签、选中状态与激活操作由原生 `UIAccessibilityElement` 提供，不叠加 Flutter 触摸覆盖层。系统玻璃的减少动态效果/透明度策略由 UIKit 处理；本轮未单独切换这些系统设置实测。
- 日课表只保留当天课程；课程卡片直接突出下一节或正在上的课，无课日提供简洁的下一节提示。周课表按日期分组，支持切周/回本周，待定课程收纳在周页。月课表以日历圆点标出有课日期，选日期查看当天安排，支持翻月/回本月。所有课程均可打开完整详情。
- 周日期范围、月课程数量居中显示在周次/年月下方。「本周」采用圆角描边按钮，位于第一组日期标题最右侧，空周仍有返回入口；「本月」以相同样式位于月历下方的选中日期标题最右侧。
- 课程保存在本地 SQLite。截图转录包含 14 门课、12 门已排、2 门待定，共 73 次课；原安排合并为 18 条已排记录和 2 条待定记录。课程数据见 [SCREENSHOT_SCHEDULE.md](SCREENSHOT_SCHEDULE.md)。
- 第一周周一为 2026-09-07，开学日为 09-09，09-20 为第二周周日。三个时段来自补充截图：09:00–12:00、13:30–16:30、19:00–21:30。未知的时间、教师和地点仍保持待定。
- App 名称为“三千上课”，暖白/淡紫主题，支持深色模式。图标采用用户确认的黑白边牧原图；桌面图标、启动页和关于页使用同一素材，保留原构图与颜色。
- 设置提供内置课表导入、手动添加、课表管理、二维码导入导出、系统日历、外观和开源许可。内置导入是已核对截图的数据，不是拍照识别新课表。移除了无关校园入口、捐赠、评分以及友盟统计接入。旧校园适配源码保留供后续开发，未从个人版页面开放。
- 模拟器 Bundle ID 保留 `top.idealclover.wheretosleepinnju`，以便原地更新并保留已有数据。真机 `local.chaoxi.schedule` 已用用户 Personal Team 签名安装；其他账号需要配置其可用的唯一 ID。

## 工具链与运行

Flutter **3.35.7** / Dart **3.9.2** / Xcode **26.5** / CocoaPods **1.17.0**。本工作区 SDK 位于 `../.tools/flutter`，包缓存位于 `../.tools/pub-cache`；使用 `tool/flutterw`，无需修改全局 PATH。其他机器可设置 `SCHEDULE_FLUTTER_SDK` 指向同版本 SDK。

本任务仅使用「南哪课表 iPhone 16」模拟器，UDID 为 `EF43A038-4E4B-417D-A813-E2404D1220FD`，iOS 26.5。iPhone 17 是用户的其他测试环境，不操作它。所有模拟器命令显式指定目标 UDID，不使用 `booted`。

在本工程目录执行：

```sh
tool/flutterw pub get
tool/flutterw run -d EF43A038-4E4B-417D-A813-E2404D1220FD
```

构建：

```sh
tool/flutterw build ios --simulator --debug
```

学校账号和 DeepSeek Key 使用 Keychain。模拟器安装包也必须保留 Xcode 生成的应用标识与模拟权限；不要用 `--no-codesign` 的产物做登录验收，否则安全存储可能返回 `-34018`。

产物 `build/ios/iphonesimulator/Runner.app` **只适用于模拟器**。真机安装见 [DEVICE_INSTALL.md](DEVICE_INSTALL.md)：已在连接的 iPhone 15 Pro Max / iOS 18.6.2 安装签名 Release。主 App 不嵌入尚未验收的小组件，不申请 App Groups。

## 截图课表的导入与更新

入口：**设置 → 导入内置课表 → 导入 / 更新本地课表**。没有课程时，首页也提供导入入口。这是已核对截图的本地数据导入，不是通用 OCR。

数据文件为 `res/schedules/zgysyjy_2026_fall.json`，revision 2。第一次导入新建独立课表；同来源后续更新仅补充空作息、空教师和完全匹配的旧默认备注，保留课表与课程 ID、本地编辑和删除。重复更新不增加课程。未来发生调课时需要明确更新，当前不自动同步学校网站。

手动添加使用当前课表的时段列表。截图中的总时段与小节不重复计课；思政大讲堂和导师课未提供安排，保持时间、周次待定。英语换教室和缺课周、摄影周末课程均按原图保留。

## 原生玻璃导航阶段验证（历史，2026-09-20）

```sh
tool/flutterw test --reporter expanded test/Models/screenshot_schedule_test.dart test/Models/personal_schedule_test.dart test/Pages/screenshot_period_display_test.dart test/Pages/personal_period_picker_test.dart test/Pages/native_schedule_navigation_test.dart test/Pages/Share/qr_payload_codec_test.dart test/Utils/CourseParser.dart test/Utils/CourseParserXK.dart test/widget_test.dart
tool/flutterw analyze
```

- **48/48 测试通过**：原有课程数据与日/周/月行为回归继续通过；本轮增加原生桥接的快速切换、非法回调、指针转交、主题/选中同步且不重建视图、释放、旧 iOS 降级和晚到能力回执验证。磨砂降级栏的连续动画/减少动态效果、滚动保留和底部遮挡仍由既有 widget 测试覆盖。
- 最终 iOS Simulator 构建通过（11.5 秒）。统计/评分/旧分享 SDK 的依赖清理沿用上一阶段；该阶段的 clean build 和产物审计保存在 `personal-artifact-audit.json`。
- 静态检查 **0 error、9 warning、141 info**，共 150 项，退出码 1；与改版前相同，本轮修改文件没有提示，不能称为全项目静态检查通过。
- **iPhone 16 原生触摸测试 1/1 通过**：XCUITest 在指定设备真实点按三个底栏按钮，验证页面同步、返回本周/下一周、设置页底栏不可点击、设置返回以及第三周浏览位置保留。原生三个无障碍按钮的标签和选中状态也已在实际可访问性树中核对。
- `liquid-native-touch-acceptance.mp4` 是最终版本的指定设备实录；15.60–16.07s 等关键帧可见透镜鼓起、图标放大/折射、亮边与回落。`liquid-iphone16-native.gif` 裁剪拼接其中四段，保持原速，总长 5.6 秒。用户参考视频与早期 `glass-*` 平移动画不作为最终效果证据。桌面坐标点击曾不触发，最终点按验收以定向 XCUITest 为准；没有声称拖动滑选或真实列表滑动验收通过。
- 更新前后 SQLite 全字段一致：2 张课表、20 条课程记录。截图课程数据未改。
- `git diff --check` 通过。

日志与界面证据位于工作区 `../.codex/tasks/nju-ios-bootstrap/`：`liquid-touch-tests.log`、`liquid-touch-analyze.log`、`liquid-release-build.log`、`liquid-xcuitest-run.log`、`liquid-native-touch.xcresult`；数据库 `liquid-db-before.json` / `liquid-db-after.json`，核对回执 `liquid-data-verification.json`。`liquid-touch-transition-1.png` 为最终切换关键帧，`native-touch-attachments/manifest.json` 定位原生测试导出的第三周截图。隔离 UI 验证工程保存在 `native-glass-ui-check/`，仅面向本任务 iPhone 16；临时测试 Runner 已从该设备卸载，课表 App 保留。

已补 App 主进程网络故障条件下的读取和冷启动验证，详见下节。后续已完成真机签名安装和设置检查，系统日历实际写入仅在专用模拟器验收，见本文最新结果。物理断网 / 真机飞行模式、原生小组件及网站自动同步未验收。原 Android 自定义接入未迁移，不能宣称跨平台完成。

## 离线验证与真机准备（历史，2026-09-20）

- 模拟器仅操作既定 iPhone 16，没有关闭 Mac 网络。独立测试动态库使目标 App 的 DNS 查询返回 `EAI_AGAIN`，IPv4/IPv6 TCP/UDP 调用返回 `ENETDOWN`；对照探针在正常模式可连通。动态库位于任务证据目录，不加入 App 项目或安装包。
- 原生 UI 测试 `testOfflineScheduleAndColdRestart` **1/1 通过**（30.575 秒）：日课表读取、第三周与英语第五会议室、9 月 22 日月历点选、设置页新名称、退出重启回当前日期及重新查看第三周。运行中进程映射确认测试动态库已加载；验收后已终止该进程并正常启动，测试库不再加载。
- 更新和验证前后 SQLite 全字段一致，仍为 2 张课表、20 条课程记录。完整 Flutter 回归为默认 46 项加两项单独调用的历史解析测试，全部通过；analyze 仍为 0 error / 9 warning / 141 info。
- 真机准备阶段 Release **无签名构建通过**（27.0 秒、22.3 MB）。主程序和 13 个嵌入 Framework 均为 arm64、最低 iOS 13；配置覆盖 iPhone 12 起的系统范围，不代表全机型全系统实测。
- 当时没有有效签名或连接真机；此限制已解除。当前 `build/ios/iphoneos/Runner.app` 已签名并安装，详见 [DEVICE_INSTALL.md](DEVICE_INSTALL.md)。

边牧定稿原图保存在 `res/personal-icon.png`，SHA-256 为 `9369a373a814361e636690631d2545b333ee82b6f0e6cc4ad427e29ab5d49663`。`python3 tool/create_personal_icon.py`（需要 Pillow）仅从这张已批准原图派生 iOS 尺寸，校验原图哈希后再写入资产，不再绘制旧的日历图标。1024 像素图标与启动页品牌图按原文件复制；其余规格只等比例缩放，不裁切、调色或添加圆角。系统负责桌面图标圆角。

定稿接入后的 Simulator 构建 11.2 秒、iphoneos Release 构建 7.8 秒通过（真机产物 26.2 MB，仍未签名）。iPhone 16 桌面与关于页均已实际核对，已有原生导航 smoke 1/1 通过，课程数据库全字段不变；证据为任务目录 `logo-asset-audit.json`、`logo-build-audit.json`、`logo-native-smoke.xcresult`、`logo-data-verification.json`、`logo-iphone16-home.png` 和 `logo-iphone16-about.png`。启动页仅确认资源替换和编译，未单独录制启动动画。

证据入口：`../.codex/tasks/nju-ios-bootstrap/offline-ui-attempt1.xcresult`、`offline-ui-attachments/manifest.json`、`offline-check/app-control-result.json`、`offline-check/app-offline-result.json`、`offline-check/offline-ui-process-map.txt`、`offline-data-verification.json`、`offline-cleanup.json`、`device-artifact-audit.json` 和 `device-release-build-named.log`。此处的离线结论只覆盖测试中的主进程网络调用失败，不声称整台设备已物理断网。

## 设置排查与修复（2026-09-20 最新结果）

| 功能 | 修复及实际验证 |
| --- | --- |
| 内置课表 | 明确入口含义；真机重复导入后原数据全字段保持。 |
| 手动添加 | 防重复提交、校验实际周次、保存成功/失败反馈；真机新建测试课程、首页显示和冷启动保存通过。 |
| 管理课表 | 当前表对勾与删除按钮使用相同的48点居中区域。新表沿用当前学期和作息，保留独立来源；切换等待保存、事务删除。真机新建、切换、删除通过，测试表已清理。 |
| 二维码分享与导入 | 分享带学期和作息，导入先预览、事务写入后切换；真机二维码显示及完整分享串复制/粘贴往返通过。 |
| 系统日历 | iOS 同一 EventKit store 处理完整权限和读写；使用真实课次日期与上课教室，逐条检查结果，重复导出更新。专用 iPhone 16 真实授权、73 次事件回读及重复导出不增量通过；真机仅验证导出预览并取消。 |
| 外观与关于 | 真机深色切换、冷启动保留、恢复跟随系统及 Apache 许可证正文通过。 |

扫码现在由“开启相机扫码”主动触发，相册和剪贴板入口可独立使用，错误会给出反馈。真机相机实景扫码已完成识别、预览、导入和重启保存验证（`qr-physical-camera.xcresult`）；真机系统相册选择二维码图片后的预览、导入和重启保存也已通过（`qr-gallery-resumed.xcresult`）。无效二维码录屏可见错误提示，但原生 Toast 的自动 AX 文本断言失败，因此该套件为 2 项通过、1 项失败。普通课表截图 OCR 由用户另行开发，本轮不实现或验证。系统日历导出跳过时间待定安排；在 App 删除课程不会自动删除已导出的日程，确认弹窗已说明。

修复后默认 Flutter 测试 49 项通过；原生适配器收尾后另复验日历相关 3 项通过。最终静态检查为 0 error / 9 warning / 141 info，退出 1，不能称为静态检查全通过。真机短验证 1/1、模拟器日历验证 1/1 通过；测试表清理后与检查前数据全字段一致（2 表、20 条课程，当前表 2）。

证据位于 `../.codex/tasks/nju-ios-bootstrap/`：`settings-tests.log`、`settings-calendar-unit-delivery.log`、`settings-analyze-verified.log`、`settings-final-device-smoke.xcresult`、`settings-calendar-native.xcresult`、`settings-phone-data-preserved.json`。学校同步、原生小组件、真机飞行模式及旧系统全面兼容仍在上述验证范围之外。

## 后续学校网站同步

用户已提供统一认证入口 `https://iam.zgysyjy.org.cn/am/UI/Login` 和研究生入口 `https://wxt.zgysyjy.org.cn:7792/graduate/frameset.jsp`。真实课表 frame、字段与接口尚未读取，不能按地址猜测。

可参考 `api/schoolList.json`、`api/tools/`、`lib/Pages/Import/ImportFromBEView.dart`。上游学校配置原本从 `Url.UPDATE_ROOT` 加载，未来新增本校适配时须一并调整配置来源。此前浏览器连接返回 `unsupported Codex auth method: apikey`，没有登录学校或读取账号凭据；截图路线已解除本轮对网页访问的依赖。
