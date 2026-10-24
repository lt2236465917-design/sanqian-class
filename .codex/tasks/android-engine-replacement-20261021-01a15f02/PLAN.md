Task-ID: android-engine-replacement-20261021-01a15f02
Owner-Session: 01a15f02-b020-75e0-aa1a-e03790568c22

目标：仅替换 Android 本地 OCR 与相机 QR 引擎，移除成品 ML Kit / 其 Play Services；保留 iOS、导入及取消合同。无付费 API、push、备案修改。

里程碑
1. 基线保护、许可证/ABI/16KB 候选评估、真实样本质量门槛。
2. 有界实现，离线模型随包；保留 CameraX / Dart 相册 zxing2。
3. 同样本对比、实际 release 与依赖/manifest/native 审计；无 GMS 环境验证。
4. subagent 独立审查、缺陷整改复验；交付包/哈希与明确缺口。

验收门槛（预设，待真实指定样本）：课程名称和教室字符准确率 >=95%，数字/时间字段 >=99%，不得丢失完整课程行；归一化框有限且处于 [0,1]，关键字段框定位正确率 >=95%；人工修正字段数不高于旧实现。相同设备冷用 <=3秒、热用 <=1秒，进程 PSS 峰值增量 <=150MiB；APK 增量 <=35MiB。QR 真实 release 相机/相册、连续多分片、权限拒绝恢复、前后台、取消/重复不丢失不重复提交。16KB 包对齐和 ELF LOAD 对齐合格，所有支持 ABI 有完整引擎/模型。样本不足或无设备不得判质量 PASS。

保护：不覆盖根 PLAN/STATUS 或其他 task；不动旧 Git 存储、签名、iOS、正式名称及用户数据。旧 APK 先保存后构建。
