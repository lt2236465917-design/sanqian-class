# 三千上课当前 App

- 用户于 2026-10-14 确认本目录 `/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual` 为当前 App 开发、打包和备案信息来源。
- Android applicationId 与上架用的 iOS Bundle ID 为 `love.sanqian.schedule`。2026-10-16 起，本机 `ios/Flutter/PersonalDevice.local.xcconfig` 的真机 ID 暂为 `love.sanqian.dev`，真机签名不带 App Group，供李滔的免费 Personal Team 安装。不要把 `love.sanqian.schedule` 或 `group.love.sanqian.schedule` 交给免费团队或旧团队 ZPAU8L65J4。付费团队通过后，真机 ID 和 entitlements 再改回上架配置。旧的 `local.sanqian.schedule` 留在李新宇的 Apple 团队。
- Android release 签名从本地 `android/key.properties` 读取。备案公钥和证书指纹应从实际交付的 release APK 提取并与签名配置核对，不从旧副本或 debug 包提取。
- 已核对的 iOS 归档使用开发描述文件；正式分发证书及 App Store Connect 标识尚未核验，不能将开发签名视为正式上架签名。
- 本目录是 linked worktree，共用 Git 存储位于 `/Users/zhuanzmima0000/Desktop/课表/NJU-Class-Shedule-Flutter/.git`。在完成存储迁移并验证前须保留该旧目录。
