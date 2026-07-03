#!/usr/bin/env python3
import argparse
import html
import json
import os
from pathlib import Path


def read_manifest(directory):
    path = directory / "manifest.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def pngs(directory):
    if not directory:
        return []
    return sorted(directory.glob("*.png"))


def frame_label(path, manifest):
    frames = manifest.get("frames") or []
    record = next((frame for frame in frames if frame.get("file") == path.name), None)
    if record and "elapsedMs" in record:
        return f"{path.stem} · {record['elapsedMs'] / 1000:.1f}s"
    return path.stem


def image_src(path, output):
    return os.path.relpath(path, output.parent)


def render_strip(title, directory, output):
    manifest = read_manifest(directory)
    frames = pngs(directory)
    escaped_title = html.escape(title)
    directory_text = html.escape(str(directory))
    parts = [
        f"<section>",
        f"<h2>{escaped_title}</h2>",
        f"<p class=\"path\">{directory_text}</p>",
        "<div class=\"strip\">",
    ]
    for frame in frames:
        src = html.escape(image_src(frame, output), quote=True)
        label = html.escape(frame_label(frame, manifest))
        parts.append(
            "<figure>"
            f"<img src=\"{src}\" alt=\"{escaped_title} {label}\">"
            f"<figcaption>{label}</figcaption>"
            "</figure>"
        )
    if not frames:
        parts.append("<p class=\"empty\">No PNG frames found.</p>")
    parts.extend(["</div>", "</section>"])
    return "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(
        description="Build an HTML page for human review of native and browser boot strips."
    )
    parser.add_argument("--native", type=Path, help="Native boot strip directory")
    parser.add_argument("--browser", type=Path, help="Browser boot strip directory")
    parser.add_argument("--out", type=Path, default=Path("/tmp/xemu-boot-strip-review.html"))
    args = parser.parse_args()

    if not args.native and not args.browser:
        parser.error("provide --native, --browser, or both")

    output = args.out.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    sections = []
    if args.native:
        sections.append(render_strip("Native software GL reference", args.native.resolve(), output))
    if args.browser:
        sections.append(render_strip("Browser current output", args.browser.resolve(), output))

    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>xemu boot strip visual review</title>
  <style>
    :root {{
      color-scheme: light dark;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #111;
      color: #eee;
    }}
    body {{
      margin: 0;
      padding: 24px;
    }}
    h1, h2 {{
      margin: 0 0 8px;
      font-weight: 650;
    }}
    header, section {{
      margin-bottom: 28px;
    }}
    .rule {{
      max-width: 900px;
      color: #c8c8c8;
      line-height: 1.45;
    }}
    .path {{
      margin: 0 0 12px;
      color: #9da7b1;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 13px;
    }}
    .strip {{
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
      gap: 12px;
      align-items: start;
    }}
    figure {{
      margin: 0;
      background: #1b1f24;
      border: 1px solid #30363d;
      border-radius: 6px;
      overflow: hidden;
    }}
    img {{
      display: block;
      width: 100%;
      aspect-ratio: 4 / 3;
      object-fit: contain;
      background: #000;
      image-rendering: auto;
    }}
    figcaption {{
      padding: 6px 8px;
      color: #c8c8c8;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
    }}
    .empty {{
      color: #ffb86b;
    }}
  </style>
</head>
<body>
  <header>
    <h1>xemu boot strip visual review</h1>
    <p class="rule">
      Human review only. Use this page to judge whether the browser is moving
      closer to native by visual feel: same broad sequence, same shapes, fewer
      black gaps, fewer corrupt colors, and the same final state. This page does
      not compute pixel diffs, hashes, or pass/fail scores.
    </p>
  </header>
  {"".join(sections)}
</body>
</html>
"""
    output.write_text(document, encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
