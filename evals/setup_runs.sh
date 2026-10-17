#!/bin/bash
# setup_runs.sh — 建夹具并把每个 eval 的 with_skill / without_skill 运行目录准备好
# 用法: bash evals/setup_runs.sh <workspace_dir>
# 注意：用 bash 3.2（macOS 自带）可跑的写法，不用关联数组。
set -euo pipefail

WS="${1:?用法: bash evals/setup_runs.sh <workspace_dir>}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IT="$WS/iteration-1"

bash "$SKILL_DIR/evals/build_fixtures.sh" "$WS" > /dev/null

fixture_of() {
  case "$1" in
    eval-0) echo "proj-new" ;;
    eval-1) echo "proj-bootstrapped" ;;
    eval-2) echo "proj-broken" ;;
  esac
}
name_of() {
  case "$1" in
    eval-0) echo "bootstrap-new-project" ;;
    eval-1) echo "record-log-after-task" ;;
    eval-2) echo "fix-drift-existing" ;;
  esac
}

for id in eval-0 eval-1 eval-2; do
  fx="$(fixture_of "$id")"; nm="$(name_of "$id")"
  dir="$IT/${id}-${nm}"
  for cfg in with_skill without_skill; do
    rm -rf "$dir/$cfg"
    mkdir -p "$dir/$cfg"
    cp -R "$WS/fixtures/$fx/." "$dir/$cfg/"
    ( cd "$dir/$cfg" && rm -rf .git && git init -q . && git add -A > /dev/null 2>&1 && \
      git -c user.email=e@e -c user.name=e commit -qm "fixture: $id" > /dev/null 2>&1 ) || true
  done
  cat > "$dir/eval_metadata.json" <<EOF
{
  "eval_id": "$id",
  "eval_name": "$nm",
  "fixture": "$fx",
  "run_dirs": {
    "with_skill": "$dir/with_skill",
    "without_skill": "$dir/without_skill"
  },
  "assertions": []
}
EOF
  echo "✅ $id ($nm) → $dir/{with_skill,without_skill}"
done

echo
echo "夹具体检（eval-2/with_skill 应故意是坏的）："
cd "$IT/eval-2-fix-drift-existing/with_skill" && find docs/daily -name "*.md" | sort | sed 's/^/   /'
bash scripts/check-daily-index.sh 2>&1 | tail -8 | sed 's/^/   /'
