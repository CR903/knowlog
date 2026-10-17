#!/bin/bash
# setup_iteration3.sh — 准备 iteration-3 的刁钻用例（跨月补写 / 布局混用+陌生命名）
set -euo pipefail
WS="${1:?用法: bash evals/setup_iteration3.sh <workspace_dir>}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IT="$WS/iteration-3"
bash "$SKILL_DIR/evals/build_fixtures.sh" "$WS" > /dev/null
fx_of() { case "$1" in eval-5) echo proj-cross-month ;; eval-6) echo proj-layout-mix ;; esac; }
nm_of() { case "$1" in eval-5) echo cross-month-backfill ;; eval-6) echo layout-mixing-and-odd-names ;; esac; }
for id in eval-5 eval-6; do
  fx="$(fx_of "$id")"; nm="$(nm_of "$id")"; dir="$IT/${id}-${nm}"
  for cfg in with_skill without_skill; do
    rm -rf "$dir/$cfg"; mkdir -p "$dir/$cfg"; cp -R "$WS/fixtures/$fx/." "$dir/$cfg/"
    ( cd "$dir/$cfg" && rm -rf .git && git init -q . && git add -A >/dev/null 2>&1 \
      && git -c user.email=e@e -c user.name=e commit -qm "fixture: $id" >/dev/null 2>&1 ) || true
  done
  cat > "$dir/eval_metadata.json" <<JSON
{ "eval_id": "$id", "eval_name": "$nm", "fixture": "$fx",
  "run_dirs": { "with_skill": "$dir/with_skill", "without_skill": "$dir/without_skill" },
  "assertions": [] }
JSON
  echo "✅ $id ($nm) → $dir/{with_skill,without_skill}"
done
echo; echo "夹具预览（eval-5 应"很乱"）："
cd "$IT/eval-5-cross-month-backfill/with_skill" && find docs -name "*.md" | sort | sed 's/^/   /' && grep -n "2026-09-28\|待回填" docs/index.md | head -3 | sed 's/^/   /'
