#!/bin/bash
# new-knowledge.sh — 新建一篇知识文档，并登记到索引（by-end 两级 / flat 单级）
#
# 「知识」= 可复用的坑位/规范/最佳实践，与「日志」互补：
#   日志是时序的（谁在何时做了什么），知识是结构化的（下次遇到同类问题看这条）。
# 只把「会重复踩 / 会被反复问」的东西沉淀成知识；一次性的任务细节留在日志里即可。
#
# 用法：
#   bash scripts/new-knowledge.sh <端> <分类> <kebab-name> "<一句话说明>" [--source "..."]   # by-end（多端项目）
#   bash scripts/new-knowledge.sh --flat <分类> <kebab-name> "<一句话说明>" [--source "..."] # flat（单面项目，无端层）
#
# 例：
#   bash scripts/new-knowledge.sh backend troubleshooting stale-binary-verify \
#     "接口验证跑的是旧二进制：源码比 main 新导致「改动没生效」误判" \
#     --source "docs/daily/2026-09/2026-09-15_baseline-test-ddl-fix.md"
#   分类 = architecture | guides | troubleshooting | best-practices
set -euo pipefail

ROOT=""; FLAT=0; END=""; CAT=""; NAME=""; DESC=""; SOURCE="今日任务"
while [ $# -gt 0 ]; do
  case "$1" in
    --flat) FLAT=1; shift ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --source=*) SOURCE="${1#--source=}"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *)
      if [ "$FLAT" -eq 1 ]; then
        if [ -z "$CAT" ]; then CAT="$1"
        elif [ -z "$NAME" ]; then NAME="$1"
        elif [ -z "$DESC" ]; then DESC="$1"
        else echo "❌ 多余参数：$1" >&2; exit 2; fi
      else
        if [ -z "$END" ]; then END="$1"
        elif [ -z "$CAT" ]; then CAT="$1"
        elif [ -z "$NAME" ]; then NAME="$1"
        elif [ -z "$DESC" ]; then DESC="$1"
        else echo "❌ 多余参数：$1" >&2; exit 2; fi
      fi
      shift ;;
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

[ -n "$CAT" ] && [ -n "$NAME" ] && [ -n "$DESC" ] || {
  echo "❌ 用法：bash scripts/new-knowledge.sh <端> <分类> <kebab-name> \"<说明>\"  或  --flat <分类> <kebab-name> \"<说明>\"" >&2; exit 2; }
case "$CAT" in
  architecture|guides|troubleshooting|best-practices) ;;
  *) echo "❌ 分类必须是 architecture / guides / troubleshooting / best-practices：$CAT" >&2; exit 2 ;;
esac
printf '%s' "$NAME" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || {
  echo "❌ 文件名必须是 kebab-case：$NAME" >&2; exit 2; }
printf '%s' "$DESC" | grep -q '|' && { echo "❌ 说明里不能含 |（会破坏索引表格）" >&2; exit 2; }

KNOW="$ROOT/docs/knowledge"
if [ "$FLAT" -eq 1 ]; then
  KDIR="$KNOW"; RELFROMROOT="$CAT/$NAME.md"
else
  [ -n "$END" ] || { echo "❌ 缺少端名（或用 --flat）" >&2; exit 2; }
  KDIR="$KNOW/$END"
  [ -d "$KDIR" ] || { echo "❌ 端目录不存在：docs/knowledge/${END}（先跑 bootstrap-docs.sh，或用 --flat）" >&2; exit 1; }
  RELFROMROOT="$END/$CAT/$NAME.md"
fi
TARGET="$KDIR/$CAT/$NAME.md"
[ -e "$TARGET" ] && { echo "❌ 已存在，未覆盖：docs/knowledge/$RELFROMROOT" >&2; exit 1; }

mkdir -p "$KDIR/$CAT"
# 用 python 渲染：说明里可能含 / & \ 等 sed 敏感字符（如「500mL/ml」），sed 会写坏甚至留 0 字节文件
TPL="$ROOT/docs/templates/knowledge-doc.md"
TARGET="$TARGET" TPL="$TPL" DESC="$DESC" ENDV="${END:-common}" CAT="$CAT" SOURCE="$SOURCE" python3 - <<'PY'
import datetime, os, pathlib, sys

