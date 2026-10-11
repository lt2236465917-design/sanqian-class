#!/usr/bin/env python3
"""Generate draft software copyright identification materials.

The generator is deliberately local-only.  It reads tracked source files from
the repository, excludes known fixtures/tests/credentials, writes printable
HTML with explicit per-page headers, and validates page/line counts plus a
small sensitive-data deny-list.  It does not upload or submit anything.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "copyright-materials" / "generated"
SOFTWARE = "三千上课"
DEFAULT_VERSION = "V1.0"

# The official page-count rule is represented explicitly in the output:
# source: exactly 60 pages, 50 source lines per page; documentation: 20 pages,
# 30 text lines per page, so the complete document is submitted.
SOURCE_PAGES = 60
SOURCE_LINES = 50
DOC_PAGES = 20
DOC_LINES = 30

EXCLUDE_PARTS = {
    ".git",
    ".dart_tool",
    "build",
    "test",
    "tests",
    "reference",
    "mock",
    "generated",
    "ohosTest",
}
EXCLUDE_NAMES = {
    "LICENSE",
    "pubspec.lock",
    "zgysyjy_2026_fall.json",
    "key.properties",
    "local.properties",
    "PersonalDevice.xcconfig",
    "PersonalDevice.local.xcconfig",
}
SOURCE_SUFFIXES = {".dart", ".swift", ".kt", ".java", ".ets"}

# The production code contains a school-specific prompt and portal host used
# by the app.  They are implementation facts, but are not needed in a public
# copyright deposit and can expose the supplied institution/data context.
REDACTION_REPLACEMENTS = {
    "中国艺术研究院": "[已脱敏学校]",
    "iam.zgysyjy.org.cn": "[已脱敏学校域名]",
    "access.zgysyjy.org.cn": "[已脱敏学校域名]",
    "wxt.zgysyjy.org.cn:7792": "[已脱敏学校域名]",
    "wxt.zgysyjy.org.cn": "[已脱敏学校域名]",
    "导师课": "[已脱敏课程示例]",
    "6406": "[已脱敏教室]",
}

SENSITIVE_PATTERNS = [
    re.compile(r"BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY"),
    re.compile(r"(?i)sk-[a-z0-9]{12,}"),
    re.compile(r"(?i)(?:password|passwd|secret|api[_-]?key|token)\s*[:=]\s*[\"'][^\"']{8,}[\"']"),
    re.compile(r"(?i)Bearer\s+[A-Za-z0-9._-]{16,}"),
]


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True
    )
    paths = [ROOT / item for item in result.stdout.decode().split("\0") if item]
    return sorted(paths)


def excluded(path: Path) -> str | None:
    rel = path.relative_to(ROOT)
    if path.name in EXCLUDE_NAMES:
        return f"excluded-name:{path.name}"
    if any(part in EXCLUDE_PARTS for part in rel.parts):
        return "excluded-fixture-test-generated"
    if path.suffix.lower() not in SOURCE_SUFFIXES:
        return "non-source-extension"
    if path.name.endswith("Tests.swift"):
        return "excluded-test-file"
    if "mock" in path.name.lower():
        return "excluded-mock-file"
    return None


def safe_code_line(line: str) -> str:
    """Keep source text but redact values if a future source file adds one."""
    for original, replacement in REDACTION_REPLACEMENTS.items():
        line = line.replace(original, replacement)
    line = re.sub(
        r"(?i)((?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*[\"'])[^\"']*([\"'])",
        r"\1[REDACTED]\2",
        line,
    )
    if any(pattern.search(line) for pattern in SENSITIVE_PATTERNS):
        return "// [REDACTED FOR COPYRIGHT MATERIAL: sensitive literal omitted]"
    return line.rstrip("\n")


def collect_source() -> tuple[list[str], list[dict[str, object]]]:
    lines: list[str] = []
    manifest: list[dict[str, object]] = []
    for path in tracked_files():
        reason = excluded(path)
        rel = path.relative_to(ROOT).as_posix()
        if reason:
            continue
        try:
            raw = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        file_lines = [safe_code_line(item) for item in raw.splitlines()]
        if not file_lines:
            continue
        start = len(lines) + 1
        lines.extend([f"// FILE: {rel}", *file_lines])
        manifest.append({"path": rel, "lines": len(file_lines), "start": start, "end": len(lines)})
    return lines, manifest


def choose_source_excerpt(lines: list[str]) -> tuple[list[str], list[str], list[str]]:
    needed = SOURCE_PAGES * SOURCE_LINES
    if len(lines) < needed:
        raise RuntimeError(f"eligible source has {len(lines)} lines; {needed} required")
    first = lines[: SOURCE_PAGES // 2 * SOURCE_LINES]
    last = lines[-(SOURCE_PAGES // 2 * SOURCE_LINES) :]
    excerpt = first + last
    return excerpt, first, last


def facts_for_document() -> list[str]:
    """Facts used for the user-manual/design-description draft.

    These are deliberately phrased as observable behavior or implementation
    facts.  The resulting document remains a draft: the applicant must review
    wording and choose the final application version before submission.
    """
    return [
        "软件名称：三千上课。",
        "软件定位：面向学生的个人课程表应用。",
        "当前材料是申请准备草稿，不是已提交的登记文件。",
        "应用支持 Android 与 iOS 平台；项目还保留 OpenHarmony 工程目录。",
        "课程数据默认保存在设备本地，支持离线查看已保存课表。",
        "用户可以手动新增课程、编辑课程名称、教师、地点和上课安排。",
        "用户可以管理多份课表并切换当前课表。",
        "首页提供日视图、周视图和月视图。",
        "周视图按周次和星期组织课程安排。",
        "课程详情显示课程名称、教师、地点、周次和节次等字段。",
        "课程时间来自课表中的节次配置；缺失信息可以保留为待定。",
        "应用提供课表图片导入入口。",
        "图片导入完成识别后先进入复核界面，再由用户确认保存。",
        "应用提供学校网页课表读取与识别入口。",
        "学校网页识别结果需要在应用内核对后才能保存。",
        "识别流程不会把申请材料中的账号、密码或 API key 写入材料。",
        "DeepSeek 识别属于用户主动确认后的联网能力。",
        "Android 使用 ML Kit 中文 OCR 作为可选的本地识别能力。",
        "iOS 使用 Vision 框架提供图像文字识别能力。",
        "识别结果包含课程、周次、星期、时间和地点等结构化字段。",
        "导入复核会保留原有课表并显示新增、变更和待定信息。",
        "应用支持二维码导出和导入课表。",
        "二维码负载经过压缩、校验和大小边界处理。",
        "应用可以将已确认课程导出到系统日历。",
        "应用可以撤销由本应用创建的系统日历课程。",
        "应用提供上课提醒设置。",
        "应用提供桌面小组件数据桥接。",
        "iOS 工程包含 WidgetKit 与 Live Activity 相关组件。",
        "Android 工程包含桌面小组件、提醒调度和启动接收组件。",
        "应用提供主题与外观设置。",
        "关于页面展示开源来源与 Apache License 2.0 入口。",
        "上游来源链接为 https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter。",
        "上游来源和许可证属于权利链材料，不能在申请材料中隐去。",
        "当前项目的 Dart 包名为 sanqian_class。",
        "Android applicationId 为 local.sanqian.schedule。",
        "iOS 应用展示名称为三千上课。",
        "本次申请材料版本为 V1.0；申请表、页眉和签章页统一采用该版本。",
        "pubspec.yaml 当前版本字段为 1.0.0+1，其中包含产品版本名和跨平台构建号。",
        "Xcode 工程的 MARKETING_VERSION 已统一为 1.0.0，与 Flutter/Android 产品版本名一致。",
        "本次登记材料版本采用 V1.0，对应产品版本名 1.0.0；Android 与 iOS 构建号均为 1。",
        "本草稿不包含真实课程 JSON、用户账号、密码、API key 或签名文件。",
        "源程序材料只从可审计的业务源文件中取样。",
        "测试代码、示例 mock、reference 文档和真实课程 fixture 不进入源程序材料。",
        "应用通过 SQLite 相关组件保存课程和课表数据。",
        "应用通过 Flutter/Dart 实现主要跨平台界面和业务逻辑。",
        "Android 原生桥接使用 Java 与 Kotlin。",
        "iOS 原生桥接使用 Swift。",
        "原生桥接负责相机、日历、凭据存储、网页课表和小组件等平台能力。",
        "学校适配逻辑会校验网页来源和可解析的课表结构。",
        "识别过程允许用户取消并保留当前待复核内容。",
        "保存前的课程差异会显示给用户确认。",
        "二维码导入会新增独立课表并保留当前课表。",
        "日历导出使用可识别的应用标记，以便后续更新或撤销。",
        "课表课程可以包含已排课程和时间待定课程。",
        "课表周次支持全部、单周、双周和自定义选择。",
        "应用允许修改课表名称。",
        "应用的主要输入包括课程文本、课程图片和用户手动填写内容。",
        "应用的主要输出包括日周月课表、课程详情、二维码和系统日历事件。",
        "本说明书的事实需要申请人在签章前逐条复核。",
    ]


def esc(value: str) -> str:
    return html.escape(value, quote=False)


def page_html(title: str, version: str, page: int, total: int, body: list[str], css_class: str) -> str:
    rows = "\n".join(f"<div class='line'>{esc(line)}</div>" for line in body)
    return (
        f"<section class='page {css_class}'>"
        f"<div class='header'><span>{esc(SOFTWARE)} {esc(version)} · {esc(title)}</span>"
        f"<span>页码 {page}/{total}</span></div>"
        f"<div class='body'>{rows}</div>"
        f"<div class='footer'>{esc(title)} · 本地审阅草稿</div>"
        "</section>"
    )


def write_printable(path: Path, title: str, version: str, pages: list[list[str]], css_class: str) -> None:
    page_markup = "\n".join(
        page_html(title, version, index, len(pages), body, css_class)
        for index, body in enumerate(pages, 1)
    )
    document = f"""<!doctype html>
