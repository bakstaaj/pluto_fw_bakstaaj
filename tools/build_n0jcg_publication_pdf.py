#!/usr/bin/env python3
"""Build a branded N0JCG publication PDF from Markdown."""

from __future__ import annotations

import argparse
from html import escape
from pathlib import Path
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    XPreformatted,
)


NAVY = colors.HexColor("#0A1F44")
BLUE = colors.HexColor("#1565C0")
CYAN = colors.HexColor("#00B8D9")
SLATE = colors.HexColor("#2B3440")
MIST = colors.HexColor("#F4F7FA")
TEXT = colors.HexColor("#15202B")
MUTED = colors.HexColor("#536171")
BORDER = colors.HexColor("#C7CDD4")
WHITE = colors.white
PAGE_WIDTH, PAGE_HEIGHT = letter
LEFT = RIGHT = 0.68 * inch
TOP = 0.76 * inch
BOTTOM = 0.64 * inch
CONTENT_WIDTH = PAGE_WIDTH - LEFT - RIGHT


def inline_markup(text: str) -> str:
    """Translate the small inline Markdown subset used by the manual."""
    placeholders: list[str] = []

    def stash(value: str) -> str:
        placeholders.append(value)
        return f"@@INLINE{len(placeholders) - 1}@@"

    text = re.sub(
        r"`([^`]+)`",
        lambda m: stash(f'<font name="Courier" color="#0A1F44">{escape(m.group(1))}</font>'),
        text,
    )
    text = re.sub(
        r"\[([^]]+)\]\([^)]+\)",
        lambda m: stash(f'<font color="#1565C0"><u>{escape(m.group(1))}</u></font>'),
        text,
    )
    text = escape(text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)
    for index, value in enumerate(placeholders):
        text = text.replace(f"@@INLINE{index}@@", value)
    return text


def is_table_separator(line: str) -> bool:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def make_styles():
    base = getSampleStyleSheet()
    return {
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.15,
            leading=12.2,
            textColor=TEXT,
            spaceAfter=6,
            allowWidows=0,
            allowOrphans=0,
        ),
        "lead": ParagraphStyle(
            "Lead",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=12,
            leading=16.5,
            textColor=SLATE,
            alignment=TA_CENTER,
            spaceAfter=14,
        ),
        "h1": ParagraphStyle(
            "H1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=NAVY,
            spaceBefore=13,
            spaceAfter=7,
            keepWithNext=True,
        ),
        "h2": ParagraphStyle(
            "H2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=13,
            leading=16,
            textColor=BLUE,
            spaceBefore=10,
            spaceAfter=5,
            keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "H3",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=10.5,
            leading=13,
            textColor=SLATE,
            spaceBefore=8,
            spaceAfter=4,
            keepWithNext=True,
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.9,
            leading=11.8,
            textColor=TEXT,
            leftIndent=0,
            spaceAfter=3,
        ),
        "caption": ParagraphStyle(
            "Caption",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.2,
            leading=10.5,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceBefore=5,
            spaceAfter=12,
        ),
        "toc": ParagraphStyle(
            "TOC",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.2,
            leading=13,
            textColor=NAVY,
            leftIndent=12,
            firstLineIndent=-12,
            spaceAfter=3,
        ),
        "code": ParagraphStyle(
            "Code",
            parent=base["Code"],
            fontName="Courier",
            fontSize=7.15,
            leading=9.2,
            textColor=SLATE,
            leftIndent=0,
            rightIndent=0,
        ),
        "table": ParagraphStyle(
            "Table",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.75,
            leading=9.7,
            textColor=TEXT,
        ),
        "table_head": ParagraphStyle(
            "TableHead",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=7.5,
            leading=9.2,
            textColor=WHITE,
        ),
    }


def draw_page(canvas, doc, logo_path: Path, short_title: str, release: str) -> None:
    canvas.saveState()
    if doc.page > 1:
        canvas.setFillColor(NAVY)
        canvas.rect(0, PAGE_HEIGHT - 34, PAGE_WIDTH, 34, fill=1, stroke=0)
        canvas.drawImage(
            str(logo_path),
            LEFT,
            PAGE_HEIGHT - 29,
            width=1.55 * inch,
            height=0.295 * inch,
            preserveAspectRatio=True,
            mask="auto",
            anchor="w",
        )
        canvas.setFillColor(WHITE)
        canvas.setFont("Helvetica-Bold", 8)
        canvas.drawRightString(PAGE_WIDTH - RIGHT, PAGE_HEIGHT - 22, short_title.upper())
    canvas.setStrokeColor(CYAN)
    canvas.setLineWidth(0.8)
    canvas.line(LEFT, 28, PAGE_WIDTH - RIGHT, 28)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(LEFT, 16, f"N0JCG Open Radio Platform  |  {release}")
    canvas.drawRightString(PAGE_WIDTH - RIGHT, 16, f"Page {doc.page}")
    canvas.restoreState()


