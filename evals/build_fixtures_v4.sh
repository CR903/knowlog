#!/bin/bash
# build_fixtures_v4.sh — iteration-4 夹具（修掉 iteration-3 的评测设计缺陷）
#
# 与 iteration-1..3 的关键差别：
#   ① **不再把"已建好的体系"塞进夹具**（那是 iter-3 出现 0 差异的根因：两边都照抄现成结构）
#   ② 夹具只给"原始素材"：代码 + 散落/异构的旧文档 + 一个刚做完的任务描述
#   ③ 每个用例都标明"它到底想测什么能力"（见 evals-v4.json 的 measures 字段）
#
# 用法: bash evals/build_fixtures_v4.sh <workspace_dir>
set -uo pipefail
WS="${1:?用法: bash evals/build_fixtures_v4.sh <workspace_dir>}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FX="$WS/fixtures-v4"
rm -rf "$FX"; mkdir -p "$FX"

# ---------- 公共小工具 ----------
mkproj() {                      # $1=目录名 $2=模块名
  local d="$FX/$1"
  mkdir -p "$d"; cd "$d" || exit 1
  printf 'module example.com/%s\n\ngo 1.22\n' "$2" > go.mod
  cat > package.json <<'EOF'
{ "name": "order-service", "private": true, "version": "0.1.0" }
EOF
  cat > README.md <<'EOF'
# 订单服务

后端 Go（internal/order），运营后台 React（web/src）。
EOF
  mkdir -p internal/order web/src
  cat > internal/order/unit.go <<'EOF'
package order

// CalcConsume 把「入库单位」换算成「消耗单位」。
// 踩过的坑：调用方经常只乘一次导致差 10 倍。
func CalcConsume(instoreCount float64, packaging, consumeRate float64) float64 {
	return instoreCount * packaging * consumeRate
}
EOF
  cat > web/src/money.ts <<'EOF'
export const money = (n: number) => `¥${(n / 100).toFixed(2)}`;
EOF
  git init -q . 2>/dev/null || true
}

# ---------- 用例 A：全新项目（连 docs/ 都没有）→ 测"从零搭结构" ----------
mkproj v4-fresh demo-fresh
# 故意什么都不放：没有 docs/、没有 scripts/、没有 AGENTS.md

# ---------- 用例 B：一团乱的历史文档 → 测"采纳异构 + 反向补齐索引 + 建门禁" ----------
mkproj v4-messy demo-messy
mkdir -p docs/logs docs/daily docs/knowledge notes
cat > docs/logs/2026-09-01-money-format.md <<'EOF'
# 金额格式化（旧格式日志）

## 做了什么
后端金额以"分"传输，前端统一用 `money()` 转成 `¥x.xx`。

## 坑
`toFixed(2)` 在 -0.005 这类小数上会出 `-0.00`，已加 `Math.abs(n) < 1 ? 0 : n` 兜底。
EOF
cat > "docs/daily/2026-09-30_order-export.md" <<'EOF'
# 订单导出修复（裸放在 daily 根，没进月份目录）

## 做了什么
导出任务状态机漏了 `status=2`（失败）分支，导致失败任务一直显示"运行中"。

## 坑
状态枚举只写了 0/1，前端轮询遇到 2 就当成"还在跑"。
EOF
cat > docs/knowledge/excel-import.md <<'EOF'
# Excel 导入的列头匹配

（这份知识文档存在，但**没有任何 index.md 登记它**）
EOF
cat > docs/index.md <<'EOF'
# 文档索引

| 日期 | 日志 |
|---|---|
| 2026-09-01 | [金额格式化](daily/2026-09-02-money-format-ghost.md) |
EOF
cat > notes/todo.md <<'EOF'
# 临时随笔（非常规目录）
- 下个迭代要做导出重试
EOF

# ---------- 用例 C：体系已就位 + 刚做完的任务 → 测"收尾质量"（写日志/沉淀知识） ----------
mkproj v4-closeout demo-closeout
# 这个用例必须自带体系：任务本身就是"给体系里记一笔"，所以这里不算作弊；
# 它测的不是"能不能搭"，而是"写出来的日志/知识质量"（所以评分口径另设，见 grade_v4.py）
bash "$SKILL_DIR/scripts/bootstrap-docs.sh" --root "$FX/v4-closeout" --project-name demo-closeout > /dev/null 2>&1
cat > TASK.md <<'EOF'
# 本次刚做完的改动（供收尾记录用）

- 改了 `internal/order/unit.go`：`CalcConsume` 之前只乘 `consumeRate`，漏乘 `packaging`，
  导致"10 瓶/箱"的物品出库量被算成 1/10。现在 = instoreCount × packaging × consumeRate。
- 影响面：借用出库、直接出库两条链路；已补单测 `unit_test.go`（3 个用例，含 packaging=10 的回归）。
- 还没做的事：调拨链路的同类调用点没查过（`transfer.go` 里可能也有），打算下个任务处理。
EOF

echo "✅ iteration-4 夹具已生成：$FX"
ls -1 "$FX" | sed 's/^/   /'
