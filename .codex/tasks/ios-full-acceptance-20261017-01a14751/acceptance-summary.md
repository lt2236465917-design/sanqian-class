# 三千上课 iOS 实际验收

Task-ID: ios-full-acceptance-20261017-01a14751
Owner-Session: 01a14751-adb1-78a0-ba9e-d9e5b8e2b334
日期：2026-10-17（Asia/Shanghai）

结论：已完成当前条件下可执行的有界模拟器验收，发现并修复两处课程管理问题。不能宣布“iOS全部业务/真机/正式上架验收通过”。未验证项和签名阻碍见下表。

## 源码、设备和构建

- 唯一源码目录 `/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`，没有使用旧 checkout 构建，没有 reset/clean。
- 固定源码 `37f54f1c934fc0bc9bcbc3699e0e9b861ed9eb3b`，引用 `refs/codex/ios-acceptance-20261017-01a14751`，基于前次固定快照134eada，仅增加本次2个业务源文件及1个测试文件。工作分支HEAD仍6363d5b，真实暂存区SHA-256前后相同。
- Xcode26.5(17F42)，Flutter3.35.7/Dart3.9.2；独立iPhone16Pro模拟器iOS26.5，UDID FBC49642-E3AF-4E73-952A-DAE24EEE8E35。
- Runner Debug，love.sanqian.schedule，group.love.sanqian.schedule。最初Pods/Manifest.lock缺失，pod install --deployment修复本地依赖，锁定版本未变。无签名构建不能注册共享容器，后用模拟器本地签名重建并验证App Group，不涉及Apple团队。
- 最终业务构建日志 `evidence/build_sim_2026-10-17T00-56-19-945Z_pid99078_4e90698c.log`，产物哈希 `evidence/build-hashes.json`。模拟器构建与开发调试模式不能证明Release真机/分发签名。
- 真机现场读到iPhone15ProMax可连接，已有local.sanqian.schedule 1.0.0(2)。未覆盖、启动或改动其真实数据。当前解析真机配置love.sanqian.dev，开发团队空、无App Group entitlement；本机描述文件全部属旧ZPAU8L65J4。未找到匹配新ID/新团队的profile，不把旧团队wildcard或分发证书当作新版本资格。

## 功能矩阵

| 功能 | 结论 | 实际操作与证据 | 边界 |
|---|---|---|---|
| 首次启动 | PASS_SIM | 独立设备首次安装，显示空日课表；实际首页可操作 | 仅iOS26.5 Debug |
| 手动添加 | PASS_SIM | UI填写IOS-QA-101、QA-ROOM；SQLite Course保存星期一及1–25周，首页显示10/19下一节 | 输入法自动化曾把教师英文分词，按实际落库值记录，不当作App缺陷 |
| 编辑课程 | FIXED_PASS_SIM | 完整周表改名和星期，SQLite已更新但旧路由未刷新；修复后保存即显示新名，回归测试用真实临时SQLite | 未遍历全部字段/日期组合 |
| 删除课程 | FIXED_PASS_SIM | 编辑页原无入口；新增二次确认。取消前后2条Course不变，确认后仅目标id1删除，table2的同名副本id2保留；共享occurrence25→0 | delete-cancel.json、delete-confirmed.json；删除与已启用日历提醒联动组合未另测 |
| 学期管理 | PASS_SIM | QR新增table2；新建IOS-QA-TERM-B table3，切换空表AppGroup为0，切回table1恢复25 | empty-term-selected.json；未调整学期起始日期 |
| 日/周/月/完整周表 | PASS_SIM | 四种视图实际打开；日期、星期、08:00–08:50、地点与当前Course一致；完整周表详情可编辑 | 超长文本/所有字号与尺寸未穷举 |
| 持久化 | PASS_SIM | 重启与同版本覆盖安装后课程保留；深色重启保留 | 不等同历史版本升级 |
| 可靠旧包同BundleID升级 | NOT_VERIFIED | 当前连接真机旧包为local.sanqian.schedule，新版正式ID为love.sanqian.schedule；本轮没有来源可靠的同ID历史包 | 不用异ID并存或同版本重装冒充升级 |
| 真正断网查看 | NOT_VERIFIED | 本地SQLite与重启读取已验证，未实际隔离模拟器网络 | 没有改动宿主机网络影响其他任务；架构离线能力不算断网实测 |
| 二维码分享/图片导入 | PASS_SIM | 实际分享页生成二维码并复制分享串；截图放入本次模拟器相册，经系统选择器解码，确认新增独立table2，原table1保留 | qr-share.png、share-payload.txt、qr-image-import-confirmed.json；相机实扫、剪贴板导入及多段二维码未测 |
| 日历拒绝 | PASS_SIM | 系统权限弹窗点“不允许”，App显示导出未完成及去设置 | ui-selected.json；去设置打开系统设置首页（模拟器行为），没有假称直接到App权限页 |
| 日历允许/首次导出 | PASS_SIM | 重置本次App权限后真实弹窗允许；EventKit落25条带sanqian-export标记事件 | calendar-first-export.json |
| 重复导出 | PASS_SIM | 再次确认导出，仍25条，ROWID/UUID完全相同，仅一份本App导出日历 | calendar-second-export.json；编辑后再导出、全删后再导出组合未另测 |
| 日历撤销 | PASS_SIM | UI撤销，App导出事件归0，系统其他250条预置事件逐条不变 | calendar-revoked.json |
| 15分钟/3小时/24小时提醒 | PASS_SIM_SCHEDULING | UI三档打开；24个未来事件分别包含-900/-10800/-86400秒alarm。关闭3小时后该档清除，其他两档保留；撤销全部后reminder事件0，export事件仍25 | reminders-all/15m-24h/revoked.json。系统默认零分钟alarm另有24条，未混算三档提醒；到点送达NOT_VERIFIED |
| WidgetKit共享 | PASS_SIM | 真实AppGroup personal-schedule.json与当前表一致，课程改名/星期与删除后更新 | widget-after-edit.json、delete-confirmed.json |
| 小组件添加/显示/点击/刷新 | PASS_SIM_SMALL | 系统选择器添加小号组件，主屏幕显示下一节日期10/24、08:00–08:50、QA-ROOM；点击打开App；删除课程后显示暂无已排课程 | widget-added.png、widget-after-delete.png；仅小号，点击保留App原提醒页导航。其他尺寸、锁屏、真机未测 |
| 外观 | PASS_SIM_LIMITED | 初始浅色，UI切深色真实渲染，重启首页仍深色 | appearance-dark.png及会话截图；系统自动切换和所有显示组合未测 |
| 教务入口及错误 | PASS_SIM_ERROR_PATH | 学校账号留空打开原生网页，点读取并识别返回“当前页面没有可识别课表” | 未登录，不证明网站正常登录/全量导入 |
| 图片/AI入口及错误 | PASS_SIM_ERROR_PATH | 系统照片选择器选择本次二维码图片；点AI识别因无Key进入设置；空保存提示请先填写Key；返回图片仍在 | 未发送识别请求，未配置凭据。真实课表OCR/AI结果NOT_VERIFIED |
| 真机当前版本 | BLOCKED_SIGNING | 设备可连接，但新团队team/profile未配置 | 不归因于没有iPhone；需要正确团队配置后再跑 |
| 正式签名/上架资格 | NOT_VERIFIED | 仅检查配置与本机profile，不上传TestFlight/AppStore，不变更付费账号、证书或ID | 模拟器本地签名不证明分发通过 |

