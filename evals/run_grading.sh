#!/bin/bash
# run_grading.sh — 对 iteration-1 的全部运行做脚本评分 + 汇总成 benchmark
# 用法: bash evals/run_grading.sh <workspace_dir> [iteration_name]
set -euo pipefail

WS="${1:?用法: bash evals/run_grading.sh <workspace_dir> [iteration]}"
IT_NAME="${2:-iteration-1}"
IT="$WS/$IT_NAME"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 可选的第三方汇总/评审器（没有就跳过 benchmark 汇总，只出脚本评分）
SC="${BENCH_TOOL:-}"

echo "=== 0/3 清理旧的评审产物（产物复制在评分之后做，避免自污染结构自检） ==="
for d in "$IT"/eval-*; do
  [ -d "$d" ] || continue
  for cfg in with_skill without_skill; do
    rm -rf "$d/$cfg/run-1/outputs"
  done
done
echo "   done"

echo
echo "=== 1/3 脚本评分（grade.py） ==="
for d in "$IT"/eval-*; do
  [ -d "$d" ] || continue
  id="$(python3 -c "import json,sys;print(json.load(open('$d/eval_metadata.json'))['eval_id'])")"
  for cfg in with_skill without_skill; do
    [ -d "$d/$cfg" ] || continue
    mkdir -p "$d/$cfg/run-1"
    python3 "$SKILL_DIR/evals/grade.py" "$id" "$d/$cfg" "$d/$cfg/run-1/grading.json" || true
  done
done

echo
echo "=== 2/3 汇总 benchmark ==="
if [ -n "$SC" ] && [ -d "$SC/scripts" ]; then
  ( cd "$SC" && python3 -m scripts.aggregate_benchmark "$IT" --skill-name knowlog ) \
    || python3 "$SC/scripts/aggregate_benchmark.py" "$IT" --skill-name knowlog
else
  echo "  （跳过：未设置 BENCH_TOOL=<第三方汇总器路径>；脚本评分已完成，见各 run-1/grading.json）"
fi

echo
echo "=== 3/3 生成评审页面（静态 HTML） ==="
BENCH="$IT/benchmark.json"
if [ -n "$SC" ] && [ -f "$SC/eval-viewer/generate_review.py" ]; then
  python3 "$SC/eval-viewer/generate_review.py" "$IT" \
    --skill-name "knowlog" ${BENCH:+--benchmark "$BENCH"} \
    --static "$IT/review.html"
  echo "评审页面：$IT/review.html"
else
  echo "  （跳过：未设置 SKILL_CREATOR=…；grading.json 已就绪）"
fi


echo
echo "=== 4/4 收集评审产物（outputs/）— 放在评分之后，避免污染体检 ==="
for d in "$IT"/eval-*; do
  [ -d "$d" ] || continue
  for cfg in with_skill without_skill; do
    src="$d/$cfg"; run="$src/run-1"
    [ -d "$src" ] || continue
    mkdir -p "$run/outputs"
    for item in SUMMARY.md AGENTS.md CLAUDE.md opencode.json GEMINI.md docs scripts .claude .codex .opencode .cursor .github .dsh .githooks; do
      [ -e "$src/$item" ] && cp -R "$src/$item" "$run/outputs/" 2>/dev/null
    done
    cp "$d/eval_metadata.json" "$run/" 2>/dev/null || true
    echo "   + $run/outputs（$(find "$run/outputs" -type f | wc -l | tr -d ' ') 个文件）"
  done
done
