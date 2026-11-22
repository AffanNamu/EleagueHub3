"""Download Apple developer documentation into a local, searchable archive.

Usage: python3 -I fetch_apple_docs.py <manifest.tsv> <output_root>

Manifest columns (tab separated): category, slug, source, mode
  mode=html  source is a full URL to a server-rendered page
  mode=doc   source is a DocC path (documentation/...) -- fetched as JSON
  mode=hig   source is a HIG slug -- resolved via redirects, fetched as JSON

For every entry the raw payload is preserved verbatim (.html / .json) and a
Markdown extraction (.md) is written next to it for offline searching.
"""

import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")
BASE = "https://developer.apple.com"


def curl(url):
    """Return (status, final_url, body_bytes)."""
    out = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-A", UA,
         "-w", "\n__META__%{http_code} %{url_effective}", url],
        capture_output=True)
    raw = out.stdout
    idx = raw.rfind(b"\n__META__")
    if idx < 0:
        return 0, url, b"", out.stderr.decode(errors="replace")
    meta = raw[idx + len(b"\n__META__"):].decode().split(" ", 1)
    return int(meta[0]), meta[1] if len(meta) > 1 else url, raw[:idx], out.stderr.decode(errors="replace")


# ── HTML -> Markdown ────────────────────────────────────────────────────────

def html_to_md(html):
    m = re.search(r"<main\b.*?</main>", html, re.S | re.I)
    fragment = m.group(0) if m else html
    for tag in ("script", "style", "nav", "noscript", "svg", "form"):
        fragment = re.sub(rf"<{tag}\b.*?</{tag}>", "", fragment, flags=re.S | re.I)
    res = subprocess.run(["pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none"],
                         input=fragment.encode(), capture_output=True)
    md = res.stdout.decode(errors="replace")
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md


# ── DocC JSON -> Markdown ───────────────────────────────────────────────────

class DocRenderer:
    def __init__(self, data):
        self.d = data
        self.refs = data.get("references", {}) or {}

    def inline(self, items):
        out = []
        for it in items or []:
            t = it.get("type")
            if t == "text":
                out.append(it.get("text", ""))
            elif t == "codeVoice":
                out.append(f"`{it.get('code', '')}`")
            elif t in ("emphasis", "newTerm"):
                out.append(f"*{self.inline(it.get('inlineContent'))}*")
            elif t == "strong":
                out.append(f"**{self.inline(it.get('inlineContent'))}**")
            elif t == "reference":
                ref = self.refs.get(it.get("identifier"), {})
                title = it.get("overridingTitle") or ref.get("title") or it.get("identifier", "")
                url = ref.get("url", "")
                if url.startswith("/"):
                    url = BASE + url
                out.append(f"[{title}]({url})" if url else title)
            elif t == "link":
                out.append(f"[{it.get('title', it.get('destination', ''))}]({it.get('destination', '')})")
            elif t == "image":
                out.append("[image]")
            elif "inlineContent" in it:
                out.append(self.inline(it.get("inlineContent")))
        return "".join(out)

    def blocks(self, items, depth=0):
        out = []
        pad = "  " * depth
        for b in items or []:
            t = b.get("type")
            if t == "heading":
                out.append("#" * min(6, b.get("level", 2) + 1) + " " + b.get("text", ""))
            elif t == "paragraph":
                out.append(pad + self.inline(b.get("inlineContent")))
            elif t in ("unorderedList", "orderedList"):
                for i, item in enumerate(b.get("items", []), 1):
                    body = self.blocks(item.get("content"), depth + 1).strip()
                    bullet = f"{i}." if t == "orderedList" else "-"
                    out.append(f"{pad}{bullet} {body.lstrip()}")
            elif t == "aside":
                name = b.get("name") or b.get("style", "note").title()
                body = self.blocks(b.get("content"), depth).strip()
                out.append("> **" + name + ":** " + body.replace("\n", "\n> "))
            elif t == "codeListing":
                out.append("```" + (b.get("syntax") or "") + "\n" + "\n".join(b.get("code", [])) + "\n```")
            elif t == "table":
                rows = b.get("rows", [])
                for r_i, row in enumerate(rows):
                    cells = [self.blocks(c).replace("\n", " ").strip() for c in row]
                    out.append("| " + " | ".join(cells) + " |")
                    if r_i == 0:
                        out.append("|" + "---|" * len(cells))
            elif t == "termList":
                for item in b.get("items", []):
                    term = self.inline(item.get("term", {}).get("inlineContent"))
                    defn = self.blocks(item.get("definition", {}).get("content")).strip()
                    out.append(f"- **{term}**: {defn}")
            elif t == "row":
                for col in b.get("columns", []):
                    out.append(self.blocks(col.get("content"), depth))
            elif t in ("tabNavigator",):
                for tab in b.get("tabs", []):
                    out.append(f"**{tab.get('title', '')}**")
                    out.append(self.blocks(tab.get("content"), depth))
            elif t == "links":
                for ident in b.get("items", []):
                    ref = self.refs.get(ident, {})
                    out.append(f"- {ref.get('title', ident)} ({BASE + ref.get('url', '')})")
            elif "content" in b and isinstance(b["content"], list):
                out.append(self.blocks(b["content"], depth))
            elif "inlineContent" in b:
                out.append(pad + self.inline(b.get("inlineContent")))
        return "\n\n".join(x for x in out if x)

    def render(self):
        d = self.d
        meta = d.get("metadata", {}) or {}
        parts = [f"# {meta.get('title', '')}"]
        if meta.get("roleHeading"):
            parts.append(f"_{meta['roleHeading']}_")
        plats = meta.get("platforms") or []
        if plats:
            parts.append("Platforms: " + ", ".join(
                f"{p.get('name')} {p.get('introducedAt', '')}{' (deprecated ' + p['deprecatedAt'] + ')' if p.get('deprecatedAt') else ''}"
                for p in plats))
        if d.get("abstract"):
            parts.append(self.inline(d["abstract"]))
        for sec in d.get("primaryContentSections", []) or []:
            kind = sec.get("kind")
            if kind == "content":
                parts.append(self.blocks(sec.get("content")))
            elif kind == "declarations":
                for decl in sec.get("declarations", []):
                    code = "".join(tok.get("text", "") for tok in decl.get("tokens", []))
                    parts.append("```swift\n" + code + "\n```")
            elif kind == "parameters":
                parts.append("## Parameters")
                for p in sec.get("parameters", []):
                    parts.append(f"- **{p.get('name')}**: {self.blocks(p.get('content')).strip()}")
            elif kind == "properties":
                parts.append("## " + sec.get("title", "Properties"))
                for p in sec.get("items", []):
                    parts.append(f"- **{p.get('name')}**: {self.blocks(p.get('content')).strip()}")
        for sec in d.get("sections", []) or []:
            if "content" in sec:
                parts.append(self.blocks(sec.get("content")))
        for key in ("topicSections", "seeAlsoSections"):
            for sec in d.get(key, []) or []:
                parts.append("## " + sec.get("title", ""))
                for ident in sec.get("identifiers", []):
                    ref = self.refs.get(ident, {})
                    abstract = self.inline(ref.get("abstract"))
                    url = ref.get("url", "")
                    parts.append(f"- [{ref.get('title', ident)}]({BASE + url if url.startswith('/') else url}) — {abstract}")
        return "\n\n".join(p for p in parts if p and p.strip())


