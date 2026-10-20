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

# ---------- 用例 D：跨月补写 + 索引占位 → 测"按任务日期归月" ----------
# 注意：这里的 docs/index.md 与一篇 10 月日志是"用户自己攒的旧文档"（原始素材），
# 不是已建好的 knowlog 体系 —— 没有 scripts/、没有 AGENTS.md、没有模板，索引只有 10 月一张表。
mkproj v4-backfill demo-backfill
mkdir -p docs/daily/2026-10 notes
cat > docs/daily/2026-10/2026-10-08_export-retry.md <<'EOF'
# 2026-10-08_export-retry 任务日志

## 概述
导出任务失败后不会重试，运维要手工点重跑。

## 做了什么
- 给导出任务加失败重试（最多 3 次，退避 5s）。

## 判据
- 手工造一条失败任务，重试后成功。
EOF
cat > docs/index.md <<'EOF'
# 开发日志索引

> 索引行格式：`| [日期](daily/<YYYY-MM>/<文件>) | 任务 | 工作内容 | 提交 | 备注 |`

## 📅 2026年

### 2026-10

| 日期 | 任务 | 工作内容 | 提交 | 备注 |
|------|------|----------|------|------|
| [2026-10-08](daily/2026-10/2026-10-08_export-retry.md) | 10-08-export-retry | 导出失败重试 | a1b2c3d | 已上线 |
EOF
cat > notes/2026-09-12-单位换算.md <<'EOF'
# 2026-09-12 记：单位换算差 10 倍

今天修了 `internal/order/unit.go` 的 `CalcConsume`：它之前只乘 `consumeRate`，
漏乘了 `packaging`，所以「10 瓶/箱」的物品出库量被算成 1/10。

- 改成：`instoreCount * packaging * consumeRate`
- 影响面：借用出库、直接出库两条链路
- 补了单测（含 packaging=10 的回归）
- 调拨链路 `transfer.go` 里可能也有同样的调用，还没查，下个任务处理
EOF
cat > notes/2026-10-15-金额精度.md <<'EOF'
# 2026-10-15 记：金额精度

前端 `money()` 用 `(n / 100).toFixed(2)`，遇到 -0.005 这类小数会出 `-0.00`；
已加 `Math.abs(n) < 1 ? 0 : n` 兜底。
EOF

