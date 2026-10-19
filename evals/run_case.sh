#!/bin/bash
# run_case.sh — 在指定运行目录里跑一个用例（iteration-4 的标准跑法）
#
# 为什么要有它：iteration-1..3 的"带/不带 skill"只是人工约定，没有机械保证 ——
# 基线（without_skill）其实也能读到装在全局的 skill，于是"基线"并不干净。
# 这里把隔离做成**可执行的**，并把证据留在 run_meta.json 里：
#
#   without_skill：① 把已安装的 skill 临时移开（~/.claude/skills/knowlog 等）
#                  ② 再加 --disable-slash-commands（双保险）
#                  ③ 移开失败 → 直接中止（不许产出"假基线"）
#   with_skill   ：不动任何东西（skill 正常可被模型看见）
#
# 用法:
#   bash evals/run_case.sh <run_dir> with_skill|without_skill [--model <model-id>]
# 前置: run_dir 里要有 PROMPT.md（setup_iteration4.sh 会写好）
set -uo pipefail

RUN="${1:?用法: bash evals/run_case.sh <run_dir> with_skill|without_skill [--model M]}"
CFG="${2:?必须指定 with_skill 或 without_skill}"
shift 2 || true
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

case "$CFG" in with_skill|without_skill) ;; *) echo "❌ 配置只能是 with_skill / without_skill" >&2; exit 2 ;; esac
[ -f "$RUN/PROMPT.md" ] || { echo "❌ 缺少 $RUN/PROMPT.md（先用 setup_iteration4.sh 造运行目录）" >&2; exit 2; }
command -v claude >/dev/null || { echo "❌ 找不到 claude CLI" >&2; exit 2; }

HOMES="$(cd ~ && pwd)/.claude/skills/knowlog $(cd ~ && pwd)/.config/opencode/skills/knowlog $(cd ~ && pwd)/.agents/skills/knowlog"
TS="$$"; HIDDEN=""

hide_skill() {
  for p in $HOMES; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      if mv "$p" "$p.hidden-$TS" 2>/dev/null; then
        HIDDEN="$HIDDEN $p|$p.hidden-$TS"
        echo "  [隔离] 临时移开 $p"
      fi
    fi
  done
}
restore_skill() {
  for pair in $HIDDEN; do
    src="${pair%%|*}"; dst="${pair##*|}"
    if [ -e "$dst" ] || [ -L "$dst" ]; then mv "$dst" "$src" 2>/dev/null; fi
  done
}
trap restore_skill EXIT INT TERM

if [ "$CFG" = "without_skill" ]; then
  hide_skill
  # 完整性守卫：还看得见就说明隔离没生效，宁可中止也不产出假基线
  if [ -e "$(cd ~ && pwd)/.claude/skills/knowlog" ]; then
    echo "❌ 隔离失败（~/.claude/skills/knowlog 仍在）→ 中止" >&2
    exit 3
  fi
fi

cd "$RUN" || exit 1
PROMPT="$(cat PROMPT.md)"
ARGS=(-p "$PROMPT" --dangerously-skip-permissions --output-format text)
if [ "$CFG" = "without_skill" ]; then ARGS+=(--disable-slash-commands); fi
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")

START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "▶ 跑用例：${RUN}（$CFG${MODEL:+ · model=$MODEL}）"
claude "${ARGS[@]}" 2>&1 | tee transcript.txt
RC="${PIPESTATUS[0]}"
END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

RUN="$RUN" CFG="$CFG" MODEL="$MODEL" RC="$RC" START="$START" END="$END" HIDDEN="$HIDDEN" python3 - <<'PY'
import json, os, pathlib, subprocess
run = pathlib.Path(os.environ["RUN"])
def sh(*a):
    return subprocess.run(a, cwd=run, capture_output=True, text=True).stdout.strip()
changed = sh("git", "status", "--porcelain").splitlines()
meta = {
    "config": os.environ["CFG"],
    "model": os.environ["MODEL"] or "(默认)",
    "exit_code": int(os.environ["RC"]),
    "started_at": os.environ["START"],
    "finished_at": os.environ["END"],
    "isolation": {
        "moved_away": [p for p in os.environ.get("HIDDEN", "").split() if p],
        "disable_slash_commands": os.environ["CFG"] == "without_skill",
    },
    "changed_files": len(changed),
    "changed_sample": changed[:12],
}
(run / "run_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"  ↳ exit={meta['exit_code']} 改动文件={meta['changed_files']} → run_meta.json")
PY
echo "✅ 完成：${RUN}（transcript.txt / run_meta.json）"