out = pathlib.Path(os.environ["TARGET"])
if os.path.exists(os.environ["TPL"]):
    text = pathlib.Path(os.environ["TPL"]).read_text(encoding="utf-8")
    for k, v in {"<标题>": os.environ["DESC"], "<端>": os.environ["ENDV"],
                 "<分类>": os.environ["CAT"], "<YYYY-MM-DD>": datetime.date.today().isoformat(),
                 "<来源>": os.environ["SOURCE"]}.items():
        text = text.replace(k, v)
else:
    text = f"""# {os.environ['DESC']}

> 分类：{os.environ['CAT']} · 端：{os.environ['ENDV']} · 首次记录：{datetime.date.today().isoformat()}（来源：{os.environ['SOURCE']}）

## 症状 / 触发条件

（什么情况下会撞上它；给可观测的现象：报错、错数据、看起来"没生效"）

## 根因

（机制层面，而不是"当时改错了"）

## 正确做法

```bash
# 可直接复制执行的最小验证 / 修复步骤
```

## 判据（怎么确认已解决）

- [ ] 观察点 1
- [ ] 观察点 2

## 关联

- 任务日志：`{os.environ['SOURCE']}`
"""
try:
    out.write_text(text, encoding="utf-8")
except Exception as e:
    print(f"❌ 写入失败：{e}", file=sys.stderr); sys.exit(1)
if out.stat().st_size == 0:
    out.unlink(missing_ok=True)
    print("❌ 渲染结果为空，已清理半成品，中止", file=sys.stderr); sys.exit(1)
PY
echo "✅ 已创建知识文档：docs/knowledge/$RELFROMROOT"

ENDV="${END:-}" FLAT="$FLAT" CAT="$CAT" NAME="$NAME" DESC="$DESC" SOURCE="$SOURCE" ROOT="$ROOT" python3 - <<'PY'
import os, pathlib

root = pathlib.Path(os.environ["ROOT"])
flat = os.environ["FLAT"] == "1"
end = os.environ["ENDV"]; cat = os.environ["CAT"]; name = os.environ["NAME"]
desc = os.environ["DESC"]; source = os.environ["SOURCE"]


def append_row(path: pathlib.Path, heading: str, row: str) -> bool:
    """在 `## heading` 下的表格末尾追加一行；没有该 section 就在文件末尾新建"""
    if not path.exists():
        print(f"⚠️  跳过（不存在）：{path.relative_to(root)}")
        return False
    lines = path.read_text(encoding="utf-8").splitlines()
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
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return True
    lines += ["", f"## {heading}", "", "| 文档 | 说明 | 来源 |", "|------|------|------|", row]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


if flat:
    ok = append_row(root / "docs" / "knowledge" / "index.md", cat,
                    f"| [{name}.md]({cat}/{name}.md) | {desc} | {source} |")
    print("✅ 已登记索引：docs/knowledge/index.md → ## " + cat if ok else "⚠️  索引未更新")
else:
    ok1 = append_row(root / "docs" / "knowledge" / end / "index.md", cat,
                     f"| [{name}.md]({cat}/{name}.md) | {desc} | {source} |")
    print(f"✅ 已登记分端索引：docs/knowledge/{end}/index.md → ## {cat}" if ok1 else "⚠️  分端索引未更新")
    # 根索引：只往已存在的「本端 section」表格里追加，不猜结构
    ri = root / "docs" / "knowledge" / "index.md"
    done = False
    if ri.exists():
        lines = ri.read_text(encoding="utf-8").splitlines()
        sec = next((i for i, l in enumerate(lines)
                    if l.startswith("##") and f"docs/knowledge/{end}/" in l), None)
        if sec is not None:
            sep = next((j for j in range(sec + 1, min(sec + 9, len(lines)))
                        if lines[j].lstrip().startswith("|------")), None)
            row = f"| {cat} | [{name}.md]({end}/{cat}/{name}.md) | {desc} | {source} |"
            if sep is None:
                lines[sec + 1:sec + 1] = ["", "| 分类 | 文档 | 说明 | 来源 |",
                                          "|------|------|------|------|", row]
            else:
                last = sep
                for j in range(sep + 1, len(lines)):
                    if not lines[j].lstrip().startswith("|"):
                        break
                    last = j
                lines.insert(last + 1, row)
            ri.write_text("\n".join(lines) + "\n", encoding="utf-8")
            done = True
    print("✅ 已登记根索引：docs/knowledge/index.md" if done
          else f"⚠️  根索引未自动更新：请在 docs/knowledge/index.md 的「{end}」section 表格里手动追加一行")
PY
