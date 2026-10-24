# 状态

Task-ID: android-namespace-copyright-20261017
Owner-Session: 01a14709-d662-7882-8a5b-a1ff3727ef4f

阶段：基线检查完成，准备迁移。

- 已读两个目录 AGENTS.md；当前 App 工作目录为本目录。
- applicationId 已为 love.sanqian.schedule；namespace 和源包名仍为 local.sanqian.schedule。
- 工作区存在既有未提交改动；已记录基线并保留。
- 审核、构建、运行和材料更新：待执行。

## M1 已完成
- 已同步 namespace、3 份 Manifest、6 条 ProGuard keep 规则和 31 份生产/测试包声明；源码及测试目录已迁移至 love/sanqian/schedule。
- 未修改 applicationId、iOS 临时签名、数据存储键和功能逻辑。
- 后续：构建、测试、设备启动、子 Agent 审核。

- 独立审核已委派 android_namespace_review；仅允许子 Agent 写 review.md。

## M2 验证进展
- flutter build apk --release：成功，约 58 MB；apksigner verify：通过。
- APK Manifest：applicationId 与所有自有组件均为 love.sanqian.schedule。
- :app:testDebugUnitTest：6 suites，44 tests，0 failures/errors/skipped。
- API 35 模拟器 install 成功；am start -W：Status ok，COLD，MainActivity，TotalTime 1201 ms；首页 XML 已保存，crash buffer 为空。
- 子 Agent 静态和产物审核目前无 blocker，等待小组件检查后落最终报告。
- 升级边界：若已有 love applicationId + local 内部组件的测试安装，旧 widget 需重新添加；不承诺无缝组件迁移。

- M2 完成：新 widget id=3 系统绑定 love.sanqian.schedule/love.sanqian.schedule.ScheduleWidgetProvider；桌面显示正常，点击打开新包 MainActivity，crash buffer 为空。
- 首次误选同名旧组件的测试已作废，测试添加的旧 widget 已移除。

## M3 已完成
- 独立审核 PASS：review.md，无阻断项。
- 审核后源码哈希一致，允许生成软著材料。
- 固定源码快照：91504055e186c0bc09a27d069811a494aa66164c；引用 refs/codex/copyright-20261017-01a14709。用独立 index 生成，不改当前分支或暂存区。

## M4 已完成
- 固定源码 91504055e186c0bc09a27d069811a494aa66164c；134 个业务文件哈希逐一匹配当前源码。
- 源码 PDF 60 页，每页 50 条非空源码；说明书 8 页，每页 37–38 行，正文未改。
- PDF 字符/文本/映射/名称/页码/结构及敏感扫描通过；全部页面缩略图和源码第 43/60 页详细视觉检查通过。
- 材料文档同步新标识与快照，保留历史官网核验日期；未填写 Apple Team ID/账号状态或权属事实。
- 新交付 ZIP：/Users/zhuanzmima0000/Desktop/课表/软著材料/三千上课-V1.0-软著材料更新包-20261017.zip，21 个文件，逐文件匹配、CRC 校验通过。
- 旧 ZIP 保留；未上传或提交版权系统。

最终状态：COMPLETE。审核及构建日志留在本任务目录；真机、旧版升级、完整业务、iOS 本轮运行及官方登记通过仍 NOT_VERIFIED。

- 收尾：临时 PDF 渲染与 UI 中间文件已清理；本次启动的模拟器已退出（启动时禁用保存快照），当前分支 HEAD 与暂存区未改变。

## 追加验收进行中
- 用户要求补充真机、原位升级和业务流程验收。
- adb devices 无连接设备；已询问能否连接 Android 真机，模拟器部分继续。
- 找到历史 APK output/sanqian-class-1.0.0-3-android-release-d522a34.apk；尚需核对包名/版本/签名。
- 当前已完成材料保留，不把后续测试结果提前标为 PASS。

## 追加验收发现与修复
- 原位升级：迁移前同 applicationId 测试包覆盖新包成功；7 个持久化文件字节不变，课程保留。旧 widget 绑定实际被移除，需重加，非无缝升级。
- Flutter 原有 175 tests 通过。
- FAIL：release 包连续日历导出 25 -> 50 条，产生第二个日历；R8 mapping 确认 Calendar.id 等字段被重命名，插件官方 README 明确要求 keep。已增加插件 keep 规则，待 release 实测。
- FAIL：无节次标签的手动课表实际有时间，却显示时间待定；已回退显示实际 clockRange，添加界面回归测试。
- 因业务修复修改源码，之前材料快照暂非最终当前源码；复核通过后重生成材料。

## 追加验收完成（限定模拟器范围）
- 用户确认暂不提供真机，先验模拟器；完整范围见 acceptance/summary.md。
- 三处问题修复并实际复测通过：明确时间的显示、R8插件模型保留、日历事件Confirmed状态。
- 176 Flutter tests、release构建/签名通过；日历导出更新撤销、提醒组合调整撤销、同ID测试包升级数据保留、小组件重加/显示/离线打开、课表切换删除已验证。
- 原 subagent 复审 PASS：acceptance/review-followup.md；历史失败证据保留，未伪装为成功。
- 最终源码快照 134eadac1b5309affcf63de4db0f2441ffc131dc；refs/codex/copyright-20261017-verified-01a14709。真实HEAD和暂存区不变。
- 134业务源文件、29322物理行、27082非空行；60页源码及8页说明书已重生成，全页文本映射/字符/结构、敏感扫描与视觉检查通过。
- 新交付：三千上课-V1.0-软著材料更新包-20261017-验收修订.zip，21文件，逐字节及CRC通过；旧包保留，未提交官网。
- QA课表、日历、桌面widget已清理；本次隔离旧包构建目录（含签名配置）已删除，本次模拟器已关闭；证据保留。
- 真机/OEM、实际通知送达、真实教务登录、付费AI/OCR、相机图片扫码、iOS本轮运行分发、历史交付包升级和全部业务组合仍NOT_VERIFIED。
最终状态：本轮获授权的模拟器限定验收及材料修订完成；外部依赖范围未作通过声明。