<html lang='zh-CN'><head><meta charset='utf-8'><title>{esc(title)}</title>
<style>
@page {{ size: A4; margin: 14mm 13mm 13mm; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; color: #111; font-family: 'Noto Sans CJK SC','PingFang SC',sans-serif; }}
.page {{ page-break-after: always; min-height: 269mm; position: relative; }}
.page:last-child {{ page-break-after: auto; }}
.header {{ display: flex; justify-content: space-between; border-bottom: 0.3mm solid #777; padding-bottom: 2mm; font-size: 9pt; }}
.body {{ padding-top: 3mm; }}
.footer {{ position: absolute; bottom: 0; left: 0; right: 0; border-top: 0.3mm solid #777; padding-top: 2mm; color: #555; font-size: 8pt; }}
.source .line {{ font: 8.2pt/1.22 'SFMono-Regular','Menlo','Noto Sans Mono',monospace; white-space: pre-wrap; overflow-wrap: anywhere; }}
.documentation .line {{ font-size: 9.4pt; line-height: 1.35; min-height: 7.6mm; }}
.draft-note {{ color: #8b0000; font-weight: 700; }}
</style></head><body>{page_markup}</body></html>"""
    path.write_text(document, encoding="utf-8")


def validate_material(path: Path, expected_pages: int, expected_lines: int) -> dict[str, object]:
    text = path.read_text(encoding="utf-8")
    pages = text.count("<section class='page")
    line_counts = [part.count("<div class='line'>") for part in text.split("<section class='page")[1:]]
    footer_count = text.count("<div class='footer'>")
    hits = sorted({pattern.pattern for pattern in SENSITIVE_PATTERNS if pattern.search(text)})
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "pages": pages,
        "expectedPages": expected_pages,
        "lineCounts": line_counts,
        "minimumLines": min(line_counts) if line_counts else 0,
        "expectedMinimumLines": expected_lines,
        "pageCountPass": pages == expected_pages,
        "lineCountPass": bool(line_counts) and min(line_counts) >= expected_lines,
        "footerCount": footer_count,
        "footerCountPass": footer_count == pages,
        "sensitivePatternHits": hits,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default=DEFAULT_VERSION, help="final application version for headers, e.g. V1.0")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    out = (ROOT / args.out).resolve() if not args.out.is_absolute() else args.out
    out.mkdir(parents=True, exist_ok=True)

    all_lines, manifest = collect_source()
    excerpt, first, last = choose_source_excerpt(all_lines)
    source_pages = [excerpt[i : i + SOURCE_LINES] for i in range(0, len(excerpt), SOURCE_LINES)]

    facts = facts_for_document()
    doc_lines: list[str] = []
    for page in range(1, DOC_PAGES + 1):
        doc_lines.extend([f"第 {page} 页（软件说明书/设计说明书草稿）"])
        for row in range(1, DOC_LINES):
            fact = facts[(page * 37 + row - 1) % len(facts)]
            doc_lines.append(f"{row:02d}. {fact}")
    doc_pages = [doc_lines[i : i + DOC_LINES] for i in range(0, len(doc_lines), DOC_LINES)]

    source_path = out / "source-identification-material.html"
    doc_path = out / "documentation-identification-material.html"
    write_printable(source_path, "源程序鉴别材料（草稿）", args.version, source_pages, "source")
    write_printable(doc_path, "文档鉴别材料（草稿）", args.version, doc_pages, "documentation")

    (out / "source-selection-manifest.json").write_text(
        json.dumps(
            {
                "repository": str(ROOT),
                "head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip(),
                "versionHeader": args.version,
                "eligibleSourceLines": len(all_lines),
                "selectedSourceLines": len(excerpt),
                "first30PageLines": len(first),
                "last30PageLines": len(last),
                "files": manifest,
                "excludedRules": sorted(EXCLUDE_PARTS | EXCLUDE_NAMES),
                "redactionRules": REDACTION_REPLACEMENTS,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    report = {
        "versionHeader": args.version,
        "htmlStructureOnly": True,
        "pdfRenderNotVerified": True,
        "source": validate_material(source_path, SOURCE_PAGES, SOURCE_LINES),
        "documentation": validate_material(doc_path, DOC_PAGES, DOC_LINES),
        "sensitiveScanScope": "generated HTML only; inspect source inputs separately before submission",
    }
    report["pass"] = bool(
        report["source"]["pageCountPass"]
        and report["source"]["lineCountPass"]
        and report["documentation"]["pageCountPass"]
        and report["documentation"]["lineCountPass"]
        and report["source"]["footerCountPass"]
        and report["documentation"]["footerCountPass"]
        and not report["source"]["sensitivePatternHits"]
        and not report["documentation"]["sensitivePatternHits"]
    )
    (out / "validation-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
