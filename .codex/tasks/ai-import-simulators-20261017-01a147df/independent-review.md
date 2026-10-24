# 独立交叉复核

结论：本轮独立交叉复核通过，未发现验收范围内的阻断缺陷。原双端截图识别、学校识别四条主路径及 iOS 教学班后缀修复结论保留。后续双端本机 OCR 加第二次 API 的真实流程、修复后的复核界面及保存数据库均已独立补验通过；“Live secondary paid OCR 尚未实测”的边界已关闭。截图及 OCR 结果均为 18 门、97 次、2 门待定，学校结果为 14 门、73 次、2 门待定；第一周周一均为 2026-09-07。

复核者：独立子 Agent `independent_review`。首轮源码范围以 TASK/preimages 为基线；后续 OCR 提示修复以 TASK/ocr-live/preimages 为基线，未把仓库中用户既有 dirty 当作本轮修改。本 Agent 未修改产品源码、未操作模拟器 UI、未使用凭据或调用付费 AI；实际双端操作和 API 请求由主 Agent 执行，本 Agent 独立核对来源、结果、运行页面和数据库。

此前 iOS 教学班别名补验沿用当时已加载修复的构建与运行进程；本次最终 OCR 补验由主 Agent 重新完成 iOS Xcode 构建和 Android debug APK 安装，未使用开发热重载作为最终验收。旧 UI 的 iOS OCR 请求及开发热重载失败后丢弃的未保存状态不计入最终通过。照片横向排版属于其他任务，本报告不对其作独立验收结论。

## 独立来源核对

先使用 view_image 逐张读取 `inputs/input-1.jpg` 至 `input-5.jpg`，再人工建立课程编码、教学班、教师、星期、周次、钟点及地点的独立对照，展开每个周次比较；没有把模型结果或主 Agent 的 verify_results.py 当作 oracle。

| 证据 | 独立结果 | 覆盖边界 |
|---|---|---|
| ios-photos-fixed.json | 18 门、97 次、2 门完整待定、11 门含教师；逐项相符 | 内容已核对，实际 UI 操作由主 Agent 执行 |
| android-photos-fixed.json | 18 门、97 次、2 门完整待定、11 门含教师；逐项相符 | 内容已核对，实际 UI 操作由主 Agent 执行 |
| ios-photos-final.json | 最新构建最终识别：18 门、97 次、2 门完整待定、11 门含教师；逐项相符 | 重新用独立人工图源标注核对，没有以另一份模型 JSON 充当 oracle |
| android-portal-extracted.txt + android-portal-fixed.json | 14 门、73 次、2 门完整待定、11 门含教师；逐项相符 | 使用学校网页单元格为来源，无新增付费请求 |
| android-portal-extracted-final.txt + android-portal-final.json | 最新版 Android：14 门、73 次、2 门完整待定、11 门含教师；逐项相符 | 独立从最新网页名单和网格解析身份、教师及逐周安排，不以其他模型 JSON 为 oracle |
| android-portal-final-warnings.json | 25 项候选、14 个不同课名；missing/extra 均为空，只保留 2 门待定提醒 | 候选名称均不含教学班后缀，因此不能证明 iOS 后缀修复的现场结果 |
| ios-portal-extracted.txt + ios-portal-baseline.json | 14 门、73 次，课程及安排相符 | 历史对照，不作为最新 iOS 学校路径证明 |
| ios-portal-extracted-latest.txt + ios-portal-fixed.json | 14 门、73 次、2 门完整待定、11 门含教师；逐项相符，重复待定说明已消失 | 独立逐行解析最新原始单元格比对，未调用模型 |
| ios-portal-extracted-final.txt + ios-portal-final.json | 最终 iOS：14 门、73 次、2 门完整待定、11 门含教师；逐项相符 | 从本次网页名单与网格独立核对课程身份、教师和逐周安排 |
| ios-portal-final-warnings.json | 38 项候选，其中 13 项带 -1 后缀、涉及 10 个不同课名；missing/extra 均为空，只保留 2 门待定提醒 | 每个后缀候选均见于原文，且匹配结果的 name + section；候选非空，实际覆盖了此次修复 |
| ios-portal-final-ui.json | 确认页新增 0 / 变更 0 / 移除 0 / 待定 2，随后出现保存成功提示 | 主 Agent 从真实运行页面采集的语义快照；本 Agent 独立核读，未亲自操作 UI |
| ios-school.db | 日期起点 2026-09-07；14 门、25 数据行、73 次、2 待定；身份、安排、时段映射与识别 JSON 一致 | 只读 SQLite，按起点展开日期为 2026-09-21 至 2027-01-01 |
| android-photos.db | 日期起点 2026-09-07；18 门、30 数据行、97 次、2 待定；保存字段及时间映射相符 | 只读 SQLite |
| android-final.db / photos | 同上；原始课程与已核对 JSON 一致 | 只读 SQLite |
| android-final.db / school-portal | 日期起点 2026-09-07；14 门、25 数据行、73 次、2 待定；保存字段及时间映射相符 | 只读 SQLite |
| android-final-latest.db | 照片表 18 门 / 30 行 / 97 次 / 2 待定，学校表 14 门 / 25 行 / 73 次 / 2 待定；两表无重复行，日期起点均为 2026-09-07 | 数据库字节与先前已核对的 android-final.db 一致；学校表逐行字段、时段和 original_course 与最新识别 JSON 相符 |
| ios-final.db / school-portal | 日期起点 2026-09-07；14 门、25 数据行、73 次、2 待定；保存字段、时段映射及原始课程相符 | 只读 SQLite |
| ios-final.db / photos | 日期起点 2026-09-07；18 门、30 数据行、97 次、2 待定；保存字段、时段映射及原始课程相符 | 只读 SQLite，按起点展开日期为 2026-09-21 至 2027-01-01 |
| ios-final-latest.db | 学校表 14 门 / 25 行 / 73 次 / 2 待定，照片表 18 门 / 30 行 / 97 次 / 2 待定；两表无重复行，日期起点均为 2026-09-07 | 两表逐行保存字段、时段及 original_course 分别匹配最终学校 / 截图 JSON；与先前已核对 ios-final.db 字节一致 |

