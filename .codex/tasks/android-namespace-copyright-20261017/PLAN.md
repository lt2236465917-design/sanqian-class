# Android 命名统一与软著更新

Task-ID: android-namespace-copyright-20261017
Owner-Session: 01a14709-d662-7882-8a5b-a1ff3727ef4f

## 范围和约束
- 统一 Android namespace、包声明、目录、Manifest 和 keep 规则。保留其他现有修改及 iOS 临时真机配置。
- 源码修改完成后启动一个独立审核子 Agent，修复所有阻断问题后才生成材料。
- 从可复现的固定源码快照生成软著 PDF，更新字段、清单、验证记录和新 ZIP；不提交官网。
- 不恢复或覆盖其他任务的 PLAN/STATUS。

## 里程碑
1. 保存基线，迁移源码。
2. Android 测试、release 构建和可用设备验证。
3. 独立审核及必要修复复核。
4. 固定源码快照、重生成材料、PDF 校验、打包。

## 追加验收（2026-10-17，用户授权）
5. 探测真机；无设备时请求连接，同时继续模拟器验收。
6. 在隔离目录复现迁移前 love applicationId + local namespace 测试包，验证覆盖安装、数据与小组件行为；另核对归档旧包不同 applicationId 的安装关系。
7. 执行手动课程、多课表、日周月、编辑持久化、日历/提醒、分享、设置及异常路径；真实学校登录/AI 依赖账号和费用授权，不伪造通过。
8. 按场景记录 PASS/FAIL/NOT_VERIFIED，必要时修复并复核；若源码改变则重走审核及材料同步。
