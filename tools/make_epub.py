#!/usr/bin/env python3
"""Generate EPUB for The Calibrant novellas - Nook native format."""

import sys
import re
from pathlib import Path

# pip/uv dependency
try:
    from ebooklib import epub
except ImportError:
    print("Installing ebooklib...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ebooklib", "-q"])
    from ebooklib import epub


NOVELLA_DIR = Path(__file__).parent.parent / "docs" / "novellas"
OUTPUT_DIR = Path(__file__).parent.parent / "docs" / "novellas"

WORLDS = [
    ("world1_the_usurpers_crown.md", "The Usurper's Crown", "World 1 — Medieval"),
    ("world2_the_neighborhood_problem.md", "The Neighborhood Problem", "World 2 — Suburban"),
    ("world3_the_regulator.md", "The Regulator", "World 3 — Steampunk"),
    ("world4_the_assembly.md", "The Assembly", "World 4 — Industrial"),
    ("world5_the_source.md", "The Source", "World 5 — Digital"),
    ("world6_the_remainder.md", "The Remainder", "World 6 — Abstract"),
]

BOOK_CSS = """
body {
    font-family: Georgia, "Times New Roman", serif;
    line-height: 1.8;
    color: #1a1a1a;
    margin: 1em;
}
h1 {
    font-size: 2em;
    text-align: center;
    margin: 1.5em 0 0.3em;
    color: #2c1810;
    page-break-before: always;
}
h2 {
    font-size: 1.1em;
    text-align: center;
    font-weight: normal;
    font-style: italic;
    color: #666;
    margin-bottom: 2em;
}
h3 {
    font-size: 1.3em;
    color: #3a2010;
    margin: 2em 0 1em;
    border-top: 1px solid #ccc;
    padding-top: 1.5em;
}
p {
    margin-bottom: 1em;
    text-indent: 1.5em;
}
p:first-of-type, h3 + p {
    text-indent: 0;
}
hr {
    border: none;
    text-align: center;
    margin: 2em 0;
}
hr::before {
    content: "* * *";
    color: #999;
    letter-spacing: 0.5em;
}
pre {
    background: #0a0a0a;
    color: #00cc44;
    font-family: "Courier New", monospace;
    font-size: 0.85em;
    padding: 1em;
    border-radius: 4px;
    white-space: pre-wrap;
    margin: 1.5em 0;
}
em { color: #333; }
strong { color: #2c1810; }
.end-mark {
    text-align: center;
    font-style: italic;
    color: #999;
    margin: 2em 0;
}
.world-break {
    text-align: center;
    font-style: italic;
    color: #666;
    font-size: 1.2em;
    margin: 3em 0;
    padding: 1.5em 0;
    border-top: 2px solid #ccc;
    border-bottom: 2px solid #ccc;
}
"""


def md_to_html(md_text: str) -> str:
    """Convert markdown to simple HTML for epub chapters."""
    lines = md_text.strip().split("\n")
    html_parts = []
    in_code = False
    code_buf = []

    for line in lines:
        # Code blocks
        if line.strip().startswith("```"):
            if in_code:
                html_parts.append(f'<pre>{"&#10;".join(code_buf)}</pre>')
                code_buf = []
                in_code = False
            else:
                in_code = True
            continue
        if in_code:
            code_buf.append(line.replace("<", "&lt;").replace(">", "&gt;"))
            continue

        stripped = line.strip()

        # Skip top-level title and subtitle (we handle those in chapter wrapper)
        if stripped.startswith("# ") and not stripped.startswith("## ") and not stripped.startswith("### "):
            continue
        if stripped.startswith("## A Novella"):
            continue

        # Headings
        if stripped.startswith("### "):
            text = stripped[4:]
            html_parts.append(f"<h3>{text}</h3>")
            continue
        if stripped.startswith("## "):
            text = stripped[3:]
            html_parts.append(f"<h2>{text}</h2>")
            continue

        # Horizontal rules
        if stripped == "---":
            html_parts.append("<hr/>")
            continue

        # Empty lines
        if not stripped:
            continue

        # End marks
        if stripped.startswith("*End of") or stripped.startswith("*End of"):
            text = stripped.strip("*")
            html_parts.append(f'<p class="end-mark">{text}</p>')
            continue

        # Inline formatting
        para = stripped
        # Bold
        para = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', para)
        # Italic
        para = re.sub(r'\*(.+?)\*', r'<em>\1</em>', para)

        html_parts.append(f"<p>{para}</p>")

    return "\n".join(html_parts)


def make_epub():
    book = epub.EpubBook()

    # Metadata
    book.set_identifier("cowardly-irregular-calibrant-novellas-v2")
    book.set_title("The Calibrant")
    book.set_language("en")
    book.add_author("Carmelo Piccione")
    book.add_metadata("DC", "description", "Six Novellas from Cowardly Irregular")

    # Stylesheet
    style = epub.EpubItem(
        uid="style",
        file_name="style/default.css",
        media_type="text/css",
        content=BOOK_CSS.encode("utf-8"),
    )
    book.add_item(style)

    # Title page
    title_html = """
    <div style="text-align:center; padding-top:40%;">
        <h1 style="font-size:2.5em; color:#2c1810; page-break-before:avoid;">The Calibrant</h1>
        <p style="font-size:1.2em; font-style:italic; color:#666; text-indent:0;">Six Novellas from Cowardly Irregular</p>
        <p style="margin-top:3em; color:#999; text-indent:0;">Carmelo Piccione</p>
        <p style="color:#999; text-indent:0;">Struktured Labs — 2025</p>
    </div>
    """
    title_page = epub.EpubHtml(
        title="Title Page", file_name="title.xhtml", lang="en"
    )
    title_page.content = title_html.encode("utf-8")
    title_page.add_item(style)
    book.add_item(title_page)

    chapters = []
    spine = ["nav", title_page]

    for i, (filename, title, subtitle) in enumerate(WORLDS, 1):
        filepath = NOVELLA_DIR / filename
        if not filepath.exists():
            print(f"WARNING: {filepath} not found, skipping")
            continue

        md_text = filepath.read_text()
        body_html = md_to_html(md_text)

        chapter_html = f"""
        <h1>{title}</h1>
        <h2>{subtitle}</h2>
        {body_html}
        """

        # Add transition between worlds
        if i < len(WORLDS):
            chapter_html += '<div class="world-break">~ Phase Transition ~</div>'

        ch = epub.EpubHtml(
            title=f"{title} ({subtitle})",
            file_name=f"world{i}.xhtml",
            lang="en",
        )
        ch.content = chapter_html.encode("utf-8")
        ch.add_item(style)
        book.add_item(ch)
        chapters.append(ch)
        spine.append(ch)

    # Table of contents
    book.toc = [title_page] + chapters
    book.add_item(epub.EpubNcx())
    book.add_item(epub.EpubNav())

    # Spine
    book.spine = spine

    # Write
    output_path = OUTPUT_DIR / "the_calibrant_novellas.epub"
    epub.write_epub(str(output_path), book)
    print(f"EPUB written to {output_path}")
    print(f"Size: {output_path.stat().st_size / 1024:.0f}KB")
    print(f"Chapters: {len(chapters)}")


if __name__ == "__main__":
    make_epub()