关键样本已逐项检查：

- 英语保留第 3、4 周的第五会议室，第 6–10、12 周的 6310；没有填入第 5、11 周，两位教师“林敬和,刘先福”完整。
- 曲艺学导论保留第 4 周一、二、三及第 6 周一的 19:00–21:30 四次安排；第九节、晚上课和第十节的重复展示没有导致重复课次。
- 黑白摄影保留第 5 周六、日各上午和下午，共四次；没有出现误落到周五或仅保留半天。
- 导师课和思政大讲堂保留为空 meetings，数据库 weeks 为空、weekday/start period 为 0，没有编造日期。原始 source 中的 `label.teachtask...week.null` 没有变成上课周次。
- 名单图包含 14 个明确课程编码，两端结果保留字母和大小写；教学班为 1。
- 名单没有、网格明确存在的中国美学史专题、经济学、文旅投融资与艺术经济、艺术机构运营均保留；其课程编码未知，维持 null。中国美学史专题的两位教师完整。
- 五图与学校网页并非同一份完整课程集合。照片不包含教师的几门课保持 teacher=null；学校网页明确提供的方李莉、葛玉清、罗微、郑长铃仅出现在网页结果，没有以网页知识污染图片识别核对。

## 源码及回归

复核了两端 DeepSeekTimetableClient、Android SchoolPortalActivity、ScheduleImportDraft、ImportReviewView、SchoolAccountView、PhotoScheduleImportView 及本轮对应测试差异。

