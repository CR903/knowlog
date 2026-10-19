#!/bin/bash
# build_fixtures.sh — 为 knowlog 的评测准备三套夹具（可重复执行，先清空再建）
# 用法: bash evals/build_fixtures.sh <workspace_dir>
set -euo pipefail

WS="${1:?用法: bash evals/build_fixtures.sh <workspace_dir>}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FX="$WS/fixtures"
rm -rf "$FX"; mkdir -p "$FX"

make_base() {                       # $1=目录名  基础项目：Go 后端 + React 前端，尚无任何文档体系
  local d="$FX/$1"
  mkdir -p "$d"; cd "$d"
  git init -q .
  printf 'module example.com/%s\n\ngo 1.22\n' "$1" > go.mod
  cat > package.json <<'EOF'
{
  "name": "web",
  "private": true,
  "dependencies": { "react": "^18.2.0" }
}
EOF
  cat > README.md <<'EOF'
# 订单服务

一个 Go + React 的小服务：后端提供订单与库存接口，前端是运营后台。
EOF
  mkdir -p internal/order web/src
  printf 'package order\n\n// 单位换算：库存以"瓶"入库、以"mL"消耗\nfunc ConsumeRate(bottleML float64, mlPerUnit float64) float64 { return bottleML / mlPerUnit }\n' > internal/order/unit.go
  printf 'export const money = (n: number) => `¥${(n / 100).toFixed(2)}`;\n' > web/src/money.ts
  git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init || true
}

seed_log() {                        # $1=slug $2=日期 $3=正文
  bash "$SKILL_DIR/scripts/new-daily-log.sh" "$1" "$2" >/dev/null
  local f
  f=$(find docs/daily -name "*_$1.md" | head -1)
  printf '%s\n' "$3" > "$f"
}

seed_knowledge() {                  # $1=端 $2=分类 $3=name $4=说明
  bash "$SKILL_DIR/scripts/new-knowledge.sh" "$1" "$2" "$3" "$4" --source "初始化示例" >/dev/null
}

# ---------- fixture 1：全新项目（无任何文档体系） ----------
make_base proj-new

# ---------- fixture 2：已搭好体系、且有历史日志（用于"任务收尾记录"） ----------
make_base proj-bootstrapped
cd "$FX/proj-bootstrapped"
bash "$SKILL_DIR/scripts/bootstrap-docs.sh" --root "$(pwd)" --project-name "订单服务" >/dev/null
seed_log fix-money-format 2026-10-12 "# 2026-10-12_fix-money-format 任务日志

## 概述
- 背景：运营后台金额展示为 1299.00 分，应显示为 ¥12.99
- 目标：统一走 money() 工具函数
- 结果：3 处替换，回归通过

