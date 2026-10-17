#!/bin/bash
# bootstrap-docs.sh — 给一个项目建立「开发文档体系」（日志 + 知识库 + 领域上下文 + 索引 + 召回 + 约束）
#
# 设计原则：
#   1. 幂等 —— 已存在的文件一律不覆盖；重复执行的结果必须逐字节相同（可 `shasum` 对拍）
#   2. 不破坏 —— AGENTS.md 只在托管块标记之间写入；**用户手工维护的内容（如领域路由表）放在块外**，
#      由本脚本"只创建一次、永不重写"
#   3. 自包含 —— 会把 assets 复制到项目的 scripts/assets/，因此**复制到项目后依然能独立运行**
#      （`--ends` 加端、补建目录都不需要原始 skill）
#   4. 可验证 —— 收尾自动跑 check-daily-index.sh，把"结构对不对"变成退出码
#
# 用法：
#   bash scripts/bootstrap-docs.sh                                  # 当前 git 仓库
#   bash scripts/bootstrap-docs.sh --ends "backend frontend"        # 指定端（默认自动探测）
#   bash scripts/bootstrap-docs.sh --knowledge-layout flat|by-end   # 知识库布局（默认 auto）
#   bash scripts/bootstrap-docs.sh --project-name "我的项目" --with-recall
#   bash scripts/bootstrap-docs.sh --dry-run                        # 只看要做什么
set -euo pipefail

# 环境变量归一化：KNOWLOG_HOME 为准，兼容旧的 DOCS_SYSTEM_HOME
KNOWLOG_HOME="${KNOWLOG_HOME:-${DOCS_SYSTEM_HOME:-}}"
ROOT=""; ENDS=""; PROJECT_NAME=""; LAYOUT="auto"; WITH_RECALL=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --ends) ENDS="${2:-}"; shift 2 ;;
    --ends=*) ENDS="${1#--ends=}"; shift ;;
    --project-name) PROJECT_NAME="${2:-}"; shift 2 ;;
    --project-name=*) PROJECT_NAME="${1#--project-name=}"; shift ;;
    --knowledge-layout) LAYOUT="${2:-}"; shift 2 ;;
    --knowledge-layout=*) LAYOUT="${1#--knowledge-layout=}"; shift ;;
    --with-hook|--with-recall) WITH_RECALL=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
case "$LAYOUT" in auto|flat|by-end) ;; *) echo "❌ --knowledge-layout 只能是 auto / flat / by-end" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$ROOT" ] || ROOT="$(cd "$HERE/.." && pwd)"
fi
[ -d "$ROOT" ] || { echo "❌ 目标目录不存在：$ROOT" >&2; exit 1; }

# ---- assets 定位：优先自包含副本（项目内 scripts/assets/），其次 skill 原始位置 ----
ASSETS=""
for cand in "${KNOWLOG_HOME:-}/assets" "$HERE/assets" "$ROOT/scripts/assets" "$(cd "$HERE/.." && pwd)/assets"; do
  if [ -n "$cand" ] && [ -d "$cand" ]; then ASSETS="$cand"; break; fi
done
if [ -z "$ASSETS" ]; then
  echo "❌ 找不到 assets 目录。请在 skill 目录里首次运行，或设 KNOWLOG_HOME=<skill 目录>" >&2
  exit 1
fi
SOURCE_SCRIPT_DIR="$(dirname "$ASSETS")/scripts"      # skill 的 scripts/（用于复制全套脚本）
if [ ! -d "$SOURCE_SCRIPT_DIR" ]; then SOURCE_SCRIPT_DIR="$HERE"; fi

if [ -z "$PROJECT_NAME" ]; then PROJECT_NAME="$(basename "$ROOT")"; fi
DATE="$(date +%Y-%m-%d)"

