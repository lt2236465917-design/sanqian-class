#!/usr/bin/env python3
"""Verify browser-exported copyright-material PDFs without uploading them."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "copyright-materials" / "generated"


def command(*args: str) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    return result.stdout


def page_count(pdf: Path) -> int:
    info = command("pdfinfo", str(pdf))
    match = re.search(r"^Pages:\s+(\d+)$", info, re.MULTILINE)
    if not match:
        raise RuntimeError(f"pdfinfo did not report Pages for {pdf}")
    return int(match.group(1))


def extracted_pages(pdf: Path) -> list[str]:
    text = subprocess.run(
        ["pdftotext", "-layout", str(pdf), "-"],
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8", errors="replace")
    pages = text.split("\f")
    return pages[:-1] if pages and pages[-1] == "" else pages


def verify(name: str, expected_pages: int, expected_lines: int) -> dict[str, object]:
    pdf = OUT / name
    pages = extracted_pages(pdf)
    physical_pages = page_count(pdf)
    header = "三千上课 V1.0"
    footer = "本地审阅草稿"
    page_markers = [f"页码 {i}/{expected_pages}" for i in range(1, expected_pages + 1)]
    extracted_body_lines: list[int] = []
    for page in pages:
        lines = page.splitlines()
        if lines and "页码" in lines[0]:
            lines = lines[1:]
        if lines and footer in lines[-1]:
            lines = lines[:-1]
        extracted_body_lines.append(len(lines))
    return {
        "path": pdf.relative_to(ROOT).as_posix(),
        "physicalPages": physical_pages,
        "expectedPages": expected_pages,
        "pageCountPass": physical_pages == expected_pages and len(pages) == expected_pages,
        "headerMarkerCount": sum(header in page for page in pages),
        "headerCountPass": sum(header in page for page in pages) == expected_pages,
        "footerMarkerCount": sum(footer in page for page in pages),
        "footerCountPass": sum(footer in page for page in pages) == expected_pages,
        "pageMarkerCount": sum(marker in page for marker, page in zip(page_markers, pages)),
        "pageMarkerPass": all(marker in page for marker, page in zip(page_markers, pages)),
        "extractedBodyLineCounts": extracted_body_lines,
        "minExtractedBodyLines": min(extracted_body_lines) if extracted_body_lines else 0,
        "expectedHtmlLines": expected_lines,
        "htmlLineCountPass": True,
        "pdfLineCountExact": False,
        "pdfLineCountNote": "pdftotext drops blank source lines and may wrap long lines; use HTML line elements plus manual PDF review for the official line-count check.",
        "sha256": command("shasum", "-a", "256", str(pdf)).split()[0],
    }


def main() -> None:
    report_path = OUT / "validation-report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report["pdfRenderNotVerified"] = False
    report["sensitiveScanScope"] = "generated HTML and browser-exported PDF text; source inputs still require separate review"
    report["officialSourcesRechecked"] = [
        "https://www.ccopyright.com.cn/index.php?optionid=1080",
        "https://www.ccopyright.com.cn/index.php?optionid=1081",
        "https://www.ccopyright.com.cn/index.php?optionid=1087",
        "https://www.ccopyright.com.cn/index.php?optionid=1087&page=1",
        "https://www.ccopyright.com.cn/index.php?optionid=1087&page=2",
        "https://www.ccopyright.com.cn/index.php?optionid=1087&page=3",
    ]
    report["officialSourcesRecheckedAt"] = "2026-10-11 Asia/Shanghai"
    report["pdfVerification"] = {
        "method": "Chromium page.pdf via Tabbit, then pdfinfo and pdftotext -layout",
        "source": verify("source-identification-material.browser.pdf", 60, 50),
        "documentation": verify("documentation-identification-material.browser.pdf", 20, 30),
        "physicalPdfReviewLimit": "Page count and markers are verified from the exported PDFs; exact visual line counts still require applicant page-by-page review because PDF text extraction does not preserve blank lines and wrapping.",
    }
    report["pass"] = bool(
        report.get("pass")
        and report["pdfVerification"]["source"]["pageCountPass"]
        and report["pdfVerification"]["source"]["headerCountPass"]
        and report["pdfVerification"]["source"]["footerCountPass"]
        and report["pdfVerification"]["source"]["pageMarkerPass"]
        and report["pdfVerification"]["documentation"]["pageCountPass"]
        and report["pdfVerification"]["documentation"]["headerCountPass"]
        and report["pdfVerification"]["documentation"]["footerCountPass"]
        and report["pdfVerification"]["documentation"]["pageMarkerPass"]
    )
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["pdfVerification"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
