# 状态
Task-ID: ios-full-acceptance-20261017-01a14751
Owner-Session: 01a14751-adb1-78a0-ba9e-d9e5b8e2b334

阶段：1，进行中。
已读取工作区及 App AGENTS.md。已核实大量既有未提交改动，禁止 reset/clean。
正式标识、设备和构建待现场核实；所有业务暂为 NOT_VERIFIED。

阶段1现场结果：Xcode 26.5 (17F42)，iOS 26.5；新建隔离模拟器 FBC49642-E3AF-4E73-952A-DAE24EEE8E35。可连接 iPhone 15 Pro Max 仅装 local.sanqian.schedule 1.0.0(2)，不覆盖。
正式模拟器 Bundle ID / App Group 为 love.sanqian.schedule / group.love.sanqian.schedule。真机 local override 为 love.sanqian.dev、team 空、entitlements 空。已安装 profiles 均为旧团队 ZPAU8L65J4，未找到新团队 dev 或正式 ID profile，真机当前源码验收 BLOCKED_SIGNING；不使用旧团队绕过。
首次 Xcode build 因 ios/Pods/Manifest.lock 缺失失败，正在 pod install --deployment 修复依赖产物，不改变依赖版本。

阶段2发现 FAIL：完整周表进入课程编辑，保存 IOS-QA-101-EDIT、星期六后，SQLite 与 App Group personal-schedule.json 已更新，完整周表仍保留 IOS-QA-101 / 星期一。重复 snapshot 仍旧。根因：独立路由持有打开时的 schedule，父页面 _load 不重建该路由。准备最小修复返回编辑后的路由刷新。
已验证：初次空状态、手动添加、课程详情、周/完整周表入口、重启和同版本覆盖安装持久化；教务无登录读取显示“当前页面没有可识别课表”。模拟器签名重建后已注册正式 App Group，共享文件含25条实际测试课程 occurrence。未修改团队/证书。

修复阶段：PersonalHomeView 完整周表编辑返回刷新已真实复测 PASS，保存后立即显示新课程名。EditCourseView 原无删除入口，已补确认后按 id 删除；10项相关既有测试 PASS，新增删除取消/隔离测试 PASS（delete-test.log）。日/周/月/完整周表均已实际打开。
日历：拒绝权限错误路径 PASS；重置本次测试 App 权限后，系统弹窗允许完全访问，首次导出25条；重复导出仍25条且 ROWID/UUID 不变（calendar-first-export / calendar-second-export.json）。系统原生日历数据库包含其他预装节假日数据，验收按 sanqian-export marker 筛选，不把总行数当本 App 事件数。

二维码图片闭环 PASS：从实际分享页截图，经系统照片选择器解码并确认新增独立 tableId=2，原 tableId=1 保留，各1条相同课程。新建 IOS-QA-TERM-B tableId=3 并切换，App Group occurrence变0；切回原表恢复25条。
提醒真实 EventKit 数据：三档开关开启产生24个未来事件，分别有 -900/-10800/-86400 秒 alarm；关闭3小时后，24个事件仍在，-10800 alarm清除，其他两档保留。到点系统通知送达尚未验证。

WidgetKit：系统选择器中添加小号实际小组件，主屏幕渲染测试课程日期10/24、08:00–08:50、QA-ROOM；点击打开当前 App（保留原提醒页导航），widget-added.png。App Group读写与首次渲染PASS，后续修改刷新待复测。
日历撤销：提醒撤销后0条 reminder、25条 export保留；再撤销导出后0条App事件，系统其他250条事件与首次导出后快照逐条相等（calendar-revoked.json）。

阶段4完成：两处产品修复已模拟器复测；全量178 Flutter测试PASS；固定快照37f54f1c934fc0bc9bcbc3699e0e9b861ed9eb3b，HEAD及真实index未变。60页源码PDF/8页说明书文本与结构PASS，限定视觉检查PASS，无敏感模式命中。新iOS验收修订ZIP已生成并逐条校验，旧ZIP保留。
阶段5：报告 acceptance-summary.md 已写，准备清理本次独立模拟器、构建与预览。报告明确真机签名、真实账号/付费识别、断网、同ID历史升级、通知送达等NOT_VERIFIED，不把全部业务标PASS。

收尾完成：本任务独立模拟器及其测试数据已删除，自有build/pdf-preview已删除。复核HEAD/真实index未变、产品文件与固定快照哈希一致。当前条件下验收交付完成；未验证项留在报告，不记为全部业务PASS。
