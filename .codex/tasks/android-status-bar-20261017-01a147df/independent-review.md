# Android 状态栏独立验收

结论：本次“时间和状态图标只显示上半截”是隔离 Android 模拟器的 SystemUI 窗口状态异常。重启模拟器后，同一个已安装 App 的冷启动、边牧开屏动画、首页、设置页均未复现。当前证据下无需修改 App 代码。

复核者：独立子 Agent `independent_review`。设备仅限 `emulator-5556`。本轮没有修改产品代码、重新安装 App、清除数据、改系统设置或调用 AI，也没有操作 iOS。

## 归因证据

- 主 Agent 留下的 before-app.png、before-launcher.png、before-system-settings.png 均已亲自查看；三种界面的时间、网络和电量图标都在同一水平线被裁掉下半部分。仅 App 内容不同，裁切形态一致。
- before-window.txt 的 StatusBar 窗口明确属于 `com.android.systemui`，Requested height 和 frame bottom 都是 63 像素。
- after-reboot-window.txt 中同一类窗口高度为 128 像素；after-reboot-launcher.png 图标完整。
- 独立冷启动 App 之后，首页及设置页 dumpsys 再次确认 SystemUI 的 StatusBar frame 为 `[0,0][1080,128]`，没有被 App 改回 63。
- 独立查询当前 `android:dimen/status_bar_height` 返回 `128.0px`。这与恢复后的真实窗口一致。
- App 安装信息：versionName 1.0.0、versionCode 1、targetSdk 36；lastUpdateTime 为 2026-10-17 12:02:37。本轮独立验收未安装任何新包。

## 实际运行验收

先 force-stop 三千上课，再从桌面冷启动；am start -W 回报 `LaunchState: COLD`。录制 12 秒原始设备视频，按原分辨率 1080×2400 解码抽帧，随后实际点开 App 设置页。

| 阶段 | 结果 | 证据 |
|---|---|---|
| 启动前桌面 | 时间及右侧图标完整 | independent-before-launch.png |
| 原生启动过渡 | 时间、网络、电量完整，无水平裁切 | independent-launch-1s.png；视频 1–4 秒也已抽帧查看 |
| 边牧开屏动画 | 时间、网络、电量完整；两帧角色姿态不同，确认不是静态配置代替运行 | independent-launch-5s.png、independent-launch-8s.png |
| 首页 | 状态栏完整，App 标题在其下方 | independent-home.png、independent-home-window.txt |
| 设置页 | 状态栏完整，返回按钮及标题无重叠 | independent-settings.png、independent-settings-window.txt |

完整视频：independent-cold-launch.mp4。冷启动命令结果：independent-cold-launch.txt。控件证据：independent-home-ui.xml、independent-settings-ui.xml。

本轮未发现需要修复的 App 状态栏缺陷，不建议为此增加固定顶部 padding 或变更全屏设置。此前为何形成错误的 SystemUI 窗口高度，未进一步追溯；本结论覆盖本次隔离模拟器和已安装版本，不扩大为所有 Android 真机的通用证明。

设备内本轮临时录屏已删除，本地保留完整视频及必要帧作为验收证据。当前 App 停留设置页，已交还 emulator-5556 操作权。

## 本次证据 SHA-256 前 16 位

- independent-cold-launch.mp4: 350e665bf0516858
- independent-launch-1s.png: a7a71a128407f7e5
- independent-launch-5s.png: 85c6bbc22fb368a4
- independent-launch-8s.png: aef6884978e64f4a
- independent-home.png: cf5527642ad506b0
- independent-settings.png: 1ca5e2a5a35f6693
- independent-home-window.txt: 19c3ac1ac0018e9c
- independent-settings-window.txt: 19c3ac1ac0018e9c
