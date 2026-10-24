Task-ID: testflight-upload-01a15cda
Owner-Session: 01a15cda-0362-7fa0-a1c0-6b69e215ee33

状态：本轮导出、上传及处理状态核对完成。

已验证里程碑：
1. App Store 分发 IPA 导出成功；主 App 和 Widget 均通过 codesign --verify --strict，签名 Authority 为 Apple Distribution: Xinyu Li (ZPAU8L65J4)，App Store profiles 无开发设备限制、get-task-allow=false，App Group 正确。
2. xcodebuild 上传退出码 0，Upload succeeded，Uploaded Runner，EXPORT SUCCEEDED。
3. 苹果上传响应确认 Uploaded package is processing（客户端时区 2026-10-21 13:57:47）。尚未确认处理完成或可供测试安装。

对象：三千上课，love.sanqian.schedule，1.0.0 (1)，B 团队 ZPAU8L65J4；Chrome 页面 App ID 6825198107。
产物：build/ios/testflight-01a15cda/export/三千上课.ipa
证据：build/ios/testflight-01a15cda/export.log、verification.json、upload.log。
原归档：/Users/zhuanzmima0000/Library/Developer/Xcode/Archives/2026-10-21/Sanqian-01a15cda.xcarchive

限制：Chrome 扩展读取超时；原生 Chrome 已导航 TestFlight，但页面正文未加载，因此状态依据苹果上传响应，不是网页显示。未邀请测试员、未提交审核、未正式发布。
非阻断警告：当前 iOS deployment target 13.0；上传工具提示 2027 年 4 月起需至少 15.0，本次未修改最低系统版本。
验证脚本先因 codesign verbosity/参数格式失败，改用 -dvvv 后验证通过；一次 upload 命令因选项文件尚未生成退出，随后实际上传成功。临时解压目录已自动清理。
下一步：TestFlight 页面确认服务器处理完成，处理实际出现的合规项，再按授权配置内部测试。

2026-10-21 新指令：用户要求直接外部测试。授权配置既有构建 1.0.0 (1) 的外部测试及准备 Beta 审核；不擅自邀请未知接收人或发布公开链接。
当前网页已确认 Ready to Submit；将检查外部测试入口、必填测试信息和审核联系人，准备并在信息充分时提交 Beta 审核。

外部测试里程碑：已创建内部占位组（关闭自动分发，0 testers/0 builds）以满足 Apple 前置条件；外部测试组已创建，ID 92032e4d-5b5a-487a-83dc-e05385b70193。已选择构建 1 并进入 Test Information 向导。用户确认联系人李滔、18920540630，审核及反馈邮箱沿用 18920540630@163.com。表单尚未保存提交，正在处理原生 AX 输入未触发网页验证的问题。无邀请或公开链接。

最新里程碑（2026-10-21）：用户手动完成测试说明并提交 Beta 审核。用户提供的截图 codex-clipboard-29bb5788-4cd1-4936-8e45-8fcfada0f279.png 显示外部测试组 0 Testers / 1 Build，1.0.0 (1) 状态 Waiting for Review。确认外部测试审核已提交、尚未获批；截图证据，未重新联网检查。不再以之前未提交表单状态为当前状态。下一步等待苹果审核结果，获批后按用户明确指定的邀请方式和对象开放测试；未创建公开链接或邀请测试员，未提交正式 App Store 上架审核。