# ---------- 用例 E：索引漂移 → 测"修复能力"（夹具必须自带体系，见 evals-v4.json 备案） ----------
# 这类用例的存在意义：项目已经有体系，但索引与磁盘对不上了。没有索引就无从"修"，
# 所以这里允许预置体系（由 bootstrap-docs.sh 生成），再人为注入四类漂移。
mkproj v4-drift demo-drift
bash "$SKILL_DIR/scripts/bootstrap-docs.sh" --root "$FX/v4-drift" --project-name demo-drift > /dev/null 2>&1
(
  cd "$FX/v4-drift" || exit 1
  PROJECT_NAME=demo-drift bash .knowlog/new-daily-log.sh paging-fix 2026-08-22 > /dev/null 2>&1
  PROJECT_NAME=demo-drift bash .knowlog/new-daily-log.sh idempotency 2026-09-05 > /dev/null 2>&1
  bash .knowlog/new-daily-log.sh audit-log 2026-10-11 > /dev/null 2>&1
  # 填实三篇日志正文（判"内容未丢失"用）
  cat > docs/daily/2026-08/2026-08-22_paging-fix.md <<'EOF'
# 2026-08-22_paging-fix 任务日志

## 概述
列表接口深分页在 offset 很大时全表扫描，慢查询。

## 做了什么
- 分页改为基于游标（keyset pagination），去掉 OFFSET。
- 判据：50 万行数据下，翻到第 10 万页仍在 20ms 内。
EOF
  cat > docs/daily/2026-09/2026-09-05_idempotency.md <<'EOF'
# 2026-09-05_idempotency 任务日志

## 概述
支付回调重复投递导致重复入账。

## 做了什么
- 回调处理加幂等键（out_trade_no + 事件类型），重复请求直接返回上一次结果。
- 判据：同一回调重放 3 次，账目只增一次。
EOF
  cat > docs/daily/2026-10/2026-10-11_audit-log.md <<'EOF'
# 2026-10-11_audit-log 任务日志

## 概述
关键写操作没有审计留痕，出了事查不到是谁改的。

## 做了什么
- 给订单状态变更加审计日志（操作人、前后值、时间）。
- 判据：手工改一次状态，审计表出现对应记录。
EOF
  # 先把三行索引填实（让夹具的"唯一毛病"就是下面注入的漂移，而不是占位）
  python3 - <<'PYX'
import pathlib
p = pathlib.Path("docs/index.md"); lines = p.read_text(encoding="utf-8").splitlines()
fill = {
 "daily/2026-08/2026-08-22_paging-fix.md": "| [2026-08-22](daily/2026-08/2026-08-22_paging-fix.md) | 08-22-paging-fix | 深分页改游标 | b1c2d3e | 已上线 |",
 "daily/2026-09/2026-09-05_idempotency.md": "| [2026-09-05](daily/2026-09/2026-09-05_idempotency.md) | 09-05-idempotency | 回调加幂等键 | c2d3e4f | 已上线 |",
 "daily/2026-10/2026-10-11_audit-log.md": "| [2026-10-11](daily/2026-10/2026-10-11_audit-log.md) | 10-11-audit-log | 关键写操作审计 | d3e4f5a | 已上线 |",
}
out = []
for l in lines:
    rep = None
    for rel, row in fill.items():
        if f"]({rel})" in l:
            rep = row; break
    out.append(rep if rep else l)
p.write_text("\n".join(out) + "\n", encoding="utf-8")
PYX
  # 漂移 ①：索引里加一条死链（指向不存在的文件）
  python3 - <<'PYX'
import pathlib
p = pathlib.Path("docs/index.md"); lines = p.read_text(encoding="utf-8").splitlines()
ghost = "| [2026-09-20](daily/2026-09/2026-09-20_reconcile-ghost.md) | 09-20-reconcile-ghost | 对账（目标文件已被删） | deadbee | 待查 |"
head = next(i for i, l in enumerate(lines) if l.strip() == "### 2026-09")
sep = next(j for j in range(head + 1, len(lines)) if lines[j].lstrip().startswith("|------"))
lines.insert(sep + 1, ghost)
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PYX
  # 漂移 ②：把 9 月日志挪进 10 月目录（目录月 ≠ 文件名月）
  mv docs/daily/2026-09/2026-09-05_idempotency.md docs/daily/2026-10/2026-09-05_idempotency.md
  # 漂移 ③：删掉 10-11 那篇的索引行（文件在、索引缺行）
  python3 - <<'PYX'
import pathlib
p = pathlib.Path("docs/index.md")
lines = p.read_text(encoding="utf-8").splitlines()
kept = [l for l in lines if "2026-10-11_audit-log.md" not in l]
p.write_text("\n".join(kept) + "\n", encoding="utf-8")
PYX
  # 漂移 ④：知识文档存在但没登记进知识索引
  cat > docs/knowledge/troubleshooting/redis-timeout.md <<'EOF'
# Redis 连接超时排查

现象：偶发 `i/o timeout`。根因：连接池 `PoolSize` 小于并发导出任务数。
处置：把 PoolSize 调到 ≥ 并发数，并设 `ReadTimeout`；详见日志。
EOF
  # 用户的"手写段落"：修索引时不许删（判"不是瞎改"）
  cat >> docs/index.md <<'EOF'

## 📌 团队约定（手写，勿删）

- 提交前必须跑 `bash .knowlog/docs-doctor.sh --quiet`。
EOF
)

# ---------- 用例 F：单面项目 flat 布局 + 关键词召回 → 测"不造端层 + 召回真能用" ----------
D="$FX/v4-flat"; mkdir -p "$D"; cd "$D" || exit 1
printf 'module example.com/csvtool\n\ngo 1.22\n' > go.mod
cat > README.md <<'EOF'
# csvtool

一个把内部数据导出成 CSV 的命令行小工具（只有 Go，一个面）。
EOF
mkdir -p cmd/export internal/export notes
cat > internal/export/csv.go <<'EOF'
package export

import "strings"

// csvColumns 返回导出 CSV 的固定列顺序。
// 踩过的坑：早期实现直接遍历 map 拼列，Go 的 map 遍历无序，
// 于是每次导出的列顺序都不一样，下游按固定列序解析时全错位。
func csvColumns() []string {
	return []string{"id", "name", "amount", "created_at"}
}

// Join 用固定列顺序把行拼成 CSV。
func Join(rows [][]string) string {
	var b strings.Builder
	b.WriteString(strings.Join(csvColumns(), ","))
	b.WriteString("\n")
	for _, r := range rows {
		b.WriteString(strings.Join(r, ","))
		b.WriteString("\n")
	}
	return b.String()
}
EOF
cat > cmd/export/main.go <<'EOF'
package main

import "fmt"

func main() { fmt.Println("csvtool: 导出内部数据为 CSV") }
EOF
cat > notes/导出列顺序.md <<'EOF'
# 坑：导出 CSV 列顺序会变

导出时直接遍历 map 拼列，Go 的 map 遍历无序，于是每次导出的列顺序都不一样，
下游按固定列顺序解析就全错位了。修法：用固定的列切片（见 `csvColumns`），不要遍历 map。
EOF
git init -q . 2>/dev/null || true

echo "✅ iteration-4 夹具已生成：$FX"
ls -1 "$FX" | sed 's/^/   /'