- 两端 imagePrompt、textPrompt、systemPrompt 去缩进后逐字一致。补充的是通用的名单与网格互补、周次/星期规则，没有硬编码本样本答案。
- 待定说明只在来源未给原因时补“安排待定”，已有来源说明不会无条件重复拼接。
- 原文星期检查只提示 AI 自己引用文本中的矛盾，不据模型引用改写课程日期；不能视为独立真值验证，也不能宣称覆盖一切周次错误。
- 课程重叠检查需要同星期、周次交集、完整钟点和严格时间重叠，不把相邻时段或不同周次判为冲突；只提示并保留双方。样本应产生四组重叠：中国美学史专题/非遗概论，经济学/艺术人类学，经济学/非遗保护理论，文旅投融资/非遗保护理论。
- 核对页与最终保存弹窗均显示 preparation warnings。周次显示压缩连续范围而保留跳周。第一周日期仍需用户选择，增加可访问按钮语义；2026-09-07 实际持久化核对通过双端两条路径。
- 学校账号文案区分 iOS 主动填入和 Android 尝试自动填入；图片页不再在已保存 Key 时仍要求先保存；辅助 OCR 文案明确需要再次发送及费用。
- Android 旧登录提示在页面开始导航时清除；自动填入成功后说明放在步骤引导区。
- 后续新增的候选覆盖修复（ScheduleImportDraft.dart:486）：仅在实际 section 非空并匹配时，把“课名-section”接受为该课程的来源候选；不改实际课名、identity、课程合并或数据。section 缺失和不同班次保留告警。两条新增回归覆盖匹配、未知和不同教学班，未发现阻断问题。

独立执行：

`flutter test test/Models/schedule_recognition_test.dart test/Pages/portal_ai_review_test.dart test/Utils/schedule_import_service_test.dart --reporter expanded`

结果：独立执行的 83 项全部通过，覆盖当时 `_selectFirstMonday` 与 `Semantics(button:true)` 所在版本；候选教学班别名修复是其后的新改动，两条新增回归已独立审阅，主 Agent 已报告更新后的 85 项及 Dart 分析通过，此处不把主 Agent 的执行描述成独立重复执行。`git diff --check` 在首次复核时无输出并成功退出。测试结果仅证明覆盖的 Dart 逻辑和组件场景，不替代原生登录/API/UI 实测。

## 最新 Android 补验

独立读取 `android-portal-extracted-final.txt` 的原始名单与网格：名单确定课程编码、课名、教学班、周次、星期与教室，网格补足教师和上午 / 下午 / 晚上的钟点。将来源与 `android-portal-final.json` 分别展开成逐周安排后逐项比较，14 门、73 次、2 门待定及 11 门教师均相符。英语跳周、黑白摄影四次安排、曲艺四次晚课和两门待定没有回归。

页面状态文件的 `expectedCourseNames` 非空，共 25 项、去重后 14 个名称；`missingCourses` 和 `extraCourses` 都为空，唯一提示是“有 2 门课程包含待定安排，缺失信息未自动补全，请核对。”这 25 项名称均无 `-1` 后缀。虽然网页网格原文有教学班后缀，本次实际覆盖检查的候选没有后缀，因此本批仅证明 Android 无回归，不能补足 iOS 后缀误报修复的现场证据。

只读检查 `android-final-latest.db`：`PRAGMA integrity_check` 为 ok；两张导入课表分别仍为 30 行与 25 行，没有完全重复的课程安排行。数据库与已独立复核过的 `android-final.db` 字节完全一致，学校表的身份、教师、周次、星期、教室、时段映射和每行 `original_course` 也逐项匹配最新识别 JSON；日期起点仍为 2026-09-07。主 Agent 报告真实保存确认显示“新增 0 / 变更 0 / 移除 0”；本 Agent 没有独立操作该保存弹窗，独立证据是保存后的数据库无增行、无内容变化及来源一致性。

## 最终 iOS 补验

独立从 `ios-portal-extracted-final.txt` 读取本次名单与网格，使用名单的课程编码、名称、班次和安排，以及网格提供的教师与时段，逐项比对 `ios-portal-final.json`。14 门课程、73 次上课、2 门完整待定和 11 门教师全部相符。英语未增加第 5 或 11 周；黑白摄影第 5 周六、日各上午 / 下午四次完整；曲艺第 4 周一、二、三和第 6 周一四次晚课完整；两门待定没有编造日期或重复说明。

