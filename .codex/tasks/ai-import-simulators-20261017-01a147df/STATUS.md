# AI 导入实测状态

Task-ID: ai-import-simulators-20261017-01a147df
Owner-Session: 01a147df-9a29-7e83-86c9-b21e4decd917

状态：部分完成，iOS 收尾 UI 操作等待用户解锁 Mac；不能标为双端完整验收通过。2026-10-17 压缩后已再次核验本任务归属，没有读取其他任务状态作为本轮状态。

## 现场与授权
- App：/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual，HEAD db31944caa515abe7e6f3ff1fdd805c363ebc372，包名 love.sanqian.schedule。
- baseline-status.bin、baseline-hashes.json、preimages/ 保留本轮前用户改动。没有提交、推送或发布。
- 用户明确授权学校登录、API 识别、双端验证码，以及独立子 Agent 复核。凭据不写入报告或源码。
- 五张原图已从本轮附件原数据恢复至 inputs/input-1.jpg 至 input-5.jpg，已亲自查看并导入双端相册。
- iOS：EF43A038-4E4B-417D-A813-E2404D1220FD，iOS 26.5，最新正常构建成功并启动，最近 PID 57710。当前停在学校门户登录页，未填验证码。
- Android：本轮隔离 AVD sanqian_ai_01a147df，emulator-5556。用户原 emulator-5554 未卸载或变更数据。

## 已修复
1. 双端提示词补充名单与网格教师互补，保留多位教师；逐条区分数字周次和汉字星期；完整名单不因网格切片或汇总行重复增加，网格独有课程仍保留。
2. 待定课程已有原因时不再重复追加“安排待定”。
3. 检测同周同时段课程重叠，以及 AI 自己引用原文中的星期矛盾；仅提醒，不擅自删改安排。核对页和最终保存确认均显示提醒。
4. 澄清学期名称、第一周周一、保存目标、周次与星期展示、已保存 Key 状态、本机文字识别辅助复核及再次调用费用。
5. 学校账号支持学号/手机号/用户名的说明；区分 iOS 手动填入和 Android 尝试自动填写。
6. Android 登录后清除过期红色状态。已重新真实登录回归：进入工作台后指南更新、无过期提示。
7. 第一周日期控件增加按钮语义；已随双端正常构建安装，组件测试通过，未声明 VoiceOver/TalkBack 人工验收。

产品变更共7个文件：两端 DeepSeekTimetableClient、Android SchoolPortalActivity、ScheduleImportDraft、ImportReviewView、PhotoScheduleImportView、SchoolAccountView；另外更新2个相关测试。按 preimages 核对本轮差异，保留用户原改动。

## 验证矩阵
| 路径 | iOS | Android |
| --- | --- | --- |
| 五图真实 AI 识别 | 最新提示词通过：18门、97次、2待定、11门教师 | 最新提示词通过：18门、97次、2待定、11门教师 |
| 学校登录/网页读取/AI | 初轮14门73次通过；最新提示词学校回归待补 | 最新提示词通过：14门、73次、2待定、11门教师 |
| 照片按2026-09-07保存 | 待执行；重建后旧review状态丢失 | UI保存与SQLite全字段核对通过 |
| 学校按2026-09-07保存 | 待执行 | UI保存与SQLite全字段核对通过 |
| 独立交叉检验 | 照片JSON/原图通过；最新学校及保存证据待补 | 两条JSON/原始资料/最终数据库通过 |

- 五图集合：名单14门，网格额外4门。联合18门97次符合原图；网页14门73次。图片中冲突课程保留并提醒核对。
- android-final.db：照片表id2，30数据行；学校表id3，25数据行。起点均2026-09-07，实际课次日期2026-09-21至2027-01-01，没有日期偏移；2门完整待定不排入日历。
- 最新 ImportReviewView（SHA-256前缀 b3043ea823798098）的83项相关Flutter测试由独立Agent跑通；主Agent再次分析本轮6个Dart文件，无问题。
- Android原生 DeepSeekParseTest/DeepSeekOcrReviewTest 通过；iOS原生离线100断言通过；双端正常构建通过。自动检查仅辅助真实模拟器/API证据。
- 没有开展本机OCR二次付费复核的真实API验收，不将其标为已实测。

## 证据
- 通过：ios-photos-fixed.json、android-photos-fixed.json、android-portal-fixed.json。
- 学校来源：ios-portal-extracted.txt、android-portal-extracted.txt；iOS旧结果 ios-portal-baseline.json。
- 失败留证：android-photos-baseline.json（漏教师），两端 photos-attempt1.json（第6周周一误成周末）。
- 数据库：android-photos.db、android-final.db。
- 人工来源校验 verify_results.py；数据库只读校验 verify_saved.py；脱敏汇总 verification-results.json。
- 独立子Agent /root/independent_review 已完成本阶段复核，未发现本轮阻断缺陷；independent-review.md 明确iOS缺口。它未操作模拟器或调用付费API。

## 阻碍与继续入口
- CUA确认Mac锁屏且自动解锁失败，已异步请求手动解锁，尚无回复。不要重复询问验证码授权。Xcode/ADB/源码工作不受锁屏影响。
- iOS验证码表单及系统图片选择器无法通过当前Xcode可点击语义快照完成，需CUA；不能用注入代替真实流程。
- 解锁后先继续iOS学校登录（验证码已授权）→研究生综合管理→我的课表→读取并识别；保存 ios-portal-fixed.json，对原文核对后以2026 Fall、2026-09-07保存。
- 再从相册选择五图，真实识别核对后以同学期日期保存；旧照片识别JSON仍可作为已通过内容证据。
- 取得iOS数据容器，SQLite只读备份为 ios-final.db；执行两个校验脚本，再followup_task同一独立Agent追加复核。
- Xcode默认workspace/scheme已验证：ios/Runner.xcworkspace、Runner、Debug、上述simulator、build/ai-import-derived、CODE_SIGN_IDENTITY=-、CODE_SIGNING_ALLOWED=YES。没有新源码修改不必重建。
- 不再尝试Flutter attach热重载。之前构造函数增量失配已通过正常构建恢复。本轮旧attach进程、无用attach日志、Swift临时二进制及Python cache已清理；原图、真实结果、数据库、preimages和有用失败证据保留。
