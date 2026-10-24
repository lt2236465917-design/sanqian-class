# Android 模拟器追加验收（2026-10-17）

环境：API 35，sanqian_visual_api35，release；用户确认暂不提供真机。
最终 APK SHA-256：bac247249fb163768e9506c5016cf321903ba27f0344a7091bd88db45125ad25。

## 修复与结果
- PASS：手动课表有时钟无节次名称时，显示实际时间而非“时间待定”；ClassTimeUtil 回退 clockRange；final-home.xml。
- PASS：R8保留 device_calendar 类字段，防止 calendar ID 丢失重复创建；创建/更新 Event 明确 Confirmed，避免 Android15 provider 更新 null status 崩溃。连续导出均成功25条，event IDs及calendar3数据不变；final-export-success.xml、final-reexport-success.xml、final-*-events.txt。撤销准确删除25条，未动其他50条测试事件。
- PASS：提醒未来24个课程事件各含15/180/1440分钟共72条；关180后48条，事件ID不变；撤销后无提醒及calendar4课程。reminder-*.txt/xml。仅证明系统日历安排，不证明到点通知送达。
- PASS：176 Flutter tests；最终release构建和签名校验；final-build.log、final-apk-signature.txt、flutter-tests-final.log。
- PASS：手动建课表/加课、日周月与完整周表、教室编辑及重启持久化，SQLite字段核对；after-edit.db/data.json。
- PASS：二维码生成，复制分享串并通过剪贴板导入，新增独立课表并保留字段；after-share-import.db、imported-result.xml。未测相机扫码/图片二维码识别。
- PASS（限定）：旧namespace+同love applicationId测试包 -> 新包覆盖安装，7个持久文件字节不变、课程保留；upgrade-data-comparison.json。旧包是在隔离目录重建的迁移前测试包，不是历史实际交付包。
- 已确认兼容边界：旧混合包widget被系统移除，必须重加；widget-before/after-upgrade.txt。
- PASS：重加widget id7绑定love/love组件；widget-final-binding.txt、widget-final-home.xml/png。实际经ui.tap_label对launcher课程区域执行adb input tap，在关闭Wi-Fi及移动数据时打开新包并显示课程；widget-final-click.xml、widget-final-open-offline.xml。activity记录仅证明前台组件，不独立证明点击来源。
- PASS：切回默认课表、通过界面删除两份QA课表，widget自动显示空课表；qa-deleted-tables.xml、widget-after-table-switch.xml。仅删除本轮QA资料。

## 未验证范围
真机及OEM、iOS本轮运行/分发签名、真实账号教务登录、付费AI/OCR联网识别、相机/照片权限与扫码、实际通知送达、跨包自动数据迁移、全部异常/业务组合不属于本轮已验证结果。
历史交付APK applicationId=local.sanqian.schedule，与love为两个App，仅查metadata，未作为原位升级测试使用。
上述有界验收不等于完整业务全部通过或官方软著通过。无真实账号、图片/凭据和真机时，不编造这些结果。

## 收尾
- 系统crash buffer为空（final-crash-buffer.txt）。
- 通过界面删除本轮两份QA课表；按已确认ID及名称清理本轮4个测试calendar，events查询为空（qa-calendar-cleanup.txt），不是宣称产品自动清理历史重复。
- 已删除本次隔离旧包构建目录及其中本地签名配置。原App及原有文件未删除。
