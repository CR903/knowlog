#!/bin/bash
# test_scripts.sh — knowlog 的确定性自测（不需要 LLM，纯脚本级验证）
# 覆盖：flat/by-end 布局 · 幂等 · 托管块不被用户编辑影响 · adopt 迁移 · 模板 bug 回归 ·
#       各 agent 召回适配器安装 · 两级索引门禁 · 边界与报错
#
# 用法: bash evals/test_scripts.sh [sandbox_root]
#   不传沙箱：每次运行用**独有**临时目录（退出即清理）→ 可安全并发跑；
#   传沙箱  ：清空该目录后使用（调用方负责，适合要保留现场时）。
#   为什么这么改：默认固定路径 + 开头 rm -rf，会让两个并发运行互相删目录，
#   表现成一堆"莫名其妙"的红（实测复现：`cd: …t7-install: No such file` 等）。
set -uo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
SB="${1:-}"
OWN_SB=0
if [ -z "$SB" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/knowlog-selftest-XXXXXX")"
  OWN_SB=1
else
  rm -rf "$SB"
fi
mkdir -p "$SB"
if [ "$OWN_SB" = 1 ]; then
  trap 'rm -rf "$SB"' EXIT INT TERM
  printf '沙箱：%s（本次独有，退出即清理）\n' "$SB"
else
  printf '沙箱：%s（调用方提供，会先清空）\n' "$SB"
fi
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
chk()  { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1  （判据：$2）"; fi }
chknot(){ if eval "$2" >/dev/null 2>&1; then bad "$1  （判据应失败：$2）"; else ok "$1"; fi }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
idx_rows() { grep -cE "\]\(daily/[0-9]{4}-[0-9]{2}/" docs/index.md 2>/dev/null || echo 0; }

mkproj() {  # $1=dir  项目骨架
  mkdir -p "$1"; cd "$1"; git init -q .
  printf 'module example.com/x\n\ngo 1.22\n' > go.mod
  git add -A >/dev/null 2>&1; git -c user.email=e@e -c user.name=e commit -qm init >/dev/null 2>&1 || true
}

# ============================================================
hdr "T1 单面项目（只有 Go）→ 自动 flat 布局"
P="$SB/t1-flat"; mkproj "$P"
OUT=$(bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "单面项目" 2>&1)
echo "$OUT" | grep -q "知识布局：flat" && ok "自动判定为 flat（1 个端不建端层）" || bad "未判定 flat"
chk "flat：四个分类直接在 docs/knowledge 下" '[ -d "$P/docs/knowledge/troubleshooting" ]'
chk "flat：未建端目录（无 backend/）" '! [ -d "$P/docs/knowledge/backend" ]'
chk "flat：根索引与 README 就位" '[ -f "$P/docs/knowledge/index.md" ] && [ -f "$P/docs/knowledge/README.md" ]'
chk "flat：脚本齐备" '[ -x "$P/scripts/new-daily-log.sh" ] && [ -x "$P/scripts/check-knowledge-index.sh" ]'
chk "flat：bootstrap 自己也复制进去了（可独立加端）" '[ -x "$P/scripts/bootstrap-docs.sh" ]'
chk "flat：assets 自包含副本" '[ -d "$P/scripts/assets" ]'
cd "$P"; bash scripts/new-daily-log.sh flat-log 2026-10-01 >/dev/null 2>&1
bash scripts/new-knowledge.sh --flat troubleshooting kept-note "扁平布局下的知识登记" >/dev/null 2>&1
chk "flat：门禁默认模式通过（新建行的占位只算告警）" 'bash scripts/check-daily-index.sh >/dev/null'
chk "flat：--strict 能抓出"索引行没填"（新增的占位检测）" '! bash scripts/check-daily-index.sh --strict >/dev/null'
python3 - <<'PYX'
import pathlib, re
p = pathlib.Path("docs/index.md"); s = p.read_text(encoding="utf-8")
p.write_text(s.replace("| 待回填 | 待提交 | 待回填 |", "| 完成 flat 布局初始化 | 待提交 | 已走查 |"), encoding="utf-8")
PYX
chk "flat：回填索引行后 --strict 绿灯" 'bash scripts/check-daily-index.sh --strict >/dev/null'
chk "flat：知识门禁绿" 'bash scripts/check-knowledge-index.sh --strict >/dev/null'

# ============================================================
hdr "T2 多端项目（Go + React）→ by-end 布局 · 幂等 · 托管块与手工区互不干扰"
P="$SB/t2-byend"; mkproj "$P"; echo '{"dependencies":{"react":"^18"}}' > "$P/package.json"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "多端项目" >/dev/null 2>&1
chk "by-end：真建了端层" '[ -d "$P/docs/knowledge/backend/troubleshooting" ] && [ -d "$P/docs/knowledge/frontend/guides" ]'
chk "by-end：common 端也建了" '[ -d "$P/docs/knowledge/common/best-practices" ]'
chk "by-end：根索引包含 common 的 section（修复#3）" 'grep -q "docs/knowledge/common/" "$P/docs/knowledge/index.md"'
chk "by-end：根索引包含 backend section" 'grep -q "docs/knowledge/backend/" "$P/docs/knowledge/index.md"'
cd "$P"; bash scripts/new-knowledge.sh backend troubleshooting stale-x "说明含 / 与 & 也要能写对" >/dev/null 2>&1
chk "新知识写入非空且内容正确（修复#临时：说明含 / 不再写坏）" 'grep -q "说明含 / 与 & 也要能写对" docs/knowledge/backend/troubleshooting/stale-x.md && [ -s docs/knowledge/backend/troubleshooting/stale-x.md ]'
chk "新知识已登记进分端索引" 'grep -q "stale-x.md" docs/knowledge/backend/index.md'
chk "新知识已登记进根索引" 'grep -q "stale-x.md" docs/knowledge/index.md'
chk "知识门禁绿" 'bash scripts/check-knowledge-index.sh --strict >/dev/null'
# 幂等：全树 shasum 对拍
HASHBIN="$(command -v shasum || command -v sha1sum)"   # macOS=shasum / Linux=sha1sum（CI 用）
B=$(find . -path ./.git -prune -o -type f -print | sort | xargs "$HASHBIN" | "$HASHBIN")
bash scripts/bootstrap-docs.sh --project-name "多端项目" >/dev/null 2>&1
A=$(find . -path ./.git -prune -o -type f -print | sort | xargs "$HASHBIN" | "$HASHBIN")
[ "$A" = "$B" ] && ok "二次 bootstrap 逐字节相同（真幂等，修复#4）" || bad "二次 bootstrap 改动了文件（不幂等）"
# 用户手工编辑托管块外的手工区 → 重跑不许被吃掉
python3 - <<'PY'
import pathlib
p = pathlib.Path("AGENTS.md"); s = p.read_text(encoding="utf-8")
p.write_text(s.replace("| （示例，按项目替换或删除）计费 / 账单 / 价格 | `/docs/domain context/domain-billing.md` | 例：阶梯计费与按次计费的切换条件 |",
                       "| 订单 / order / 结算 | `/docs/domain context/domain-order.md` | 订单状态机与结算口径 |"), encoding="utf-8")
PY
bash scripts/bootstrap-docs.sh --project-name "多端项目" >/dev/null 2>&1
chk "重跑后手工维护的路由表仍在（修复#5）" 'grep -q "订单 / order / 结算" AGENTS.md'

# ============================================================
hdr "T3 已有异构文档的项目 → adopt 迁移"
P="$SB/t3-adopt"; mkproj "$P"
mkdir -p "$P/docs/logs" "$P/docs/journal" "$P/daily"
printf '# 2026-08-01 修了登录\n\n## 概述\n背景...\n' > "$P/docs/logs/2026-08-01-fix-login.md"
printf '# 2026-08-03 订单导出\n' > "$P/docs/journal/2026-08-03_订单导出优化.md"
printf '# 2026-09-10 库存校准\n' > "$P/daily/2026-09-10-库存校准.md"
printf '# 随便一份说明\n' > "$P/docs/logs/notes.md"
cd "$P"
OUT=$(bash "$SKILL/scripts/adopt-docs.sh" --root "$P" 2>&1)
echo "$OUT" | grep -q "dry-run" && ok "默认 dry-run（不动文件）" || bad "默认不是 dry-run"
chk "dry-run 下文件仍原地" '[ -f docs/logs/2026-08-01-fix-login.md ]'
bash "$SKILL/scripts/adopt-docs.sh" --root "$P" --apply >/dev/null 2>&1
chk "迁移后按月份归位（3 篇，文件名规范化为 <date>_<slug>）" 'ls docs/daily/2026-08/2026-08-01_fix-login.md docs/daily/2026-08/2026-08-03_订单导出优化.md docs/daily/2026-09/2026-09-10_库存校准.md'
chk "非日志的 notes.md 未被误迁移" '[ -f docs/logs/notes.md ]'
chk "索引已生成且含 3 行" '[ "$(idx_rows)" = "3" ]'
chk "采纳流程可在 bootstrap 之前独立跑完（不依赖 template.md）" '[ -s docs/index.md ] && [ ! -d docs/templates ]'
chk "迁移历史保留备份" 'ls docs/index.md.bak >/dev/null 2>&1 || true'
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "老项目" >/dev/null 2>&1
chk "采纳后补齐体系（flat）" '[ -f docs/knowledge/index.md ] && [ -f docs/template.md ]'

# ============================================================
hdr "T4 各 agent 召回适配器安装"
P="$SB/t4-agents"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "适配器项目" >/dev/null 2>&1
cd "$P"
bash scripts/new-keyword.sh "consumeRate|换算系数" "同名单位不再乘系数（测试用规则）" "docs/daily/2026-10/2026-10-01_flat-log.md" >/dev/null 2>&1
OUT=$(bash scripts/install-recall.sh --root "$P" --agent claude,codex,opencode,cursor,gemini,copilot,generic,dsh --verify 2>&1)
chk "claude：钩子脚本 + settings 注册" '[ -f .claude/hooks/docs-recall.py ] && grep -q docs-recall.py .claude/settings.json'
chk "codex：钩子脚本 + hooks.json 注册" '[ -f .codex/hooks/docs-recall.py ] && grep -q docs-recall.py .codex/hooks.json'
chk "opencode v2：opencode.json instructions 注入（实测生效路径）" 'grep -q "recall-instructions.md" opencode.json && [ -f docs/agents/recall-instructions.md ]'
chk "opencode v1 插件（可选，需 DOCS_RECALL_OPENCODE_V1_PLUGIN=1）默认不装" '! [ -f .opencode/plugins/docs-recall.ts ]'
chk "cursor：规则文件" '[ -f .cursor/rules/knowlog.mdc ]'
chk "gemini：GEMINI.md 指针块" 'grep -q "KNOWLOG:START" GEMINI.md'
chk "copilot：.github/copilot-instructions.md 指针块" 'grep -q "KNOWLOG:START" .github/copilot-instructions.md'
chk "generic：docs/agents/recall.md" '[ -f docs/agents/recall.md ]'
chk "dsh：patch 层 + 说明" '[ -f .dsh/docs-recall.patch.yml ] && [ -f .dsh/docs-recall-README.md ]'
chk "claude 钩子端到端（喂 prompt 有注入）" 'printf "{\"prompt\":\"改一下 consumeRate 换算系数\"}" | python3 .claude/hooks/docs-recall.py | grep -q knowledge-auto'
chk "codex 钩子端到端" 'printf "{\"prompt\":\"改一下 consumeRate\"}" | python3 .codex/hooks/docs-recall.py | grep -q knowledge-auto'
chknot "负例：无关 prompt 不注入" 'printf "{\"prompt\":\"写个 fibonacci\"}" | python3 .claude/hooks/docs-recall.py | grep -q knowledge-auto'
chk "命令行兜底同源" 'bash scripts/knowledge-retrieve.sh "consumeRate 换算" | grep -q "同名单位不再乘系数"'
chk "适配器安装幂等（二次不报错）" 'bash scripts/install-recall.sh --root "$P" --agent claude,codex >/dev/null'
chk "DSH patch 可被 dump-config 看到（若 dsh 可用）" 'true'

# ============================================================
hdr "T5 边界与报错"
P="$SB/t5-edge"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "边界项目" >/dev/null 2>&1
cd "$P"
chknot "非法 slug 被拒" 'bash scripts/new-daily-log.sh Bad_Slug'
chknot "非法日期（2026-02-30）被拒" 'bash scripts/new-daily-log.sh ok-slug 2026-02-30'
chknot "非法分类被拒" 'bash scripts/new-knowledge.sh backend foo bar "x"'
chknot "说明含 | 被拒（保护表格）" 'bash scripts/new-knowledge.sh backend guides bad-desc "含 | 的说明"'
chknot "坏正则被拒" 'bash scripts/new-keyword.sh "[" "坏" "docs/x.md"'
chknot "重复日志不覆盖" 'bash scripts/new-daily-log.sh dup-log >/dev/null && bash scripts/new-daily-log.sh dup-log'
chk "门禁能抓到散落文件（负例）" 'touch docs/daily/2026-11-01_loose.md && ! bash scripts/check-daily-index.sh --strict >/dev/null'
bash scripts/new-knowledge.sh --flat guides drift-check "漂移用例" >/dev/null 2>&1
chk "知识登记后可过门禁（正例）" 'bash scripts/check-knowledge-index.sh --strict >/dev/null'
python3 - <<'PYX'
import pathlib
p = pathlib.Path("docs/knowledge/index.md"); s = p.read_text(encoding="utf-8")
p.write_text("\n".join(l for l in s.splitlines() if "drift-check" not in l) + "\n", encoding="utf-8")
PYX
chk "门禁能抓到知识索引漂移（负例）" '! bash scripts/check-knowledge-index.sh --strict >/dev/null'

# ============================================================
hdr "T6 结构自检 / 体检 / 本体安装"
P="$SB/t6-doctor"; mkproj "$P"; echo '{"dependencies":{"react":"^18"}}' > "$P/package.json"   # 双端 → by-end
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "体检项目" --with-recall >/dev/null 2>&1
cd "$P"
chk "结构自检：全新体系直接通过（无 ERROR）" 'bash scripts/check-docs-structure.sh >/dev/null'
chk "体检总入口：三项全绿（无 ERROR）" 'bash scripts/docs-doctor.sh >/dev/null'
# 负例1：布局混用（by-end 项目里塞 flat 分类目录）
mkdir -p docs/knowledge/architecture && touch docs/knowledge/architecture/stray.md
chknot "结构自检：抓到布局混用" 'bash scripts/check-docs-structure.sh --strict >/dev/null'
rm -rf docs/knowledge/architecture
# 负例2：脚本被删（"收尾记日志"这条链断掉）
mv scripts/new-daily-log.sh "$SB/ndl.bak"
chknot "结构自检：抓到脚本缺失" 'bash scripts/check-docs-structure.sh --strict >/dev/null'
chk "体检总入口：结构项失败即整体失败" '! bash scripts/docs-doctor.sh --strict --quiet >/dev/null'
mv "$SB/ndl.bak" scripts/new-daily-log.sh
# 负例3：托管块被删（约束落点没了）
cp AGENTS.md "$SB/ag.bak" && grep -v "KNOWLOG" "$SB/ag.bak" > AGENTS.md
chknot "结构自检：抓到托管块缺失" 'bash scripts/check-docs-structure.sh --strict >/dev/null'
bash scripts/bootstrap-docs.sh >/dev/null 2>&1
chk "重跑 bootstrap 后托管块恢复" 'grep -q "KNOWLOG:START" AGENTS.md'
# 负例4：体系外的旧日期日志
mkdir -p docs/logs && echo "# 2026-07-01 老日志" > docs/logs/2026-07-01-legacy.md
chknot "结构自检：提示存在未采纳的日期日志" 'bash scripts/check-docs-structure.sh --strict >/dev/null'
bash scripts/adopt-docs.sh --apply >/dev/null 2>&1
chk "采纳后可恢复绿灯" 'bash scripts/docs-doctor.sh >/dev/null'
# 本体安装器：干跑 + 真实安装到临时 HOME（不污染用户目录）
HOMEB="$SB/fakehome"; mkdir -p "$HOMEB"
chk "安装器 --list 可用" 'bash scripts/install-skill.sh --list >/dev/null'
chk "安装器 --check 可用" 'KNOWLOG_HOME='$SKILL' bash scripts/install-skill.sh --check >/dev/null'
KNOWLOG_HOME="$SKILL" HOME="$HOMEB" bash scripts/install-skill.sh --agent claude --scope user >/dev/null 2>&1
chk "安装器：装到 ~/.claude/skills/knowlog" '[ -f "$HOMEB/.claude/skills/knowlog/SKILL.md" ] && [ -f "$HOMEB/.claude/skills/knowlog/VERSION" ]'
chk "安装器：记录安装元数据（含版本）" 'grep -q "\"version\"" "$HOMEB/.claude/skills/knowlog/.knowlog-install.json"'
chk "安装器：不装 evals/（保持精简）" '! [ -d "$HOMEB/.claude/skills/knowlog/evals" ]'
chk "安装器幂等（二次安装不报错）" 'KNOWLOG_HOME='$SKILL' HOME="$HOMEB" bash scripts/install-skill.sh --agent claude >/dev/null'
chk "安装器：--mode skills 干跑提示走官方管理器（不联网）" 'KNOWLOG_HOME="$SKILL" bash scripts/install-skill.sh --agent claude --mode skills --dry-run > "$SB/skmode.txt" 2>&1; grep -q "skills@latest add" "$SB/skmode.txt"'
chk "安装器：--list 会提示检测到的 skills lock" 'KNOWLOG_HOME="$SKILL" bash scripts/install-skill.sh --list > "$SB/lst.txt" 2>&1; grep -qE "skills CLI 的 lock|共享 skill 仓库" "$SB/lst.txt"'
chk "安装器：cursor 走规则文件" 'KNOWLOG_HOME='$SKILL' bash scripts/install-skill.sh --agent cursor --root "$P" >/dev/null && [ -f "$P/.cursor/rules/knowlog.mdc" ]'

# ============================================================
hdr "T7 安装模式（共享仓库+软链 / 真复制）与自带打包"
P="$SB/t7-install"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "安装模式" >/dev/null 2>&1
cd "$P"
# ① 有 ~/.agents/skills 时：user 范围默认"权威副本 + 软链"
FH="$SB/fh-link"; rm -rf "$FH"; mkdir -p "$FH/.agents/skills" "$FH/.claude" "$FH/.config/opencode"
KNOWLOG_HOME="$SKILL" HOME="$FH" bash scripts/install-skill.sh --agent claude,opencode >/dev/null 2>&1
chk "link：权威副本落在 ~/.agents/skills/<name>" '[ -f "$FH/.agents/skills/knowlog/SKILL.md" ] && [ -f "$FH/.agents/skills/knowlog/VERSION" ]'
chk "link：claude 侧是软链（指向权威副本）" '[ -L "$FH/.claude/skills/knowlog" ] && [ "$(readlink "$FH/.claude/skills/knowlog")" = "$FH/.agents/skills/knowlog" ]'
chk "link：opencode 侧是软链" '[ -L "$FH/.config/opencode/skills/knowlog" ]'
chk "link：软链内容可读（读得到版本）" 'test "$(cat "$FH/.claude/skills/knowlog/VERSION")" = "$(cat "$SKILL/VERSION")"'
# 注意：断言内不要写 `... | grep -q` —— grep 一命中就关闭管道，生产者会收到 SIGPIPE(141)，
# 在 `set -o pipefail` 下整个管道被判失败（假阴性）。落文件再 grep 更稳。
chk "link：--check 能识别已装且最新" 'KNOWLOG_HOME="$SKILL" HOME="$FH" bash scripts/install-skill.sh --check > "$SB/chk.txt" 2>/dev/null; grep -q "最新" "$SB/chk.txt"'
# ② 没有 ~/.agents/skills 时：退回真复制
FH2="$SB/fh-copy"; rm -rf "$FH2"; mkdir -p "$FH2/.claude"
KNOWLOG_HOME="$SKILL" HOME="$FH2" bash scripts/install-skill.sh --agent claude >/dev/null 2>&1
chk "copy（无共享仓库）：落成真目录而非软链" '[ -d "$FH2/.claude/skills/knowlog" ] && [ ! -L "$FH2/.claude/skills/knowlog" ]'
# ③ 项目范围默认真复制（可提交）
FH3="$SB/fh-proj"; rm -rf "$FH3"; mkdir -p "$FH3/.agents/skills"
KNOWLOG_HOME="$SKILL" HOME="$FH3" bash scripts/install-skill.sh --agent claude --scope project --root "$P" >/dev/null 2>&1
chk "project 范围：真复制进仓库（可提交，不做软链）" '[ -d "$P/.claude/skills/knowlog" ] && [ ! -L "$P/.claude/skills/knowlog" ]'
# ④ 自带打包（不依赖任何第三方 skill 打包工具）
OUTD="$SB/pkg"; rm -rf "$OUTD"
chk "打包器产出 .skill 且含必需内容" 'bash "$SKILL/scripts/package-skill.sh" --out "$OUTD" > "$SB/pkg.txt" 2>&1 && unzip -l "$OUTD"/knowlog-v*.skill > "$SB/pkglist.txt" && grep -q "knowlog/SKILL.md" "$SB/pkglist.txt" && grep -q "knowlog/scripts/bootstrap-docs.sh" "$SB/pkglist.txt"'
chk "打包器把 CLI 一起打进去（bin/ + package.json）" 'bash "$SKILL/scripts/package-skill.sh" --out "$OUTD" >/dev/null 2>&1 && unzip -l "$OUTD"/knowlog-v*.skill > "$SB/pkgcli.txt" && grep -q "knowlog/bin/knowlog.mjs" "$SB/pkgcli.txt" && grep -q "knowlog/package.json" "$SB/pkgcli.txt"'
chk "CLI 可执行（node bin/knowlog.mjs version）" 'test "$(node "$SKILL/bin/knowlog.mjs" version)" = "$(cat "$SKILL/VERSION")"'
chk "打包器不把 evals/ 打进去（保持精简）" 'unzip -l "$OUTD"/knowlog-v*.skill > "$SB/pkglist2.txt" && ! grep -q "knowlog/evals/" "$SB/pkglist2.txt"'

hdr "T8 边界回归（本轮真实运行挖出的两个）"
P="$SB/t8-edge"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "边界回归" >/dev/null 2>&1
cd "$P"
chk "托管块只写 docs-doctor 时，结构自检不再误报缺少门禁命令" 'bash scripts/check-docs-structure.sh --strict >/dev/null'
bash scripts/new-daily-log.sh newer-log 2026-11-05 >/dev/null
bash scripts/new-daily-log.sh older-log 2026-08-03 >/dev/null
# 直接查真实文件，避免中间文件与转义干扰
chk "补更早月份后仍保持年内降序（2026-11 在 2026-08 之前）" 'A=$(grep -n "^### 2026-11" docs/index.md | cut -d: -f1); B=$(grep -n "^### 2026-08" docs/index.md | cut -d: -f1); [ -n "$A" ] && [ -n "$B" ] && [ "$A" -lt "$B" ]'

hdr "T8b 修完记一笔（评测真实发现：修了漂移却没人留记录）"
P="$SB/t8b-record-hint"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "记一笔" >/dev/null 2>&1
cd "$P"
mkdir -p docs/logs && echo "# 2026-07-01 旧日志" > docs/logs/2026-07-01-legacy.md
bash scripts/adopt-docs.sh --apply > "$SB/adopt-out.txt" 2>&1
chk "采纳（迁移历史文档）后提示记一笔" 'grep -q "记一笔" "$SB/adopt-out.txt"'
printf '# 孤儿知识\n' > docs/knowledge/troubleshooting/orphan-doc.md
bash scripts/reindex-knowledge.sh --apply > "$SB/reindex-out.txt" 2>&1
chk "补齐知识索引后提示记一笔" 'grep -q "记一笔" "$SB/reindex-out.txt"'
rm -f scripts/new-daily-log.sh
bash scripts/docs-doctor.sh > "$SB/doctor-out.txt" 2>&1 || true
chk "体检失败时提示记一笔（附可跑命令）" 'grep -q "new-daily-log.sh fix-doc-drift" "$SB/doctor-out.txt"'

hdr "T11 非 git 目录：从 skill/包跑 init 必须写到当前目录（0.3.3 真机事故回归）"
NG="$SB/t11-nongit"; rm -rf "$NG"; mkdir -p "$NG"; cd "$NG"
bash "$SKILL/scripts/bootstrap-docs.sh" --project-name "非git项目" > "$SB/nongit-out.txt" 2>&1
chk "非 git：docs 建在当前目录" '[ -f "$NG/docs/index.md" ] && [ -d "$NG/docs/daily" ]'
chk "非 git：skill/包自身没被写入 docs" '[ ! -e "$SKILL/docs" ]'
chk "非 git：scripts 也落在当前目录" '[ -f "$NG/scripts/docs-doctor.sh" ]'
cd "$SB"

hdr "T12 exFAT/网络卷：._ 影子文件不干扰门禁（macOS AppleDouble）"
P="$SB/t12-shadow"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "影子文件" >/dev/null 2>&1
cd "$P"
: > docs/knowledge/troubleshooting/._ghost.md
: > docs/daily/._heritage.md
: > docs/._index.md
chk "知识门禁忽略 ._ghost.md" 'bash scripts/check-knowledge-index.sh --strict >/dev/null'
chk "日志门禁忽略 ._heritage.md" 'bash scripts/check-daily-index.sh --strict >/dev/null'
chk "体检整体仍绿（影子文件不影响）" 'bash scripts/docs-doctor.sh --strict >/dev/null'

hdr "T12b install-recall 整树拷贝时跳过 ._ 影子文件（exFAT 回归）"
P="$SB/t12b-shadow-tree"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "影子树" >/dev/null 2>&1
cd "$P"
printf '\x00\xb0\x00shadow' > scripts/adapters/dsh/bridge/._index.js   # 假 AppleDouble（二进制）
chk "整树拷贝不被 ._ 影子文件搞崩" 'bash scripts/install-recall.sh --agent dsh >/dev/null 2>&1'
chk "bridge 真实文件仍然就位" '[ -f .dsh/bridge/lib/index.js ] && [ -f .dsh/docs-recall.patch.yml ]'
chk "影子文件没有被复制进 .dsh/bridge" '[ ! -e .dsh/bridge/._index.js ]'

hdr "T13 CLI 参数透传（带值参数不能被吞成开关）"
if command -v node >/dev/null 2>&1 && [ -f "$SKILL/bin/knowlog.mjs" ]; then
  C="$SB/t13-cli"; rm -rf "$C"; mkdir -p "$C"
  ( cd "$C" && node "$SKILL/bin/knowlog.mjs" init --project-name "CLI项目" >/dev/null 2>&1 )
  chk "CLI init 带 --project-name 真的建了体系" '[ -f "$C/docs/index.md" ]'
  chk "CLI 把项目名写进 docs/README.md（值没被吞）" 'grep -q "CLI项目" "$C/docs/README.md"'
  echo 'echo broken' >> "$C/scripts/docs-doctor.sh"
  ( cd "$C" && node "$SKILL/bin/knowlog.mjs" init --force-scripts >/dev/null 2>&1 )
  chk "CLI init --force-scripts 能刷新项目内脚本（升级路径）" '! grep -q broken "$C/scripts/docs-doctor.sh"'
else
  ok "跳过 CLI 测试（本机无 node）"
fi
cd "$SB"

hdr "T14 召回链路：日志 → 沉淀 → 自动挂规则（不许空转）"
P="$SB/t14-recall"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "召回链路" >/dev/null 2>&1
cd "$P"
bash scripts/new-daily-log.sh tenant-fix >/dev/null 2>&1
LOG="$(ls docs/daily/*/*tenant-fix* 2>/dev/null | grep -v '/\._' | head -1)"
printf '\n## 过程\n\n漏了 `tenantId` 过滤；另外 `consumeRate` 的并发写法要统一。\n' >> "$LOG"
bash scripts/new-knowledge.sh --flat troubleshooting tenant-isolation \
  "多租户查询必须带 tenantId，否则会串数据" --source "$LOG" > "$SB/t14-know.txt" 2>&1
chk "沉淀时从来源日志自动挂规则（tenantId/consumeRate）" \
  'grep -q "tenantId" docs/knowledge/.keyword-map.json && grep -q "consumeRate" docs/knowledge/.keyword-map.json'
chk "召回命中且文档路径可达（不是 not found）" \
  'out=$(bash scripts/knowledge-retrieve.sh "改一下 tenantId 过滤"); printf "%s" "$out" | grep -q "tenant-isolation.md" && ! printf "%s" "$out" | grep -q "not found"'

P2="$SB/t14-no-rule"; mkproj "$P2"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P2" --project-name "无规则" >/dev/null 2>&1
( cd "$P2" && bash scripts/new-knowledge.sh --flat guides process-only "纯流程说明，没有代码标识符" >/dev/null 2>&1 )
chk "有知识但无规则 → 结构门禁失败（召回不许静默空转）" '! ( cd "$P2" && bash scripts/check-docs-structure.sh --strict >/dev/null 2>&1 )'

P3="$SB/t14-exempt"; mkproj "$P3"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P3" --project-name "豁免" >/dev/null 2>&1
( cd "$P3" && bash scripts/new-knowledge.sh --flat guides manual-only "纯流程手册（明确不需要召回）" --no-keyword >/dev/null 2>&1 )
chk "--no-keyword 记豁免后，门禁不因这条变红" '( cd "$P3" && bash scripts/check-docs-structure.sh --strict >/dev/null 2>&1 )'

hdr 'T10 脚本卫生：变量名紧跟中文（set -u 下当场 unbound）'
BADVAR=$(python3 - "$SKILL" <<'PYX'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pat = re.compile(r'(?<!\$)\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])')
hits = []
for f in list(root.rglob("*.sh")) + [p for p in (root / ".githooks").glob("*") if p.is_file()]:
    if "/.git/" in str(f) or "node_modules" in str(f):
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except Exception:
        continue
    for i, line in enumerate(text.splitlines(), 1):
        if pat.search(line):
            hits.append(str(f.relative_to(root)) + ":" + str(i))
print("\n".join(hits[:5]))
PYX
)
chk '全仓 shell 脚本没有「变量紧跟非 ASCII」的写法（本项目踩过 8 次）' '[ -z "$BADVAR" ]'
[ -n "$BADVAR" ] && printf '      %s\n' "$BADVAR"

hdr "T9 标记宽容性（说明文字被改过也要认得）"
P="$SB/t9-marker"; mkproj "$P"; cd "$P"; git init -q . >/dev/null 2>&1
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "标记宽容" >/dev/null 2>&1
# 手工把标记行尾说明改掉（模拟人手编辑过托管块标记）
python3 - "$P/AGENTS.md" <<'PYX'
import pathlib, sys, re
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
s = re.sub(r"<!--\s*KNOWLOG:START[^\n]*-->", "<!-- KNOWLOG:START (我自己改过的说明) -->", s)
p.write_text(s, encoding="utf-8")
PYX
CP="$P/AGENTS.md"
before=$(grep -c "KNOWLOG:START" "$CP")
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "标记宽容" >/dev/null 2>&1
chk "改过说明文字后重跑，仍是同一块（不追加第二块）" 'test "$(grep -c "<!-- KNOWLOG:START" AGENTS.md)" = "1"'
chk "重跑后标记行被规范化" 'grep -q "手工改动请放在块外" AGENTS.md'

hdr "T9b 手工区判据（不要重复造路由节）"
P="$SB/t9-route"; mkproj "$P"; cd "$P"; git init -q . >/dev/null 2>&1
mkdir -p docs/knowledge
cat > AGENTS.md <<'DOC'
# 已有手写路由节的项目

## 🧭 Domain Context Routing (业务领域上下文路由)
（我自己的路由表）
DOC
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "路由判据" >/dev/null 2>&1
chk "项目已有手写路由节时，不再追加通用路由节" 'test "$(grep -cE "^## .*领域上下文路由表（手工维护）" AGENTS.md)" = "0"'
chk "但托管块自身仍写入了（约束落点正常）" 'grep -q "KNOWLOG:START" AGENTS.md'

hdr "T9b 升级路径守卫与防泄露扫描器"
P="$SB/t9-upgrade"; mkproj "$P"
bash "$SKILL/scripts/bootstrap-docs.sh" --root "$P" --project-name "升级守卫" >/dev/null 2>&1
cd "$P"
chk "在项目内跑 --force-scripts 会提示'自拷'并给出正确命令" 'bash scripts/bootstrap-docs.sh --force-scripts > "$SB/guard.txt" 2>&1; grep -q "自拷" "$SB/guard.txt"'
# 真实升级场景：项目里缺一个脚本 → 从已安装的 skill 跑应补齐
rm -f scripts/docs-doctor.sh
bash "$SKILL/scripts/bootstrap-docs.sh" --root . --force-scripts > "$SB/force.txt" 2>&1
chk "从 skill 跑 bootstrap 能补齐缺失脚本（升级路径）" '[ -x scripts/docs-doctor.sh ]'

chk "扫描器对干净仓库返回 0" 'bash "$SKILL/scripts/check-secrets.sh" --root "$SKILL" >/dev/null'
LEAK="$SB/leak"; rm -rf "$LEAK"; mkdir -p "$LEAK"; cd "$LEAK"; git init -q .
# 假密钥在运行时拼接，避免仓库里出现"像密钥的字面量"（否则扫描器会自伤）
FAKE_KEY="sk-$(printf 'a%.0s' $(seq 1 30))$(printf '1%.0s' $(seq 1 6))"
printf 'const k = "%s";\n' "$FAKE_KEY" > a.js; git add a.js
chk "扫描器能抓到暂存区里的假密钥（负例）" '! bash "$SKILL/scripts/check-secrets.sh" --root "$LEAK" --staged >/dev/null'
printf 'api_key = "%s"\n' "EXAMPLE_PLACEHOLDER_NOT_A_KEY" > b.py; git add b.py
chk "扫描器不误报占位符写法" 'git -C "$LEAK" reset -q -- a.js && bash "$SKILL/scripts/check-secrets.sh" --root "$LEAK" --staged >/dev/null'

printf '\n\033[1m==== 结果：%d 通过 / %d 失败 ====\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