## 问题与解决
### 问题 1：金额单位混乱
- 现象：列表显示 1299.00
- 根因：有的组件直接用后端返回的分，有的用 money()
- 修法：统一调 money()
- 判据：\`grep -rn \"toFixed(2)\" web/src\` 无直出
"
seed_log add-order-export 2026-10-14 "# 2026-10-14_add-order-export 任务日志

## 概述
- 背景：运营需要导出订单
- 结果：新增 /orders/export，CSV 落 S3

## 测试与验证
- [x] 单测 2 条
- [x] 手工导出 200 行核对列顺序
"
seed_knowledge backend troubleshooting stale-binary-verify "接口验证跑的是旧二进制：源码比 main 新导致「改动没生效」误判"
seed_knowledge frontend guides money-format-single-source "金额展示必须走 money()：直出分值是历史遗留错误来源"

# ---------- fixture 3：被搞乱的体系（用于"体检修复"） ----------
cp -R "$FX/proj-bootstrapped" "$FX/proj-broken"
cd "$FX/proj-broken"
rm -rf .git; git init -q .; git add -A >/dev/null 2>&1
git -c user.email=e@e -c user.name=e commit -qm init || true
# ① 一篇日志散落到 daily 根（索引行稍后删掉）
git mv docs/daily/2026-10/2026-10-12_fix-money-format.md docs/daily/2026-10-12_fix-money-format.md
# ② 一篇日志的索引行被删掉（fix-money-format 在根，索引行也被删）
python3 - <<'PY'
import pathlib
p = pathlib.Path("docs/index.md"); s = p.read_text(encoding="utf-8")
keep = [l for l in s.splitlines() if "fix-money-format" not in l]
p.write_text("\n".join(keep) + "\n", encoding="utf-8")
PY
# ③ 另一篇的索引链接被改成旧的扁平路径
python3 - <<'PY'
import pathlib
p = pathlib.Path("docs/index.md"); s = p.read_text(encoding="utf-8")
p.write_text(s.replace("](daily/2026-10/2026-10-14_add-order-export.md)",
                       "](daily/2026-10-14_add-order-export.md)"), encoding="utf-8")
PY
# ④ 一篇日志的月份与目录不符（文件名是 9 月，却躺在 10 月目录里），且索引里没有它
cp docs/daily/2026-10/2026-10-14_add-order-export.md docs/daily/2026-10/2026-09-30_wrong-month.md
echo "（历史残留，文件名月份与目录不一致）" >> docs/daily/2026-10/2026-09-30_wrong-month.md

# ---------- fixture 4：已有异构文档（目录/命名都不按规范） ----------
make_base proj-messy-docs
cd "$FX/proj-messy-docs"
mkdir -p docs/logs docs/journal docs/knowledge/notes daily
printf '# 2026-08-01 修登录\n\n## 概述\n- 背景：登录态偶发失效\n- 根因：token 过期时间与刷新窗口不一致\n- 判据：连续刷新 50 次不掉线\n' > docs/logs/2026-08-01-fix-login.md
printf '# 2026-08-05 订单导出\n\n## 概述\n- 导出 CSV，按状态分组\n' > "docs/journal/2026-08-05_订单导出优化.md"
printf '# 2026-08-10 退款流程\n\n## 概述\n- 退款改为两步审批\n' > docs/journal/2026-08-10-refund-flow.md
printf '# 2026-09-02 对账差异\n\n## 概述\n- 差异按批次回写\n' > daily/2026-09-02-对账差异.md
printf '# 一些随手记的知识\n\n- 单位换算三段式容易漏\n' > docs/knowledge/notes/random-notes.md
cat > AGENTS.md <<'EOF'
# 订单服务 — Agent 指南

本项目使用 Go + React。代码风格遵循 gofmt / prettier。

## 用户手写的其它约定（这段不能被脚本覆盖）
- 提交信息用中文
- 不要直接改 migration 目录
EOF
printf '# 订单服务\n\nGo + React 的小服务。\n' > README.md
printf '# 变更日志\n\n- v0.1 初始化\n' > CHANGELOG.md
git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init >/dev/null 2>&1 || true

# ---------- fixture 5：单面项目（Python CLI，没有前后端之别） ----------
FX5="$FX/proj-cli-single"; mkdir -p "$FX5/src"; cd "$FX5"; git init -q .
printf '[project]\nname = "taskq"\nversion = "0.1.0"\ndependencies = ["typer", "rich"]\n' > pyproject.toml
printf 'import typer\n\napp = typer.Typer()\n\n@app.command()\ndef run(name: str) -> None:\n    """跑一个任务"""\n    typer.echo(f"running {name}")\n' > src/app.py
printf '# taskq\n\n一个命令行任务队列工具。\n' > README.md
git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init >/dev/null 2>&1 || true

# ---------- fixture 6：跨月补写 + 索引占位 + 散落日志 + 死链 ----------
make_base proj-cross-month          # 单面项目（1 端 → flat），避免把布局问题混进来
cd "$FX/proj-cross-month"
bash "$SKILL_DIR/scripts/bootstrap-docs.sh" --root "$(pwd)" --project-name "跨月项目" >/dev/null 2>&1
# 一篇 10 月的日志（内容真、但索引行仍是占位）
bash "$SKILL_DIR/scripts/new-daily-log.sh" cache-key-tenant 2026-10-05 >/dev/null
cat > docs/daily/2026-10/2026-10-05_cache-key-tenant.md <<'EOF'
# 2026-10-05_cache-key-tenant 任务日志

## 概述
- 背景：缓存串租户
- 目标：key 带上 tenantId
- 结果：已改

## 关键实现
`cacheKey = tenantId + ":" + key`
EOF
# 一篇 9 月的日志散落在 daily 根（未归月），索引里还留着一条指向扁平路径的死链
cat > docs/daily/2026-09-28_legacy-hotfix.md <<'EOF'
# 2026-09-28_legacy-hotfix 任务日志

## 概述
- 背景：上月底的紧急修复
- 结果：待补记
EOF
python3 - <<'PYX'
import pathlib
p = pathlib.Path("docs/index.md"); s = p.read_text(encoding="utf-8")
s += "| [2026-09-28](daily/2026-09-28_legacy-hotfix.md) | 09-28-legacy-hotfix | 待补记 | 待提交 | 待回填 |\n"
p.write_text(s, encoding="utf-8")
PYX
git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init >/dev/null 2>&1 || true

# ---------- fixture 7：知识库布局混用 + 陌生命名 ----------
make_base proj-layout-mix
cd "$FX/proj-layout-mix"
bash "$SKILL_DIR/scripts/bootstrap-docs.sh" --root "$(pwd)" --ends "backend frontend" --project-name "混用项目" >/dev/null 2>&1
# ① by-end 布局下又塞了一份 flat 的裸分类目录
mkdir -p docs/knowledge/troubleshooting
cat > docs/knowledge/troubleshooting/unit-three-stage.md <<'EOF'
# 单位换算三段式容易漏

> 分类：troubleshooting · 端：（未定） · 首次记录：2026-08-20（来源：随手记）

## 症状
箱→瓶→ml 少乘一步，数量差 10 倍。
EOF
# ② 一个非常规目录（随手记）
mkdir -p docs/knowledge/notes
cat > "docs/knowledge/notes/临时想法 与 待办.md" <<'EOF'
# 临时想法 与 待办（命名里带空格）

- 结算口径要跟财务对齐
EOF
# ③ 端目录里已有正经知识（必须保留）
cat > docs/knowledge/backend/troubleshooting/dup-order-cart.md <<'EOF'
# 同一物品在同一单里出现两行

> 分类：troubleshooting · 端：backend · 首次记录：2026-08-01（来源：老日志）

## 根因
按 GroupKey 合并时漏了 unitId。
EOF
git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init >/dev/null 2>&1 || true

echo "✅ 夹具就绪："
for d in "$FX"/*/; do
  n=0
  if [ -d "$d/docs" ]; then
    n=$(find "$d/docs" -name "*.md" | wc -l | tr -d ' ')
  fi
  echo "   $(basename "$d")  docs 下 md 文件: $n"
done