def screenshot_block(path: Path, caption: str, styles, max_height: float) -> list:
    image = Image(str(path))
    image._restrictSize(CONTENT_WIDTH, max_height)
    return [image, Paragraph(caption, styles["caption"])]


def parse_manual(markdown: str, styles) -> list:
    lines = markdown.splitlines()
    start = next((i for i, line in enumerate(lines) if re.match(r"^##\s+(?:1\.\s|Transport$)", line)), 0)
    lines = lines[start:]
    story: list = []
    paragraph_lines: list[str] = []
    index = 0

    def flush_paragraph() -> None:
        nonlocal paragraph_lines
        if paragraph_lines:
            text = " ".join(part.strip() for part in paragraph_lines)
            story.append(Paragraph(inline_markup(text), styles["body"]))
            paragraph_lines = []

    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped:
            flush_paragraph()
            index += 1
            continue
        if stripped.startswith("```"):
            flush_paragraph()
            index += 1
            code_lines: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code_lines.append(lines[index].rstrip())
                index += 1
            index += 1
            code = XPreformatted(escape("\n".join(code_lines)), styles["code"])
            box = Table([[code]], colWidths=[CONTENT_WIDTH - 14], hAlign="LEFT")
            box.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#EEF2F6")),
                ("BOX", (0, 0), (-1, -1), 0.5, BORDER),
                ("LINEBEFORE", (0, 0), (0, -1), 3, BLUE),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]))
            story.extend([box, Spacer(1, 5)])
            continue
        heading = re.match(r"^(#{2,4})\s+(.+)$", stripped)
        if heading:
            flush_paragraph()
            level = len(heading.group(1))
            style = styles[{2: "h1", 3: "h2", 4: "h3"}[level]]
            story.append(Paragraph(inline_markup(heading.group(2)), style))
            index += 1
            continue
        if stripped.startswith("|") and index + 1 < len(lines) and is_table_separator(lines[index + 1]):
            flush_paragraph()
            raw_rows = [split_table_row(stripped)]
            index += 2
            while index < len(lines) and lines[index].strip().startswith("|"):
                raw_rows.append(split_table_row(lines[index]))
                index += 1
            columns = max(len(row) for row in raw_rows)
            weights = []
            for column in range(columns):
                length = max(len(row[column]) if column < len(row) else 0 for row in raw_rows)
                weights.append(max(10, min(length, 48)))
            total = sum(weights)
            widths = [CONTENT_WIDTH * value / total for value in weights]
            data = []
            for row_index, row in enumerate(raw_rows):
                data.append([
                    Paragraph(inline_markup(row[col] if col < len(row) else ""), styles["table_head" if row_index == 0 else "table"])
                    for col in range(columns)
                ])
            table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, colors.HexColor("#F8FAFC")]),
                ("GRID", (0, 0), (-1, -1), 0.35, BORDER),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]))
            story.extend([table, Spacer(1, 6)])
            continue
        item = re.match(r"^[-*]\s+(.+)$", stripped)
        numbered = re.match(r"^\d+\.\s+(.+)$", stripped)
        if item or numbered:
            flush_paragraph()
            items: list[ListItem] = []
            ordered = bool(numbered)
            pattern = r"^\d+\.\s+(.+)$" if ordered else r"^[-*]\s+(.+)$"
            while index < len(lines):
                match = re.match(pattern, lines[index].strip())
                if not match:
                    break
                value = match.group(1)
                index += 1
                while index < len(lines):
                    continuation = lines[index].strip()
                    if not continuation or re.match(r"^[-*]\s+|^\d+\.\s+|^#{2,4}\s+|^```|^\|", continuation):
                        break
                    value += " " + continuation
                    index += 1
                if value.startswith("[ ] "):
                    value = "[ ] " + value[4:]
                items.append(ListItem(Paragraph(inline_markup(value), styles["bullet"]), leftIndent=14))
            story.append(ListFlowable(
                items,
                bulletType="1" if ordered else "bullet",
                start="1",
                leftIndent=20,
                bulletFontName="Helvetica",
                bulletFontSize=8.5,
                bulletColor=BLUE,
                spaceAfter=5,
            ))
            continue
        paragraph_lines.append(stripped)
        index += 1
    flush_paragraph()
    return story


