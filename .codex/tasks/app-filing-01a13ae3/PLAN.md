# App 备案资料准备

Task-ID: app-filing-01a13ae3
Owner-Session: 01a13ae3-a803-7752-8e40-495be978c12d

## 范围
以当前 local.sanqian.schedule 的实际产物和源码准备资料；核对 Android 签名、联网域名及 SDK、iOS 缺项。保留其他任务状态与用户修改，不提交外部备案、不修改产品代码。后续用户已明确授权生成 CSR、向 Apple 上传并创建 Apple Distribution；私钥留存钥匙串。

## 里程碑
1. 提取并交叉核对 Android release APK 与现用 keystore 的公开证书信息。
2. 核对实际联网配置及 SDK，区分源码发现、产物证据与未知项。
3. 核对本地 iOS 归档和签名，列出需开发者后台确认的缺项。
4. 交付可填写清单及公开证书材料，核验输出且清理临时文件。
