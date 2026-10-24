# 状态

Task-ID: app-filing-01a13ae3
Owner-Session: 01a13ae3-a803-7752-8e40-495be978c12d

- 当前阶段：Android 资料及 iOS 新分发证书准备完成；接入方式、最终发布包和 App Store Connect 记录待后续核对。
- 已确认工作目录：/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual。
- 根目录 PLAN.md / STATUS.md 及其他 .codex 状态属于既有工作，未读取为本任务状态、未覆盖。
- 用户现有 copyright-materials 修改保留。
- 未提交外部备案；iOS 开发者账号后台尚未核验。

## 里程碑 1 已验证
- Android APK 签名校验通过，包名 local.sanqian.schedule，版本 1.0.0 / 3。
- APK 证书 DER 与现用 keystore 导出的公开证书完全一致。已导出 RSA 公钥模数及证书 MD5；未导出私钥或密码。
- APK 与当前源码提交的构建对应关系尚未验证，联网审计须分别标注证据来源。

## 用户补充
- 阿里云服务器仅部署官网和下载页，无 App 后台接口。
- iOS 最终使用 Xinyu Li 团队 ZPAU8L65J4。
- 下一阶段：域名和 SDK 核对；不得将官网服务器伪填为 App 接口服务器。

## 里程碑 2 已验证
- 当前源码与 APK 静态字符串均发现 api.deepseek.com 和三个 zgysyjy.org.cn 学校域名。
- 扫描的当前源码及 APK dex/libapp 范围未发现 sanqianshangke.top；用户确认服务器仅官网和下载。尚无完整运行流量证据，不把静态列表当作完整联网清单。
- 离线 Gradle releaseRuntimeClasspath 解析成功：Google ML Kit 中文 OCR、mobile_scanner 间接引入 barcode-scanning 和 datatransport；DeepSeek 为 HTTP API 调用，不是嵌入式 SDK。
- 阿里云接入方式需针对无自建后台的实际架构确认，不能直接套用官网服务器；已保存官方资料链接用于交付。

## 里程碑 3 本地核对完成
- 本地 iOS 归档 Bundle ID 与用户确认一致，团队 Xinyu Li / ZPAU8L65J4；描述文件 get-task-allow=true，是开发签名。
- 当前钥匙串搜索列表未发现 Apple Distribution / iPhone Distribution 证书（以 JSON 实测为准）；不等于云端没有证书。
- 浏览器状态读取超时并重置，未完成 Apple 后台读取；不能确认账号会员、Identifiers 或 App Store Connect 记录。
- 下一步：完成清单，列出待用户/后台确认的接入方式和正式 iOS 证书，不创建或撤销证书。

## 里程碑 4 完成
- 已交付 备案资料/2026-10-14/三千上课-App备案填写清单.md 及 8 份公开/本地核验附件。
- 本轮资料准备完成；App 备案提交未执行，接入方式与 iOS 云端/最终证书确认仍待后续处理。
- Chrome 打开 Apple 证书页的重试返回 nodeRepl.fetch request failed；未更换浏览器后端，也未声称已读取账号。
- 没有生成或复制私钥、密码、完整描述文件；没有新建临时文件。

## 交付核验
- 清单内公钥与导出模数一致，证书 DER 的 MD5 与填写值一致，APK SHA-256 与当前文件一致。
- 共 9 个交付文件，未发现私钥导出标记。Git 已跟踪修改名单仍为用户既有 copyright-materials 文件；本轮仅新增备案资料及专属任务状态。

## 用户登录后的核对尝试
- 用户已登录，提供的当前浏览器页面是 Apple Certificates 列表。
- 使用当前 in-app browser 的实际 URL 读取页面，cua.getTab 在 30 秒后超时并重置。未读取到页面内容。
- 这是浏览器控制连接故障，不能推断 Apple 登录失败、证书不存在或账号异常；所有云端核验状态仍为 NOT_VERIFIED。
- 可继续通过用户提供的证书列表截图核对；未换后端、未创建或撤销证书。

## Apple 证书列表截图证据
- 用户截图显示团队 Xinyu Li / ZPAU8L65J4。
- 云端证书列表包含 Development 与 Distribution Managed 两张证书，平台 All，均显示到期日 2027/09/30。
- 这证明云端存在托管分发证书，但尚未查看证书详情、下载证书或提取公钥/SHA-1；也尚未核对 Identifiers/Profiles 中 Bundle ID 的关联。

## Apple 分发证书详情截图证据
- 用户截图确认 Distribution Managed 证书：名称 Xinyu Li，创建者 Xinyu Li (Lxy013328@163.com)，到期 2027/09/30，自动轮换日期 2027/07/02。
- 该详情页 Download 按钮呈禁用状态；尚未获得可下载 .cer，因此仍无法提取该托管证书的公钥/SHA-1。未点击 Revoke 或 Rotate。

## 结论：Distribution Managed 不可下载
- 截图显示 Download 灰色，证书类型为 Distribution Managed；这是云托管分发证书，当前不能下载 .cer，不能直接从该页面提取备案公钥/SHA-1。
- 未点击 Revoke、Rotate 或创建新证书。建议使用同团队的普通 Apple Distribution 证书获取可下载 .cer；若最终采用 Xcode Cloud 云签名，则应从实际云签名交付产物提取证书信息，并与备案字段保持一致。

## 新授权与 CSR
- 用户明确授权本机生成 CSR、上传 Apple 创建 Apple Distribution，随后明确账号邮箱 lxy013328@163.com。此前不创建新证书的范围限制被本次具体授权更新。
- 通过钥匙串证书助理生成 CSR，界面显示已创建；路径 /Users/zhuanzmima0000/Documents/Sanqian-Apple-Distribution-20261014.certSigningRequest。私钥未导出。
- 正在继续 Apple 网页申请，尚未证明新证书创建成功。

## 已验证：新 Apple Distribution 创建与安装
- 用户指定 Tabbit；CLI 实例 3A0B7C47540D54EB，原有登录团队 ZPAU8L65J4。
- CSR 上传后创建证书 6SXD8QVGQF；页面显示 Distribution，2027/10/14 到期。首次等待误把 Download 当 button 超时；读取实际页面确认创建成功并按 link 下载，未重复创建。
- .cer 下载成功，证书主题 Apple Distribution: Xinyu Li (ZPAU8L65J4)。SHA-1: 201aac298a78d50039b6a93190aff35ff9d16aba。
- 证书公钥与 CSR 完全一致；导入登录钥匙串后 security find-identity 列出此有效签名身份，确认私钥配对。私钥未导出。
- Apple Identifiers 页面已核验 local.sanqian.schedule 及其 ScheduleWidgetExtension；App Store Connect 仍未核验。
- 已更新备案填写清单并新增公开证书、公钥 PEM/hex/模数和 JSON；现有托管证书未撤销。最终发布包尚未使用新证书重新签名。
