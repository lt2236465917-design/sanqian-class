# iPhone 真机试用

App 名称为「三千上课」，图标已接入用户确认的黑白边牧定稿。这里准备的是主 App 的构建与签名流程；原始 Logo 保存在 `res/personal-icon.png`，不重新生成或修改图案。

## 已准备的工程

- 真机：`arm64`、`iphoneos`、Release；主 App 和所有嵌入 Framework 的最低版本均为 iOS 13。此配置覆盖 iPhone 12 起的系统范围，但不代表所有机型和旧系统已经实测。
- iOS 26 使用原生玻璃底栏；更早系统使用 Flutter 磨砂底栏。
- 模拟器保留原 Bundle ID，以保护已有数据；真机使用 `local.chaoxi.schedule`，已在本用户 Personal Team 完成签名；其他账号安装需配置其可用的唯一 ID。
- 已取消原作者 Team / 描述文件绑定，使用自动签名。主 App 不嵌入尚未验收的小组件，也不请求 App Groups，扩展源码保留待后续适配。
- 新增 `ChaoxiDevice` scheme，Run 使用 Release，便于签名安装后脱离 Xcode 冷启动。

## 先用普通 Apple ID 试用

1. 在 Xcode → Settings → Accounts 中自行登录 Apple Account。若团队显示 `Personal Team`，就是免费个人签名。无需向代理提供密码。
2. 用数据线连接 iPhone，解锁并信任这台 Mac；若 Xcode 提示，按手机指引开启 Developer Mode。2026-09-20 已配对 iPhone 15 Pro Max / iOS 18.6.2，并确认 Developer Mode 已开启、Xcode Personal Team 已登录。
3. 打开 `ios/Runner.xcworkspace`，选择 `ChaoxiDevice` scheme 和这台实际 iPhone。
4. Runner → Signing & Capabilities 中选择自己的 Team，保留 Automatically manage signing。真机 Bundle ID 通过 `ios/Flutter/PersonalDevice.local.xcconfig` 配置：复制同目录 `.example`，填写自己可用的 ID 和 Team ID；该本地配置已加入 Git 忽略。
5. Run。Xcode 完成签名和安装后，从手机桌面独立打开 App。首次使用从首页或设置导入内置截图课表，不需要登录学校网站。

Apple 官方说明：Personal Team 的描述文件签发后 7 天到期，需要重新构建安装；适合先试用。付费 Apple Developer Program 才能使用 TestFlight 等分发方式。见 [Apple 开发者账号与会员说明](https://developer.apple.com/support/compare-memberships/)。

## 构建与安装包的区别

在仓库根目录运行：

```sh
tool/flutterw build ios --release --no-codesign
```

上述 `--no-codesign` 命令产出的 `build/ios/iphoneos/Runner.app` 是**未签名真机版本**，用于确认 Release 编译与依赖；不能直接发到 iPhone 安装。模拟器的 `build/ios/iphonesimulator/Runner.app` 也不能装真机。

可安装版本需要有效签名和对应的分发条件。个人试用可以直接通过 Xcode 安装，无需先导出 IPA。后续若选 Ad Hoc IPA，需要付费开发者账号并将目标设备加入描述文件；若选 TestFlight，则需要上传 App Store Connect，属于另一个分发步骤。

## 真机验收时检查

- 首次导入 14 门课：12 门已排、2 门待定，课程时间和教室与截图一致。
- 开启飞行模式后关闭 Wi-Fi，退出并重新打开 App，查看日 / 周 / 月、课程详情和待定安排。
- 第 3 周英语在第五会议室，第 6 周在 6310；第 5 周周末摄影课程存在。
- 终止并重新打开 App，课程仍保留，默认回到当前日期；恢复网络后继续正常使用。

模拟器的网络故障注入只验证 App 主进程在 DNS / TCP / UDP 调用失败时的行为，不代替以上真机飞行模式验收。

## 2026-09-20 本机安装进度

「三千上课」已用 Personal Team 签名构建并安装到连接的 iPhone 15 Pro Max。当前 `build/ios/iphoneos/Runner.app` 是本次签名产物（并非上面的未签名构建），描述文件包含这台设备，到期北京时间 2026-09-27 21:20:45。

首次启动曾被 iOS 安全策略拦截；用户信任开发者证书后已正常运行。设置修复版也已原地更新：真机实测手动添加并重启保留、课表新建/切换/删除、二维码分享串往返导入、内置课表重复导入、深色持久化及开源许可。原 2 份课表、20 条课程记录保持，测试课表已清理，外观恢复跟随系统。

系统日历的真实权限弹窗、73 次课程写入/回读及重复导出去重已在专用 iPhone 16 模拟器通过；真机仅验证预览并取消，未向手机日历写入测试数据。真机摄像头识别二维码、系统相册选择二维码图片均已完成预览、导入和冷启动保存验证；普通课表截图 OCR 留待单独开发。真机飞行模式仍未验收。课表管理对勾与删除按钮已统一为 48 点居中区域，修复版已安装并在真机核对。完整设置结果见 [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)。

增量构建后需用 `codesign --verify --deep --strict build/ios/iphoneos/Runner.app` 核对完整签名。本次末次 Flutter 构建出现外层资源清单对 `App.framework/App` 的旧哈希；已用同一签名身份和原 entitlements 重新签署外层包，严格校验通过后安装，记录见 `settings-final-signature.log`。
