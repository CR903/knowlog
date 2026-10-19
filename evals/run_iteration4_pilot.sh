#!/bin/bash
# run_iteration4_pilot.sh — 把 iteration-4 的六个用例（带/不带 skill）跑完并出对照表
#
# 用法:
#   bash evals/run_iteration4_pilot.sh [workspace_dir]     # 默认 ${TMPDIR}/knowlog-iter4
#   FORCE_RERUN=1 bash evals/run_iteration4_pilot.sh       # 忽略已有评分，重跑
#
# 为什么串行：基线要把全局 skill 临时改name移开（见 run_case.sh），并行会互相污染。
# 为什么开头/结尾都要 restore：万一上一次被强杀，可能会留下 .hidden-<pid> 残留。
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS="${1:-${TMPDIR:-/tmp}/knowlog-iter4}"
IT="$WS/iteration-4"

restore_leftovers() {
  local d p base
  for d in "$HOME/.claude/skills" "$HOME/.config/opencode/skills" "$HOME/.agents/skills"; do
    for p in "$d"/*.hidden-*; do
      [ -e "$p" ] || continue
      base="${p%.hidden-*}"
      [ -e "$base" ] && continue          # 目标已存在就别动
      mv "$p" "$base" && echo "  [修复] 还原残留：$base"
    done
  done
}

restore_leftovers
echo "▶ 造/校验运行目录…"
bash "$SKILL_DIR/evals/setup_iteration4.sh" "$WS" > /dev/null || exit 1

for cs in eval-7-fresh-project-no-docs eval-8-messy-legacy-docs-adopt eval-9-closeout-after-real-task \
          eval-10-cross-month-backfill eval-11-index-drift-repair eval-12-single-end-flat-recall; do
  eid="$(printf %s "$cs" | cut -d- -f1-2)"   # eval-7 / eval-8 / eval-9（别用 ${cs%%-*}：会截成 eval）
  for cfg in with_skill without_skill; do
    RUN="$IT/$cs/$cfg"
    [ -d "$RUN" ] || { echo "  ⚠️ 缺运行目录：$RUN"; continue; }
    if [ -f "$RUN/grading.json" ] && [ -z "${FORCE_RERUN:-}" ]; then
      echo "⏭️  已有评分，跳过 $cs/$cfg"
    else
      echo "════ $cs / $cfg ════"
      bash "$SKILL_DIR/evals/run_case.sh" "$RUN" "$cfg" 2>&1 | tail -2
      python3 "$SKILL_DIR/evals/grade_v4.py" "$eid" "$RUN" "$RUN/grading.json" 2>&1 | head -1
    fi
    restore_leftovers                          # 每次跑完都确认一次全局状态
  done
done
restore_leftovers

echo
echo "════════ 对照表 ════════"
WS="$WS" python3 - <<'PY'
import json, os, pathlib
it = pathlib.Path(os.environ["WS"]) / "iteration-4"
rows = []
for cdir in sorted(p for p in it.iterdir() if p.is_dir()):
    row = {"case": cdir.name}
    for cfg in ("with_skill", "without_skill"):
        g = cdir / cfg / "grading.json"
        m = cdir / cfg / "run_meta.json"
        if g.exists():
            s = json.loads(g.read_text(encoding="utf-8"))["summary"]
            row[cfg] = f'{s["passed"]}/{s["total"]}'
        else:
            row[cfg] = "—（未跑）"
        if m.exists():
            meta = json.loads(m.read_text(encoding="utf-8"))
            row[cfg + "_files"] = meta.get("changed_files", "?")
        # 人工量表（若已填）
        mr = cdir / cfg / "manual_review.md"
        if mr.exists():
            txt = mr.read_text(encoding="utf-8")
            import re as _re
            mm = _re.search(r"\*\*合计\*\* \| \*\*(\d+)/6\*\*", txt)
            if mm:
                row[cfg + "_rubric"] = mm.group(1) + "/6"
    rows.append(row)

hdr = f'{"用例":<38} {"with_skill":<12} {"人工":<8} {"without_skill":<14} {"人工":<8}'
print(hdr); print("-" * len(hdr))
for r in rows:
    print(f'{r["case"]:<38} {r.get("with_skill","—"):<12} {r.get("with_skill_rubric","—"):<8} '
          f'{r.get("without_skill","—"):<14} {r.get("without_skill_rubric","—"):<8}')
print("\n注：结构断言 = knowlog 形状的 9/9/7/10/9/11 条客观判据；人工 = evals/review-rubric.md 的 D1+D2+D3（各 2 分）。")
PY