def build(source: Path, output: Path, logo: Path, screenshots: Path | None, title: str, subtitle: str, kicker: str, release: str) -> None:
    styles = make_styles()
    output.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(output),
        pagesize=letter,
        leftMargin=LEFT,
        rightMargin=RIGHT,
        topMargin=TOP,
        bottomMargin=BOTTOM,
        title=title,
        author="N0JCG Open Radio Platform",
        subject=subtitle,
    )
    frame = Frame(LEFT, BOTTOM, CONTENT_WIDTH, PAGE_HEIGHT - TOP - BOTTOM, id="normal")
    doc.addPageTemplates(PageTemplate(id="manual", frames=[frame], onPage=lambda c, d: draw_page(c, d, logo, title, release)))

    story: list = []
    banner = Table([[Image(str(logo), width=4.75 * inch, height=0.9 * inch)]], colWidths=[CONTENT_WIDTH])
    banner.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), NAVY),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 20),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 20),
    ]))
    story.extend([
        banner,
        Spacer(1, 46),
        Paragraph(inline_markup(kicker.upper()), ParagraphStyle("Kicker", parent=styles["body"], alignment=TA_CENTER, fontName="Helvetica-Bold", fontSize=9, leading=11, textColor=CYAN, spaceAfter=9)),
        Paragraph(inline_markup(title), ParagraphStyle("Title", parent=styles["h1"], alignment=TA_CENTER, fontSize=30, leading=34, textColor=NAVY, spaceAfter=8)),
        Paragraph(inline_markup(subtitle), styles["lead"]),
        Table([
            ["RELEASE", release, "PUBLICATION", "August 2026"],
            ["PLATFORM", "PlutoSDR / Pluto Plus", "AUDIENCE", "Operators and app builders"],
        ], colWidths=[0.95 * inch, 2.15 * inch, 1.05 * inch, 2.15 * inch], style=TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), MIST),
            ("BOX", (0, 0), (-1, -1), 0.5, BORDER),
            ("INNERGRID", (0, 0), (-1, -1), 0.35, BORDER),
            ("TEXTCOLOR", (0, 0), (-1, -1), NAVY),
            ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
            ("FONTNAME", (2, 0), (2, -1), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 8.5),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 9),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ])),
        Spacer(1, 28),
        Paragraph(inline_markup("A practical N0JCG reference for firmware operation, application integration, diagnostics, and safe RF workflows."), styles["lead"]),
        PageBreak(),
        Paragraph("Contents", styles["h1"]),
    ])
    headings = [line[3:].strip() for line in source.read_text(encoding="utf-8").splitlines() if re.match(r"^##\s+", line) and line.strip() not in {"## User Guide", "## Contents"}]
    story.extend(Paragraph(inline_markup(heading), styles["toc"]) for heading in headings)
    if screenshots:
        story.extend([
            PageBreak(),
            Paragraph("Interface reference", styles["h1"]),
            Paragraph("These branded screen references show the operator dashboard and app-builder API test surface used by the Pluto firmware workflow.", styles["body"]),
        ])
        for name, caption in (("n0jcg-pluto-dashboard.png", "Operator dashboard - system state, receive controls, and guarded transmit access."), ("n0jcg-pluto-api-test.png", "API test page - endpoint groups, request controls, and a successful status response.")):
            path = screenshots / name
            if path.exists():
                story.append(Image(str(path), width=CONTENT_WIDTH, height=2.35 * inch, kind="proportional"))
                story.append(Paragraph(f"<font color=\"#536171\">{escape(caption)}</font>", styles["caption"]))
                story.append(Spacer(1, 10))
        story.append(PageBreak())
    story.extend(parse_manual(source.read_text(encoding="utf-8"), styles))
    doc.build(story)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--logo", type=Path, required=True)
    parser.add_argument("--screenshots", type=Path)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", required=True)
    parser.add_argument("--kicker", required=True)
    parser.add_argument("--release", required=True)
    args = parser.parse_args()
    build(args.source.resolve(), args.output.resolve(), args.logo.resolve(), args.screenshots.resolve() if args.screenshots else None, args.title, args.subtitle, args.kicker, args.release)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