# ---- 端自动探测 ----
if [ -z "$ENDS" ]; then
  detected=()
  if [ -f "$ROOT/go.mod" ]; then detected+=("backend"); fi
  if [ -f "$ROOT/package.json" ] && grep -qE '"(react|vue|@angular/core|svelte|next|nuxt)"' "$ROOT/package.json" 2>/dev/null; then detected+=("frontend"); fi
  if [ -f "$ROOT/manifest.json" ] && [ -f "$ROOT/pages.json" ]; then detected+=("mobile"); fi
  if [ -f "$ROOT/pubspec.yaml" ]; then detected+=("mobile"); fi
  if [ ${#detected[@]} -eq 0 ]; then
    for d in "$ROOT"/*/; do
      if [ -f "${d}go.mod" ] || [ -f "${d}package.json" ]; then detected+=("$(basename "$d")"); fi
    done
  fi
  if [ ${#detected[@]} -eq 0 ]; then detected=("app"); fi
  ENDS="$(printf '%s ' "${detected[@]}")"
fi
ENDS="$(printf '%s' "$ENDS" | tr ',' ' ')"
read -r -a END_ARR <<< "$ENDS"
if [ "$LAYOUT" = "auto" ]; then
  if [ ${#END_ARR[@]} -ge 2 ]; then LAYOUT="by-end"; else LAYOUT="flat"; fi
fi

echo "📗 bootstrap-docs"
echo "   项目：${PROJECT_NAME}（${ROOT}）"
if [ "$LAYOUT" = "by-end" ]; then
  echo "   知识布局：by-end（端：${END_ARR[*]} · 通用：common）"
else
  echo "   知识布局：flat（单面项目：四个分类直接放 docs/knowledge/ 下，无端层）"
fi
if [ "$DRY" -eq 1 ]; then echo "   ⚠️  --dry-run：只打印计划，不落盘"; fi
echo

ROOT="$ROOT" PROJECT_NAME="$PROJECT_NAME" DATE="$DATE" ENDS="$ENDS" LAYOUT="$LAYOUT" \
ASSETS="$ASSETS" SOURCE_SCRIPT_DIR="$SOURCE_SCRIPT_DIR" DRY="$DRY" python3 - <<'PY'
import os, pathlib, re, shutil, stat, sys

root = pathlib.Path(os.environ["ROOT"]); assets = pathlib.Path(os.environ["ASSETS"])
srcdir = pathlib.Path(os.environ["SOURCE_SCRIPT_DIR"])
name = os.environ["PROJECT_NAME"]; date = os.environ["DATE"]
ends = os.environ["ENDS"].split(); layout = os.environ["LAYOUT"]
dry = os.environ["DRY"] == "1"

created, skipped, notes = [], [], []
MARK_START = "<!-- KNOWLOG:START (由 knowlog skill 托管，手工改动请放在块外) -->"
MARK_END = "<!-- KNOWLOG:END -->"
CATS = ["architecture", "guides", "troubleshooting", "best-practices"]


def put(rel: str, content: str):
    p = root / rel
    if p.exists():
        if p.read_text(encoding="utf-8", errors="ignore") == content:
            skipped.append(rel); return
        skipped.append(rel + "（已存在，保留现有内容）"); return
    if dry:
        created.append(rel); return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    created.append(rel)


def normalize(text: str) -> str:
    return text.rstrip("\n") + "\n"


LEGACY_START = "<!-- " + "DOCS" + "-SYSTEM:START"     # 旧标记（本项目 v0.2 及更早写入的），只为兼容迁移
LEGACY_END = "DOCS" + "-SYSTEM:END -->"


def put_block_managed(rel: str, block: str, preamble: str = ""):
    """托管块：块内由脚本维护（幂等：内容规范化后相同就不写）

    兼容：老项目里可能是旧标记（DOCS-SYSTEM），这里顺手迁移到新标记（KNOWLOG），
    否则老项目会一直被判"缺少托管块"，人就得手工改。
    """
    p = root / rel; block = normalize(block)
    if p.exists():
        old = p.read_text(encoding="utf-8")
        if LEGACY_START in old and LEGACY_END in old and MARK_START not in old:
            migrated = re.sub(re.escape(LEGACY_START) + r".*?" + re.escape(LEGACY_END),
                              lambda _: block.strip(), old, flags=re.S)
            if not dry:
                p.write_text(normalize(re.sub(r"\n{3,}", "\n\n", migrated)), encoding="utf-8")
            created.append(rel + "（托管块标记已从 DOCS-SYSTEM 迁移到 KNOWLOG）")
            return
        if MARK_START in old and MARK_END in old:
            new = re.sub(re.escape(MARK_START) + r".*?" + re.escape(MARK_END),
                         lambda _: block.strip(), old, flags=re.S)
            new = normalize(re.sub(r"\n{3,}", "\n\n", new))
            if new == normalize(old):
                skipped.append(rel + "（托管块已最新）"); return
            if not dry:
                p.write_text(new, encoding="utf-8")
            created.append(rel + "（刷新托管块）"); return
        new = normalize(old.rstrip("\n") + "\n\n" + block)
        if not dry:
            p.write_text(new, encoding="utf-8")
        created.append(rel + "（追加托管块）"); return
    if not dry:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(preamble + block, encoding="utf-8")
    created.append(rel + "（新建）")


def ensure_unmanaged_section(rel: str, marker_re: str, content: str):
    """用户手工维护的 section：**只创建一次，之后永不改写**（否则会吃掉用户的编辑）

    注意：判断必须用「行首标题」正则，不能用子串包含 —— 托管块正文里会**提到**这个标题
    （"路由表在…一节"），子串匹配会误判成"已存在"，于是手工区永远建不出来。
    """
    p = root / rel
    if p.exists() and re.search(marker_re, p.read_text(encoding="utf-8"), re.M):
        skipped.append(rel + "（手工维护区已存在，未改动）"); return
    if not p.exists():
        put_block_managed(rel, "")     # 先确保文件存在
    p = root / rel
    old = p.read_text(encoding="utf-8") if p.exists() else ""
    if not dry:
        p.write_text(normalize(old.rstrip("\n") + "\n\n" + content), encoding="utf-8")
    else:
        created.append(rel + "（新增手工维护区）"); return
    created.append(rel + "（新增手工维护区）")


# ---------- 渲染上下文 ----------
def end_sections_for(dirs):
    out = []
    for e in dirs:
        rows = "\n".join(
            f"| — | [{f}]({e}/{f}) | {'端知识库说明与文档模板' if f == 'README.md' else f'{e} 端索引（新增知识后必须更新）'} | 初始化 |"
            for f in ("README.md", "index.md"))
        out.append(f"## 📦 {e} 知识 `docs/knowledge/{e}/`\n\n| 分类 | 文档 | 说明 | 来源 |\n|------|------|------|------|\n{rows}\n")
    return "\n".join(out)


known_ends = list(dict.fromkeys(ends + (["common"] if layout == "by-end" and "common" not in ends else [])))
end_table = "\n".join(
    f"| {e} | [index.md]({e}/index.md) | {e} 端知识（架构 / 规范 / 踩坑 / 最佳实践） | — |" for e in known_ends)
flat_rows = "\n".join(
    f"| — | [{c}/]({c}/) | {c}：{'架构、目录、启动流程、数据模型' if c == 'architecture' else '规范与开发指南' if c == 'guides' else '踩坑与 Bug 复盘' if c == 'troubleshooting' else '最佳实践与性能优化'} | 初始化 |"
    for c in CATS)


def render(tpl: str, extra: dict | None = None) -> str:
    s = (assets / tpl).read_text(encoding="utf-8")
    if layout == "by-end":
        know_paths = "`docs/knowledge/<端>/{architecture,guides,troubleshooting,best-practices}/`（端 = " + "、".join(known_ends) + "）"
        know_indexes = "分端 `docs/knowledge/<端>/index.md` + 根 `docs/knowledge/index.md` 两级"
        know_tree = ("<端>/                # 按端聚合（" + " / ".join(known_ends) + "）\n"
                     "│       ├── README.md · index.md\n"
                     "│       └── {architecture,guides,troubleshooting,best-practices}/")
        new_know_cmd = "bash scripts/new-knowledge.sh <端> <分类> <kebab-name> \"<一句话说明>\""
        layout_desc = "**by-end（多端项目）**：知识按端聚合（" + "、".join(known_ends) + "）── 各端知识基本不通用，混在一起会互相淹没"
    else:
        know_paths = "`docs/knowledge/{architecture,guides,troubleshooting,best-practices}/`（flat：单面项目不分端）"
        know_indexes = "根 `docs/knowledge/index.md` 一级"
        know_tree = ("{architecture,guides,troubleshooting,best-practices}/   # flat：四个分类直接放这里\n"
                     "│       └── <kebab-name>.md")
        new_know_cmd = "bash scripts/new-knowledge.sh --flat <分类> <kebab-name> \"<一句话说明>\""
        layout_desc = "**flat（单面项目）**：只有一个「面」（一个服务/CLI/管道），知识按分类放，不造端层"

    mapping = {
        "__PROJECT__": name, "__DATE__": date, "__ENDS__": " / ".join(ends) if layout == "by-end" else "（无端层：flat 布局）",
        "__LAYOUT_DESC__": layout_desc, "__KNOW_PATHS__": know_paths,
        "__KNOW_INDEXES__": know_indexes, "__KNOW_TREE__": know_tree, "__NEW_KNOW_CMD__": new_know_cmd,
        "__END_DIRS__": (", ".join(f"{e}/" for e in known_ends) if layout == "by-end" else ", ".join(f"{c}/" for c in CATS)),
        "__END_TABLE__": end_table if layout == "by-end" else flat_rows,
        "__END_SECTIONS__": end_sections_for(known_ends) if layout == "by-end" else "",
        "__LAYOUT__": layout,
    }
    if extra:
        mapping.update(extra)
    for k, v in mapping.items():
        s = s.replace(k, v)
    return s


# ---------- 1. 目录树 ----------
dirs = ["docs/daily", "docs/agents", "docs/templates", "docs/domain context", "docs/knowledge", "scripts"]
if layout == "by-end":
    for e in known_ends:
        for c in CATS:
            dirs.append(f"docs/knowledge/{e}/{c}")
else:
    for c in CATS:
        dirs.append(f"docs/knowledge/{c}")
for d in dirs:
    if dry:
        continue
    (root / d).mkdir(parents=True, exist_ok=True)
# 空目录不被 git 跟踪 → 别人 clone 后结构 checker 会退化成告警，所以放占位文件
KEEP_DIRS = [d for d in dirs if d.startswith("docs/knowledge/") and d.count("/") >= 2]
for d in KEEP_DIRS:
    if not any((root / d).iterdir()):
        (root / d / ".gitkeep").write_text("", encoding="utf-8")
notes.append(f"目录：{len(dirs)} 个（已存在的不动；空的分类目录放了 .gitkeep）")

# ---------- 2. 文档骨架 ----------
put("docs/index.md", render("daily-index.md.tmpl"))
put("docs/README.md", render("daily-README.md.tmpl"))
put("docs/template.md", render("daily-template.md.tmpl"))
put("docs/templates/knowledge-doc.md", render("knowledge-doc.md.tmpl"))
put("docs/knowledge/.keyword-map.json", render("keyword-map.json.tmpl"))
put("docs/domain context/README.md", render("domain-readme.md.tmpl"))
put("docs/agents/domain.md", render("agents-domain.md.tmpl"))
put("docs/agents/issue-tracker.md", render("agents-issue-tracker.md.tmpl"))
put("docs/agents/triage-labels.md", render("agents-triage-labels.md.tmpl"))
if layout == "by-end":
    put("docs/knowledge/README.md", render("knowledge-root-README.md.tmpl"))
    put("docs/knowledge/index.md", render("knowledge-root-index.md.tmpl"))
    for e in known_ends:
        put(f"docs/knowledge/{e}/README.md", render("knowledge-end-README.md.tmpl", {"__END__": e}))
        put(f"docs/knowledge/{e}/index.md", render("knowledge-end-index.md.tmpl", {"__END__": e}))
else:
    put("docs/knowledge/README.md", render("knowledge-flat-README.md.tmpl"))
    put("docs/knowledge/index.md", render("knowledge-flat-index.md.tmpl"))
    for c in CATS:
        put(f"docs/knowledge/{c}/README.md", render("knowledge-flat-category-README.md.tmpl",
                                                   {"__CAT__": c, "__CAT_DESC__": {
                                                       "architecture": "架构、目录结构、启动流程、数据模型",
                                                       "guides": "规范与开发指南（接口约定、错误处理、部署）",
                                                       "troubleshooting": "踩坑与 Bug 复盘（症状 → 根因 → 修法 → 判据）",
                                                       "best-practices": "最佳实践与性能优化"}[c]}))

# ---------- 3. 脚本 + 资产（自包含：复制到项目后仍可独立运行） ----------
SCRIPTS = ["bootstrap-docs.sh", "adopt-docs.sh", "new-daily-log.sh", "check-daily-index.sh",
           "check-docs-structure.sh", "docs-doctor.sh", "new-knowledge.sh",
           "check-knowledge-index.sh", "reindex-knowledge.sh", "new-keyword.sh", "knowledge-retrieve.sh",
           "install-recall.sh", "install-skill.sh", "package-skill.sh", "index-util.py", "recall-core.py"]
for s in SCRIPTS:
    src = srcdir / s
    dst = root / "scripts" / s
    if not src.exists():
        notes.append(f"⚠️ 资产缺失：{s}（跳过）"); continue
    if dst.exists() and dst.read_bytes() == src.read_bytes():
        skipped.append(f"scripts/{s}"); continue
    if dst.exists():
        notes.append(f"⚠️ scripts/{s} 已存在且内容不同 → 保留你的版本（如需上游版本请手工比对）"); continue
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        os.chmod(dst, dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    created.append(f"scripts/{s}")

# assets 自包含副本（供复制后的 bootstrap 独立运行）
asset_dst = root / "scripts" / "assets"
if assets.resolve() != asset_dst.resolve():
    if dry:
        created.append("scripts/assets/（模板副本）")
    else:
        asset_dst.mkdir(parents=True, exist_ok=True)
        n = 0
        for f in sorted(assets.glob("*.tmpl")):
            t = asset_dst / f.name
            if not t.exists() or t.read_bytes() != f.read_bytes():
                shutil.copy2(f, t); n += 1
        created.append(f"scripts/assets/（{n} 个模板更新）")
for extra_src, extra_dst in [(srcdir.parent / "adapters", root / "scripts" / "adapters")]:
    if extra_src.is_dir() and not extra_dst.exists() and not dry:
        shutil.copytree(extra_src, extra_dst)
        created.append("scripts/adapters/（各 agent 适配器）")

# ---------- 4. 约束：托管块（规则）+ 手工维护区（路由表，只创建一次） ----------
put_block_managed("AGENTS.md", render("agents-block.md.tmpl"),
                  preamble=f"# {name} — Agent 指南\n\n")
ensure_unmanaged_section("AGENTS.md", r"^##\s+🧭\s*领域上下文路由表", render("agents-routing-section.md.tmpl"))

# ---------- 报告 ----------
print(f"✅ 新建/更新 {len(created)} 项")
for c in created:
    print(f"   + {c}")
if skipped:
    print(f"⏭️  跳过（已存在，未覆盖）{len(skipped)} 项")
    for s in skipped[:10]:
        print(f"   = {s}")
    if len(skipped) > 10:
        print(f"   … 另有 {len(skipped) - 10} 项")
for n in notes:
    print(f"ℹ️  {n}")
PY

if [ "$DRY" -eq 0 ]; then
  if [ "$WITH_RECALL" -eq 1 ] && [ -f "$ROOT/scripts/install-recall.sh" ]; then
    echo
    echo "🔌 安装关键词召回适配器（按本机检测到的 agent）"
    bash "$ROOT/scripts/install-recall.sh" --root "$ROOT" --agent auto
  fi
  echo
  echo "🔎 自检："
  if [ -f "$ROOT/scripts/check-daily-index.sh" ]; then bash "$ROOT/scripts/check-daily-index.sh" --root "$ROOT" || true; fi
  if [ -f "$ROOT/scripts/check-knowledge-index.sh" ]; then bash "$ROOT/scripts/check-knowledge-index.sh" --root "$ROOT" || true; fi
  echo
  echo "下一步："
  echo "  1. 记日志：bash scripts/new-daily-log.sh <slug>"
  echo "  2. 沉淀：bash scripts/new-knowledge.sh <端|--flat> <分类> <name> \"<说明>\" --source <日志路径>"
  echo "  3. 召回：bash scripts/new-keyword.sh \"<正则>\" \"<提示>\" \"<文档>\"（并 install-recall.sh 装到各 agent）"
  echo "  4. 门禁：bash scripts/check-daily-index.sh --strict && bash scripts/check-knowledge-index.sh --strict"
  echo "  5. 既有异构文档：bash scripts/adopt-docs.sh（先看计划，再 --apply）"
fi