实际页面状态 `ios-portal-final-warnings.json` 有 38 项非空候选，前 25 项与名单展开后的候选完全一致；另外 13 项带 `-1` 后缀，涉及 10 个不同课名。每一项后缀候选都在原始网页网格中找到，且与识别结果的课程名称和 `section=1` 唯一对应；这些候选不等于任何实际裸课名，证明本次确实覆盖了教学班别名匹配。页面 `missingCourses`、`extraCourses` 均为空，仅保留两门待定提醒，原来的教学班后缀漏课误报已消除。

`ios-portal-final-ui.json` 的真实运行页面语义快照显示确认页“新增 0 / 变更 0 / 移除 0 / 待定 2”，并保留同一待定提醒；后续序列显示“课表已保存，返回首页即可查看。”独立只读核对保存后的 `ios-final-latest.db`：`PRAGMA integrity_check` 为 ok，学校表 25 行 / 14 门 / 73 次，截图表 30 行 / 18 门 / 97 次，均保留 2 门待定且没有重复安排行。两表的课程身份、教师、周次、星期、教室、时段和每行 `original_course` 分别与最终学校 / 截图 JSON 完全一致；第一周周一均为 2026-09-07。数据库与先前已核对的 `ios-final.db` 字节完全一致，支持此次重复保存未增行、未改动课程内容。

## 双端真实 OCR 补验及提示修复

本次复核重新使用 view_image 读取全部五张原图，人工整理 18 门课的编码、教学班、教师、星期、周次、时段、教室和可见原文引用，独立展开 97 次上课。将该人工标注分别与 `ocr-live/ios-primary-final.json`、`ios-ocr-final.json`、`android-primary-final.json`、`android-ocr-final.json` 比较，四份均逐项相符；没有以首次模型结果或主 Agent 的校验脚本替代原图真值。14 门有明确课程编码，网格额外四门保持编码未知；11 门有图源教师，两位英语教师及两位中国美学史教师完整，图片未提供教师的课程没有从学校网页补入教师。

各安排的 sourceReference 与人工读取的名单或网格文字相符。iOS 的中国美学史引用将英文逗号改为中文逗号，两端 raw.sourceLine 的汇总长短也不同；这些差异不影响课程字段和安排，每个 meeting 仍有对应引用。两端 OCR 最终结果的 recognition 均为 `deepseek-ocr-review`，元数据均为 `ocrAttempted=true`、`imageCount=5`。英语跳周、黑白摄影四次安排、曲艺四次晚课、两门完整待定和网格额外四门均完整保留。独立从人工课次计算出四组重叠，与两端五条提示（四组重叠加两门待定）完全一致。

本 Agent 在 OCR 补验开始时发现并报告了确认页缺陷：只用新增课名判断完整，导致丢课、字段变化和时段减少时仍可能宣称课表完整，且采用后丢失提醒没有保留。主 Agent 随后修复，本 Agent 对照 `ocr-live/preimages/` 独立审阅：OCR 确认页现同时展示字段 / 安排差异、原有安排未保留提醒及 preparation warnings；采用后 `_reviewWarnings` 动态比较 `_beforeAI` 与当前草稿，在核对页和保存弹窗持续显示损失提醒；恢复原稿后清除这类差异提醒。采用前明确说明会替换草稿及手动修改，正式课表在确认保存后才改变。

独立执行 `flutter test test/Pages/portal_ai_review_test.dart --name 'OCR|photo anomaly|portal recheck|second|recheck' --reporter expanded`：8 项全部通过。损失回归实际覆盖教师变化、周六 3 次安排丢失、完整待定课丢失，并检查采用前、采用后、保存弹窗和恢复；取消 / 网络失败保留草稿、只发送一次及 portal recheck 场景也通过。主 Agent 另报告全部 33 项页面测试和分析通过；后续测试仅补 const、未改变行为，此处不把主 Agent 的执行当作独立重复执行。

最终真实 UI 的独立核读与图片查看结果如下：