## 修复、检查与材料

产品改动仅 `lib/Pages/Personal/PersonalHomeView.dart` 和 `lib/Pages/AddCourse/EditCourseView.dart`。测试改动仅 `test/Pages/edit_course_test.dart`，新增真实数据库编辑后完整周表刷新，以及删除取消/仅删目标两项。178项Flutter测试全部通过，最终diff-check通过。新增刷新测试最初把Semantics identifier当Widget key导致测试查找失败，修正测试选择器后通过；没有以该测试失败误判运行缺陷。Android真机/构建未因本轮重复执行，其历史验收不升级为当前源码运行证据。

已更新软著固定快照、代码统计、可编辑说明书、60页源程序PDF、8页文档PDF和清单。PDF文本/映射/页码/边界检查通过，敏感模式扫描无命中。视觉检查范围：说明书全部8页联系表及修改页4全尺寸；源程序页1/30/31/43/60，43为最小字体页。其他源页为结构检查，未逐页人工视觉检查。

新交付 `/Users/zhuanzmima0000/Desktop/课表/软著材料/三千上课-V1.0-软著材料更新包-20261017-iOS验收修订.zip`，22条文件全部与当前材料逐字节一致，CRC通过，SHA-256 `620bf311ec0a71f5b443d332a7ebaa6ec7241d2194fe984f61cfd2569ff39800`。历史包未覆盖；无官网提交。

## 后续最小配合

1. 在新团队上完成有效开发签名配置（确认团队ID及匹配profile）。免费个人版仅可验主App；正式App Group/Widget真机需要合适的付费团队能力。不要将正式ID交给旧/免费团队。
2. 真正教务与图片识别验收需要用户自己的学校登录、可用课表图片，以及明确的DeepSeek调用费用授权。当前没有为验收擅用账户或Key。
3. 历史升级验收需要来源可靠、同Bundle ID且可安装的旧包；到点通知需真实设备配合等待和系统提醒设置核对。

## 清理

本次日历导出及提醒已从系统中撤销；课程删除验证已留快照。独立模拟器中的其余课表/二维码照片/小组件，以及本任务临时构建和PDF预览，收尾统一删除；只保留复核所需日志、数据快照和最终材料。其他模拟器、真机旧App及用户既有工作区改动保留。
