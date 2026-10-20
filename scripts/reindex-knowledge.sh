#!/bin/bash
# reindex-knowledge.sh — 从磁盘**反向重建/补齐**知识索引（只增不删，幂等）
#
# 为什么需要它：老项目的知识库往往是"文档写了一堆、索引只登记了一部分"。
# 让 `check-knowledge-index.sh` 变绿的正道不是手抄几十行，而是从磁盘把缺的行补回来
# （`new-knowledge.sh` 负责"新增"，本脚本负责"补齐存量"）。
#
# 行为：
#   · 只**新增**缺失的索引行，绝不删除/改写已有行（避免吃掉人工补充的说明文字）
#   · 说明列取文档首个 `# 标题`；来源列取文档头 `> 分类：… （来源：X）`，取不到则写"存量补录"
#   · 支持 flat 与 by-end 两种布局
#   · 先 dry-run（默认），`--apply` 才写盘
#
# 用法：
#   bash scripts/reindex-knowledge.sh                 # 只看会补哪些行
#   bash scripts/reindex-knowledge.sh --apply
set -euo pipefail

ROOT=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --apply) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$ROOT" ] || {
    _self="$(cd "$(dirname "$0")/.." && pwd)"
    # 非 git 目录：区分「项目内副本」与「skill/包本体」
    #   · skill/包本体（带 SKILL.md + assets/）→ 目标是**用户当前目录**
    #     （否则会写进 skill 自己——0.3.3 真机事故：npx 运行时体系建到了 npx 缓存包里）
    #   · 项目内副本 → 目标是项目根
    if [ -f "$_self/SKILL.md" ] && [ -d "$_self/assets" ]; then ROOT="$PWD"; else ROOT="$_self"; fi
  }
fi
export ROOT APPLY

python3 - <<'PY'
import os, pathlib, re, sys

root = pathlib.Path(os.environ["ROOT"]); KNOW = root / "docs" / "knowledge"
apply = os.environ["APPLY"] == "1"
CATS = ["architecture", "guides", "troubleshooting", "best-practices"]

if not KNOW.is_dir():
    print("❌ 没有 docs/knowledge/", file=sys.stderr); sys.exit(1)

end_dirs = [d for d in sorted(KNOW.iterdir())
            if d.is_dir() and d.name not in CATS and (d / "index.md").exists()]
layout = "by-end" if end_dirs else "flat"


def meta_of(p: pathlib.Path) -> tuple[str, str]:
    """从文档里取 (说明, 来源)：说明取首个一级标题，来源取头部元信息行"""
    title, source = p.stem, "存量补录"
    for line in p.read_text(encoding="utf-8", errors="ignore").splitlines()[:20]:
        if line.startswith("# ") and title == p.stem:
            title = line[2:].strip()
        m = re.search(r"（来源：(.+?)）|\(来源:(.+?)\)", line)
        if m:
            source = (m.group(1) or m.group(2) or "").strip()
            break
    return title, source


def append_row(index: pathlib.Path, heading: str, row: str) -> bool:
    """在 `## heading` 表格末尾追加（忽略已存在同路径行）"""
    if not index.exists():
        return False
    lines = index.read_text(encoding="utf-8").splitlines()
    rel = re.search(r"\]\(([^)]+)\)", row).group(1)
    if any(f"]({rel})" in l for l in lines):
        return False
    for i, l in enumerate(lines):
        if l.strip() == f"## {heading}":
            sep = next((j for j in range(i + 1, min(i + 9, len(lines)))
                        if lines[j].lstrip().startswith("|------")), None)
            if sep is None:
                lines[i + 1:i + 1] = ["", "| 文档 | 说明 | 来源 |", "|------|------|------|", row]
            else:
                last = sep
                for j in range(sep + 1, len(lines)):
                    if not lines[j].lstrip().startswith("|"):
                        break
                    last = j
                lines.insert(last + 1, row)
            if apply:
                index.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return True
    lines += ["", f"## {heading}", "", "| 文档 | 说明 | 来源 |", "|------|------|------|", row]
    if apply:
        index.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


def append_root_row(end: str | None, cat: str, rel_from_root: str, title: str, source: str) -> bool:
    """根索引：by-end 写进该端 section（4 列）；flat 写进分类 section（3 列）"""
    ri = KNOW / "index.md"
    if not ri.exists():
        return False
    lines = ri.read_text(encoding="utf-8").splitlines()
    if any(f"]({rel_from_root})" in l for l in lines):
        return False
    if end:
        sec = next((i for i, l in enumerate(lines)
                    if l.startswith("##") and f"docs/knowledge/{end}/" in l), None)
        row = f"| {cat} | [{pathlib.Path(rel_from_root).name}]({rel_from_root}) | {title} | {source} |"
        header = ["| 分类 | 文档 | 说明 | 来源 |", "|------|------|------|------|"]
    else:
        sec = next((i for i, l in enumerate(lines) if l.strip() == f"## {cat}"), None)
        row = f"| [{pathlib.Path(rel_from_root).name}]({rel_from_root}) | {title} | {source} |"
        header = ["| 文档 | 说明 | 来源 |", "|------|------|------|"]
    if sec is None:
        return False
    sep = next((j for j in range(sec + 1, min(sec + 9, len(lines)))
                if lines[j].lstrip().startswith("|------")), None)
    if sep is None:
        lines[sec + 1:sec + 1] = [""] + header + [row]
    else:
        last = sep
        for j in range(sep + 1, len(lines)):
            if not lines[j].lstrip().startswith("|"):
                break
            last = j
        lines.insert(last + 1, row)
    if apply:
        ri.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


added_end = added_root = 0
for end_dir in (end_dirs if layout == "by-end" else [None]):
    base = end_dir if end_dir is not None else KNOW
    for cat in CATS:
        for p in sorted((base / cat).glob("*.md")) if (base / cat).is_dir() else []:
            if p.name in {"README.md", "index.md"} or p.name.startswith("._"):
                continue
            title, source = meta_of(p)
            if end_dir is not None:
                rel_end = f"{cat}/{p.name}"
                rel_root = f"{end_dir.name}/{cat}/{p.name}"
                if append_row(end_dir / "index.md", cat, f"| [{p.name}]({rel_end}) | {title} | {source} |"):
                    added_end += 1
            else:
                rel_root = f"{cat}/{p.name}"
            if append_root_row(end_dir.name if end_dir is not None else None, cat, rel_root, title, source):
                added_root += 1

print(f"📚 reindex-knowledge（布局：{layout}{' · dry-run' if not apply else ' · 已写盘'}）")
print(f"   分端索引补齐：{added_end} 行 · 根索引补齐：{added_root} 行")
if not apply and (added_end or added_root):
    print("\n执行：bash scripts/reindex-knowledge.sh --apply")
if apply and (added_end or added_root):
    print("\n📝 补完记得记一笔（「我补了哪些索引、为什么之前漏了」值得留给未来）：bash scripts/new-daily-log.sh reindex-knowledge-index")
PY
