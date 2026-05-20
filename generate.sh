#!/bin/bash
# EVA Tech Brief Generator
# Called by EVA's cron at 7:25 PM PKT
# Usage: ./generate.sh YYYY-MM-DD brief.json
#
# EVA generates brief.json with the content, this script:
# 1. Renders the HTML from template + JSON
# 2. Updates index.html archive
# 3. Updates feed.xml
# 4. Commits and pushes (CF auto-deploys)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DATE="${1:?Usage: generate.sh YYYY-MM-DD brief.json}"
JSON_FILE="${2:?Usage: generate.sh YYYY-MM-DD brief.json}"

if [ ! -f "$JSON_FILE" ]; then
    echo "Error: $JSON_FILE not found"
    exit 1
fi

cd "$REPO_DIR"

BRIEF_DIR="$REPO_DIR/$DATE"
mkdir -p "$BRIEF_DIR"

# Read JSON and render HTML using Python
python3 - "$DATE" "$JSON_FILE" "$BRIEF_DIR/index.html" "$REPO_DIR/template.html" <<'PYTHON'
import sys, json
from pathlib import Path

date = sys.argv[1]
data = json.loads(Path(sys.argv[2]).read_text())
output = sys.argv[3]
template = Path(sys.argv[4]).read_text()

def render_items(items):
    html = ""
    for item in items:
        sources = ""
        for src in item.get("sources", []):
            sources += f'<a href="{src["url"]}" target="_blank">{src["label"]}</a>'
        html += f'''<div class="item">
            <h3>{item["headline"]}</h3>
            <p>{item["detail"]}</p>
            <div class="source">{sources}</div>
        </div>\n'''
    return html

pillars = ["llm", "gpu", "cloud", "pakistan", "security", "dev"]
summary_parts = []
for p in pillars:
    items = data.get(p, [])
    if items:
        summary_parts.append(items[0]["headline"])
    template = template.replace("{{" + p.upper() + "_ITEMS}}", render_items(items))

summary = " | ".join(summary_parts[:3])
template = template.replace("{{DATE}}", date)
template = template.replace("{{SUMMARY}}", summary)

Path(output).write_text(template)
print(f"Rendered {output}")
PYTHON

# Update index.html archive
python3 - "$DATE" "$REPO_DIR/index.html" "$JSON_FILE" <<'PYTHON'
import sys, json, re
from pathlib import Path

date = sys.argv[1]
index_path = sys.argv[2]
data = json.loads(Path(sys.argv[3]).read_text())

pillars = ["llm", "gpu", "cloud", "pakistan", "security", "dev"]
summary_parts = []
for p in pillars:
    items = data.get(p, [])
    if items:
        summary_parts.append(items[0]["headline"])
summary = " | ".join(summary_parts[:3])

entry = f'<li><a href="/{date}">{date}</a><span class="summary">{summary}</span></li>'

index = Path(index_path).read_text()

existing = re.search(r'<!-- ARCHIVE_START -->(.*?)<!-- ARCHIVE_END -->', index, re.DOTALL)
if existing:
    current = existing.group(1).strip()
    if f'href="/{date}"' in current:
        lines = [l for l in current.split('\n') if f'href="/{date}"' not in l]
        current = '\n'.join(lines)
    if '<ul class="archive-list">' not in current:
        new_archive = f'<ul class="archive-list">\n{entry}\n</ul>'
    else:
        new_archive = current.replace('<ul class="archive-list">', f'<ul class="archive-list">\n{entry}')
    index = index[:existing.start()] + '<!-- ARCHIVE_START -->\n' + new_archive + '\n<!-- ARCHIVE_END -->' + index[existing.end():]

Path(index_path).write_text(index)
print(f"Updated {index_path}")
PYTHON

# Update RSS feed
python3 - "$DATE" "$REPO_DIR/feed.xml" "$JSON_FILE" <<'PYTHON'
import sys, json
from pathlib import Path

date = sys.argv[1]
feed_path = sys.argv[2]
data = json.loads(Path(sys.argv[3]).read_text())

pillars = ["llm", "gpu", "cloud", "pakistan", "security", "dev"]
summary_parts = []
for p in pillars:
    items = data.get(p, [])
    if items:
        summary_parts.append(items[0]["headline"])
summary = " | ".join(summary_parts[:3])

item = f'''    <item>
        <title>EVA Tech Brief | {date}</title>
        <link>https://brief.rola.fyi/{date}</link>
        <guid>https://brief.rola.fyi/{date}</guid>
        <pubDate>{date}T19:30:00+05:00</pubDate>
        <description>{summary}</description>
    </item>'''

feed = Path(feed_path).read_text()
if f'<guid>https://brief.rola.fyi/{date}</guid>' not in feed:
    feed = feed.replace('<!-- FEED_ITEMS -->', f'<!-- FEED_ITEMS -->\n{item}')
    Path(feed_path).write_text(feed)
    print(f"Updated {feed_path}")
else:
    print(f"Feed already has entry for {date}")
PYTHON

# Git commit and push
cd "$REPO_DIR"
git add -A
git diff --cached --quiet && echo "No changes to commit" && exit 0
git commit -m "Brief: $DATE"
git push origin main

echo "Done. Live at https://brief.rola.fyi/$DATE"