| 路径 | 页面和保存证据 | 独立结果 |
|---|---|---|
| iOS OCR | ios-ocr-result.jpg、ios-ocr-result-ui.json 的顶部与滚动快照、ios-ocr-save-ui.json | 18 门 → 18 门；替换和恢复说明清楚，显示“本次复核未发现课程或安排变化，请继续核对原图”，无“已经很完整”文案。滚动后能读到全部五条提醒，保存确认保留全部提醒并显示新增 0 / 变更 0 / 移除 0 / 待定 2。保存后快照返回设置页；该快照未截到成功 toast，保存成功另由下述数据库与 OCR 原始记录确认 |
| Android OCR | android-ocr-result.png、android-ocr-result-ui.jsonl、android-ocr-confirm-ui.jsonl、android-ocr-saved-ui.jsonl | 同样 18 门 → 18 门，替换说明、无变化提示及五条提醒全部呈现；保存确认 0 / 0 / 0 / 待定 2；保存后明确采集到“课表已保存，返回首页即可查看。” |

该批真实样本中首次识别与 OCR 的课程业务字段及安排一致，因此现场验收覆盖的是“无业务变化但仍有待定 / 重叠提醒”的分支。丢课和字段损失分支由上述独立页面回归验证，没有把合成损失用例称为真实 API 返回。

两份最终数据库均以只读方式打开，`PRAGMA integrity_check` 均为 ok。逐行核对结果：

| 数据库 | 照片课表 | 学校课表 | 日期及原始记录 |
|---|---|---|---|
| ocr-live/ios-ocr-final.db | 30 行 / 18 门 / 97 次 / 2 待定，无重复 | 25 行 / 14 门 / 73 次 / 2 待定，无重复 | 两表起点 2026-09-07；照片每行 original_course 与 iOS 最终 OCR JSON 完全一致，学校原始记录与已验最终学校 JSON 完全一致 |
| ocr-live/android-ocr-final.db | 30 行 / 18 门 / 97 次 / 2 待定，无重复 | 25 行 / 14 门 / 73 次 / 2 待定，无重复 | 两表起点 2026-09-07；照片每行 original_course 与 Android 最终 OCR JSON 完全一致，学校原始记录与已验最终学校 JSON 完全一致 |

课程名、编码、教学班、教师、星期、周次、教室和时段映射全部匹配；待定行的 weeks=[]、weekday/start/time_count=0，没有编造日期。照片原始记录全部保留 `deepseek-ocr-review`，学校原始记录保持 `deepseek`。按起点展开日期仍为 2026-09-21 至 2027-01-01，这是数据库算术核对。新数据库因导入元数据刷新与上轮 final-latest.db 的字节不同，不沿用早先“数据库字节相同”的表述。

## 验收边界

双端四条主识别与保存路径、iOS 教学班后缀修复，以及双端 Live secondary paid OCR 的最终真实流程均已补验通过。主 Agent 报告并实际执行正常 UI 选五原图、首次识别、主动确认发送、本机 OCR 加第二次 API、采用和确认保存；本 Agent 独立检查留存原图、两次结果、实际页面、对应原生分支和最终 SQLite，没有再调用凭据或模型。两端原生 OCR 分支分别调用 Vision / ML Kit，随后把原图和 OCR 页传给 DeepSeek；本次检查的代码哈希与 source-fingerprints.json 一致。以上不把 recognition 标记、语义快照或测试单独当成真实 API 成功证明，也不声称核验了实际扣费金额。照片横向排版另由主 Agent 验收，不在本报告的独立复核范围内。

## 证据指纹

以下为本次读取时 SHA-256 前 16 位，便于防止后续文件变化导致结论漂移。

| 文件 | 指纹 |
|---|---|
| ios-photos-fixed.json | 877674c4809c8c5c |
| android-photos-fixed.json | 877674c4809c8c5c |
| android-portal-fixed.json | dfbf8f2333f77329 |
| ios-portal-baseline.json | ceba1dba92d93e09 |
| android-photos.db | 4cc505ce02bb512d |
| android-final.db | c09050caeee3b4cc |
| lib/Models/ScheduleImportDraft.dart（含候选教学班别名修复） | 41ddf6d40a3b3a75 |
| lib/Pages/Import/ImportReviewView.dart | b3043ea823798098 |
| ios/Runner/DeepSeekTimetableClient.swift | a69e50b1a18c7369 |
| android/app/src/main/kotlin/love/sanqian/schedule/DeepSeekTimetableClient.kt | 076582a8aefc044f |

