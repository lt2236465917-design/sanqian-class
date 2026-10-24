# Android 追加验收独立复核

Task-ID: android-namespace-copyright-20261017
Owner-Session: 01a14709-d662-7882-8a5b-a1ff3727ef4f
Reviewer: android_namespace_review
Date: 2026-10-17

## 最终结论：PASS（有界模拟器验收）

已发现的问题已修复并取得实际系统日历复测证据，当前审查范围内没有剩余阻断项。允许主 Agent 固定最终源码快照并重新生成软著材料。此 PASS 不等于真机、全部业务组合、历史交付版本升级或官方软著审查通过。

最终审查 APK：build/app/outputs/flutter-apk/app-release.apk。
SHA-256：bac247249fb163768e9506c5016cf321903ba27f0344a7091bd88db45125ad25（审核时独立重新计算，与主 Agent 记录一致）。
本报告只由审核 Agent 写入；业务源码、运行环境和其他状态未由审核 Agent 修改。

## 修复正确性与范围

- android/app/proguard-rules.pro:25 的 `-keep class com.builttoroam.devicecalendar.** { *; }` 与本地 device_calendar 4.3.3 README:80-90 的推荐规则完全一致。依赖 CalendarDelegate.kt 使用 Gson.toJson 序列化 Calendar/Event，模型字段没有 SerializedName；旧 R8 破坏字段名能够解释读取 calendar ID 失败及重复创建。当前 release mapping 保留 Calendar/Event 名称，规则只覆盖该插件包，没有关闭全局混淆或扩大到全部应用。
- lib/Utils/ClassTimeUtil.dart:65 仅在首尾 label 缺失时回退既有 clockRange；非法/缺失钟点仍返回 null，有 label 的时段仍保持原逻辑。test/Pages/personal_home_week_details_test.dart:15 新增实际 Widget 回归，覆盖首页与课程详情钟点、错误“待定”文案和无异常，不修改排课算法。
- lib/Utils/ScheduleCalendarExporter.dart:222 与 lib/Utils/ScheduleCalendarReminders.dart:303 将本应用维护的课程事件明确标记 EventStatus.Confirmed。首次仅添加 keep 后复测仍失败，审核已打回：fixed-reexport-result.xml 明确显示“导出未完成”。独立读取运行日志确认 NPE 来自 CalendarProvider2.doesStatusCancelUpdateMeanUpdate；插件无条件写入 nullable event status，应用 Event 默认 null。此次显式状态修复对应实际根因，未修改依赖缓存、引入 vendor fork 或绕过平台校验。对应测试断言新建事件状态；最终以真实 provider 更新成功为主要证据。
- 最终 diff 已移除无关 formatter 变化。新增修复只涉及 ProGuard、一个显示 fallback、两处事件状态及三个相关测试文件；未改 iOS 签名、权限申请规则或其他业务逻辑。

## 已独立核对的验证

1. flutter-tests-final.log：176 Flutter tests 全通过。final-build.log：release 构建成功；final-apk-signature.txt：APK v2 签名验证成功。final-crash-buffer.txt 为零字节。
2. 日历重复导出：final-export-success.xml 与 final-reexport-success.xml 均显示成功写入 25 次课程；两次 final-*-events.txt 字节相同，calendar_id=3 的同一 25 个事件未重复。final-revoke-result.xml 显示移除 25 次课程，final-revoke-events.txt 中 calendar3 事件全部消失。此前失败测试 calendar1/2 各 25 条仍保留，此证据证明本次导出/更新/撤销，不证明自动修复历史重复数据。
3. 提醒：reminder-all-events.txt 中 calendar4 有 24 个未来事件、eventStatus 均为 1；reminder-all-rows.txt 为 24×15/180/1440 分钟，共 72 条。取消 180 分钟后 reminder-changed-rows.txt 剩 48 条，all/changed-events 文件字节一致，事件 ID 未改变。撤销后 calendar4 事件消失，reminder-revoked-rows.txt 没有提醒行，旧测试事件保留。证明真实系统日历写入、更新和撤销，不证明到点通知送达。
4. 手动课程/编辑/分享：只读打开 after-edit.db，课程 QA-Namespace 的 Room-202、Teacher-QA、25 周、周六第一节与 08:00–08:50 时段一致；after-share-import.db 新增独立 table3 与课程副本，核心字段保持。final-home-stable.xml 显示实际钟点，不再错误显示待定。页面操作链与其余 UI 证据由主 Agent 执行，见 summary.md；不把夹具测试替代真实登录或 OCR。
5. 原位升级：baseline-install.txt / upgrade-install.txt 记录同 love applicationId 的旧内部 namespace 测试包覆盖新包成功；独立比较两份 tar，排除 cache 后 7 个持久文件逐字节一致。完整 tar 前 8 后 7 的唯一差异为 cache/oat_primary/arm64/base.art，此缓存差异不属于课程数据丢失。旧 APK 是隔离重建的迁移前测试包，不是历史真实交付 APK；不泛化为所有旧版本升级。
6. 小组件兼容边界已实测：widget-before-upgrade.txt id5 绑定 love/local，升级后 Widgets 为空，必须重新添加。最终 widget-final-binding.txt:74 的 id7 绑定 love/love；widget-final-home.xml 的新包 RemoteViews 显示课程、教室、时间。summary.md 记录通过 launcher 课程区域实际 tap，在断网下打开新包；widget-final-open-offline.xml 保留课程。activity 仅为辅助证据，不独立证明点击来源。早先误选同名旧 app widget 不计为新版本成功证据。
7. qa-deleted-tables.xml 仅剩默认课表，widget-after-table-switch.xml 显示暂无已排课程，支持切表/删除本次测试课表后的刷新。

## 未验证与非阻断限制

- 用户明确暂不提供真机。真机/OEM、iOS 本轮运行/分发、真实教务账号登录、付费 AI/OCR 联网识别、相机/照片权限和二维码识别、真实到点提醒送达、全部异常路径仍 NOT_VERIFIED。
- 旧混合包 widget 不保留；历史 local/com.lilystudio applicationId 是其他应用，不自动迁移私有数据。此次只证明受控同 ID 测试包升级。
- 日历插件仍在 logcat 输出 allDay Boolean 到 Integer 的 provider 类型警告；其源码为 values.put(Events.ALL_DAY, event.eventAllDay)。当前实际导出、更新、撤销及提醒路径已通过，未观察到该警告导致本轮功能失败。本次直接 blocker 是 null status，不能混淆二者；不为该非阻断依赖警告扩大本轮代码范围。
- 之前生成的软著快照不含新增业务修复，必须在本次 PASS 后重新固定源码、生成和校验；本报告并未审核尚未生成的新 PDF/ZIP。
