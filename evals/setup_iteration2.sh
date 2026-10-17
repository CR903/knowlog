#!/bin/bash
# setup_iteration2.sh — 准备 iteration-2 的三套运行目录（adopt / flat / record-log）
# 用法: bash evals/setup_iteration2.sh <workspace_dir>
set -euo pipefail

WS="${1:?用法: bash evals/setup_iteration2.sh <workspace_dir>}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IT="$WS/iteration-2"

bash "$SKILL_DIR/evals/build_fixtures.sh" "$WS" > /dev/null

fx_of() { case "$1" in eval-1) echo proj-bootstrapped ;; eval-3) echo proj-messy-docs ;; eval-4) echo proj-cli-single ;; esac; }
nm_of() { case "$1" in eval-1) echo record-log-after-task ;; eval-3) echo adopt-heterogeneous-docs ;; eval-4) echo flat-single-surface ;; esac; }

for id in eval-1 eval-3 eval-4; do
  fx="$(fx_of "$id")"; nm="$(nm_of "$id")"; dir="$IT/${id}-${nm}"
  for cfg in with_skill without_skill; do
    rm -rf "$dir/$cfg"; mkdir -p "$dir/$cfg"
    cp -R "$WS/fixtures/$fx/." "$dir/$cfg/"
    ( cd "$dir/$cfg" && rm -rf .git && git init -q . && git add -A >/dev/null 2>&1 \
      && git -c user.email=e@e -c user.name=e commit -qm "fixture: $id" >/dev/null 2>&1 ) || true
  done
  cat > "$dir/eval_metadata.json" <<EOF
{
  "eval_id": "$id",
  "eval_name": "$nm",
  "fixture": "$fx",
  "run_dirs": { "with_skill": "$dir/with_skill", "without_skill": "$dir/without_skill" },
  "assertions": []
}
EOF
  echo "✅ $id ($nm) → $dir/{with_skill,without_skill}"
done

echo
echo "夹具预览："
echo "--- proj-messy-docs 的日志分布（应很乱）---"
cd "$IT/eval-3-adopt-heterogeneous-docs/with_skill" && find . -name "*.md" -not -path "./.git/*" | sort | sed 's/^/   /'