def main():
    manifest, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    retrieved = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    records = []
    for line in manifest.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        category, slug, source, mode = line.split("\t")
        outdir = root / category
        outdir.mkdir(parents=True, exist_ok=True)
        rec = {"category": category, "slug": slug, "mode": mode, "retrieved_utc": retrieved}

        if mode == "html":
            rec["source_url"] = source
            status, final, body, err = curl(source)
            ext = "html"
        elif mode == "doc":
            rec["source_url"] = f"{BASE}/{source}"
            json_url = f"{BASE}/tutorials/data/{source}.json"
            status, final, body, err = curl(json_url)
            rec["data_url"] = json_url
            ext = "json"
        else:  # hig
            page = f"{BASE}/design/human-interface-guidelines/{source}"
            _, page_final, _, _ = curl(page)
            final_slug = page_final.rstrip("/").rsplit("/", 1)[-1]
            rec["source_url"] = page_final
            json_url = f"{BASE}/tutorials/data/design/human-interface-guidelines/{final_slug}.json"
            status, final, body, err = curl(json_url)
            rec["data_url"] = json_url
            ext = "json"

        rec["http_status"] = status
        rec["final_url"] = final
        if status != 200 or not body:
            rec["result"] = "FAILED"
            rec["error"] = (err or f"HTTP {status}").strip()[:300]
            records.append(rec)
            print(f"FAIL {status} {category}/{slug}  {rec['source_url']}")
            continue

        raw_path = outdir / f"{slug}.{ext}"
        raw_path.write_bytes(body)
        rec["raw_file"] = str(raw_path.relative_to(root))
        rec["bytes"] = len(body)
        rec["sha256"] = hashlib.sha256(body).hexdigest()

        try:
            if ext == "html":
                md_body = html_to_md(body.decode("utf-8", errors="replace"))
                title_m = re.search(r"<title>(.*?)</title>", body.decode("utf-8", errors="replace"), re.S | re.I)
                rec["title"] = re.sub(r"\s+", " ", title_m.group(1)).strip() if title_m else slug
            else:
                data = json.loads(body)
                md_body = DocRenderer(data).render()
                rec["title"] = (data.get("metadata") or {}).get("title", slug)
            header = (f"<!--\nSource: {rec['source_url']}\nFinal URL: {final}\n"
                      f"Retrieved (UTC): {retrieved}\nRaw file: {raw_path.name}\n"
                      f"SHA-256 of raw: {rec['sha256']}\n"
                      "Extraction: automated text extraction for offline search; the raw file is authoritative.\n-->\n\n")
            md_path = outdir / f"{slug}.md"
            md_path.write_text(header + md_body)
            rec["markdown_file"] = str(md_path.relative_to(root))
            rec["markdown_chars"] = len(md_body)
            rec["result"] = "OK"
        except Exception as exc:  # keep the raw file even if extraction fails
            rec["result"] = "RAW_ONLY"
            rec["error"] = f"extraction failed: {exc}"
        records.append(rec)
        print(f"{rec['result']:8} {status} {category}/{slug}  ({rec.get('bytes', 0)} bytes)")

    manifest_path = root / "manifest.json"
    merged = {}
    if manifest_path.exists():
        for r in json.loads(manifest_path.read_text()):
            merged[(r["category"], r["slug"])] = r
    for r in records:
        merged[(r["category"], r["slug"])] = r
    manifest_path.write_text(json.dumps(sorted(merged.values(), key=lambda r: (r["category"], r["slug"])), indent=2))
    ok = sum(1 for r in records if r["result"] == "OK")
    print(f"\nDone: {ok}/{len(records)} OK")


if __name__ == "__main__":
    main()
