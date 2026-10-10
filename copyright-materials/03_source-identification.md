# 03 源程序鉴别材料

## 官网规则

官网[所需文件](https://www.ccopyright.com.cn/index.php?optionid=1080)给出一般交存规则：程序前、后各连续 30 页；整个程序不足 60 页时提交全文；通常每页不少于 50 行。[问题问答](https://www.ccopyright.com.cn/index.php?optionid=1087)要求页眉建议标注软件名称和版本号，右上角标页码，源程序正文从第 1 页编到第 60 页。版本号要与申请表一致。

## 本次生成口径

`scripts/generate_materials.py` 从 Git 跟踪的业务源文件抽取并拼接文件边界注释，排除并脱敏：

- `test/`、`src/test/`、`*Tests.swift`、`reference/`、`build/`、`.dart_tool/`、生成目录和 mock 文件；
- `res/schedules/zgysyjy_2026_fall.json` 等真实课程 fixture；
- 学校专名、学校门户域名和源码中的课程示例会替换为 `[已脱敏...]` 占位；实际替换规则记录在 `source-selection-manifest.json`；
- `LICENSE`、锁文件、签名/本机配置和密钥文件；
- 非 Dart/Swift/Kotlin/Java/ETS 源文件。

生成结果取拼接源程序的前 30 页与后 30 页，每页 50 行，形成 60 页 HTML。文件清单和行数见 `generated/source-selection-manifest.json`，结构校验见 `generated/validation-report.json`。

## 生成文件

- `generated/source-identification-material.html`：可用浏览器打印为 A4 PDF 的草稿。
- 页眉默认是 `三千上课 V1.0 · 源程序鉴别材料（草稿）`；`V1.0` 是占位值，版本统一后必须重生成。
- 页码在每页右上位置显示为 `页码 n/60`；浏览器打印前应关闭浏览器自己的页眉页脚，避免增加官网未要求的浏览器信息。

## 必须人工复核

1. 逐页检查是否意外包含真实课程、教师、教室、学号、账号、密码、API key、签名或本机路径。
2. 检查源码选页是否能代表申请的软件版本；如用户采用其他代码口径，修改脚本排除规则后重新生成并保留清单。
3. 检查 `wheretosleepinnju`、`NJU`、`chaoxi` 等出现位置：来源链接和上游兼容通道可保留，但用户可见旧品牌应剔除或说明。
4. 检查 Android manifest 中注释掉的旧 Umeng URI，不要把它作为当前功能或品牌提交。
5. 由申请人最终确认页眉软件名/版本号、页码、行数和 PDF 内容。

## 本地命令

```bash
python3 copyright-materials/scripts/generate_materials.py --version V1.0
python3 -m json.tool copyright-materials/generated/validation-report.json >/dev/null
git diff --check -- copyright-materials
```

结构检查通过不等于官网审查通过；它只证明生成的 HTML 具有预期页数、最低行数、页眉页脚页码和本脚本的敏感模式扫描结果。当前环境未验证浏览器打印后的物理 PDF 页数，提交前必须打印为 PDF 后逐页核对。