补验新增指纹：

| 文件 | 指纹 |
|---|---|
| ios-portal-fixed.json | 64d9ec7ab92d99f7 |
| ios-portal-extracted-latest.txt | 112935467c210c56 |
| ios-school.db | a317839a4f9deea9 |
| test/Models/schedule_recognition_test.dart（两条新增回归） | 325a4f497c6dcf34 |

最终 iOS 截图与数据库补验指纹：

| 文件 | 指纹 |
|---|---|
| ios-photos-final.json | 58bde18a66e4af77 |
| ios-final.db | 0a588bffbbefbfa4 |

最新 Android 学校回归补验指纹：

| 文件 | 指纹 |
|---|---|
| android-portal-final.json | 64d9ec7ab92d99f7 |
| android-portal-extracted-final.txt | 498f0a82469edff1 |
| android-portal-final-warnings.json | 5b03dbf6279528c6 |
| android-final-latest.db | c09050caeee3b4cc |

最终 iOS 学校与教学班候选补验指纹：

| 文件 | 指纹 |
|---|---|
| ios-portal-extracted-final.txt | 914729228bcfc2f1 |
| ios-portal-final.json | 64d9ec7ab92d99f7 |
| ios-portal-final-warnings.json | 2e0eceadee4f1ad1 |
| ios-portal-final-ui.json | 231716d86ec287be |
| ios-final-latest.db | 0a588bffbbefbfa4 |

最终 OCR 实测证据指纹（此前各表保留为对应阶段的历史指纹）：

| 文件 | 指纹 |
|---|---|
| ocr-live/ios-primary-final.json | 58bde18a66e4af77 |
| ocr-live/ios-ocr-final.json | caf6108f45de0e09 |
| ocr-live/ios-ocr-metadata.json | 234f7b4aaa212367 |
| ocr-live/ios-ocr-result-ui.json | cf414e05dbcafa79 |
| ocr-live/ios-ocr-save-ui.json | 1eee7c41c6a4a7cd |
| ocr-live/ios-ocr-final.db | 9372e6f8861bee65 |
| ocr-live/ios-ocr-result.jpg | 56f319c51d722d95 |
| ocr-live/android-primary-final.json | 58bde18a66e4af77 |
| ocr-live/android-ocr-final.json | 7e3e39ad35ff9de5 |
| ocr-live/android-ocr-metadata.json | 234f7b4aaa212367 |
| ocr-live/android-ocr-result-ui.jsonl | ebfef39b6e688edc |
| ocr-live/android-ocr-confirm-ui.jsonl | fcb7fda5cf041d84 |
| ocr-live/android-ocr-saved-ui.jsonl | 82f3e24b179a51d9 |
| ocr-live/android-ocr-final.db | 07fa832bbe3a1889 |
| ocr-live/android-ocr-result.png | eb05dd1777624264 |
| ocr-live/source-fingerprints.json | 2d96b00eadd13a9e |

本次 OCR 提示修复及原生调用路径的最终代码指纹：

| 文件 | 指纹 |
|---|---|
| lib/Pages/Import/ImportReviewView.dart | 5b694149e3fcd1d3 |
| test/Pages/portal_ai_review_test.dart | f916fbe29b253f16 |
| ios/Runner/ScheduleImportPlugin.swift | 9c08777d8e0c1f37 |
| ios/Runner/DeepSeekTimetableClient.swift | a69e50b1a18c7369 |
| android/app/src/main/kotlin/love/sanqian/schedule/ScheduleImportPlugin.kt | ad51c45bea1277b6 |
| android/app/src/main/kotlin/love/sanqian/schedule/DeepSeekTimetableClient.kt | 076582a8aefc044f |
