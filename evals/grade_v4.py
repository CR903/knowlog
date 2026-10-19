#!/usr/bin/env python3
"""grade_v4.py — iteration-4 客观评分器（并生成人工评审骨架）

用法: python3 evals/grade_v4.py <eval_id> <project_dir> <out_grading_json>

与 grade.py 的分工：
  · 这里只判**可判定**的东西（文件集合关系、门禁退出码、链接可达性、内容关键词是否丢失）
  · "写得好不好"交给 evals/review-rubric.md（本脚本会在同目录生成 manual_review.md 骨架）

判据尽量用「脚本退出码」和「集合关系」，不用"看着像"。
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys

EVAL = sys.argv[1]
PROJ = pathlib.Path(sys.argv[2])
OUT = pathlib.Path(sys.argv[3])

R: list[dict] = []

# 评测时"不算数"的东西：
#   · .git / .remember / .trellis 等第三方工具或运行时产物（.remember 是本机另一个记忆工具的全局钩子写进来的）
#   · 评测自产文件（PROMPT/transcript/run_meta/grading/manual_review）
IGNORE_DIRS = {".git", ".remember", ".trellis", "node_modules"}
IGNORE_FILES = {"PROMPT.md", "transcript.txt", "run_meta.json", "grading.json",
                "manual_review.md", "baseline_files.json"}


def counted(p: pathlib.Path) -> bool:
    if p.name in IGNORE_FILES:
        return False
    return not any(part in IGNORE_DIRS for part in p.parts)


def check(text: str, passed: bool, evidence: str = ""):
    R.append({"text": text, "passed": bool(passed), "evidence": str(evidence)[:600]})


# ---------------- 通用工具 ----------------
def md_all() -> list[pathlib.Path]:
    return sorted(p for p in PROJ.rglob("*.md") if counted(p))


def text_all() -> str:
    out = []
    for p in md_all():
        try:
            out.append(p.read_text(encoding="utf-8", errors="ignore"))
        except Exception:
            pass
    return "\n".join(out)


def daily() -> list[pathlib.Path]:
    d = PROJ / "docs" / "daily"
    return sorted(d.rglob("*.md")) if d.is_dir() else []


def loose() -> list[pathlib.Path]:
    return [p for p in daily() if p.parent == PROJ / "docs" / "daily"]


def monthly() -> list[pathlib.Path]:
    return [p for p in daily() if re.fullmatch(r"\d{4}-\d{2}", p.parent.name)]


def idx_text() -> str:
    p = PROJ / "docs" / "index.md"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def daily_links() -> list[str]:
    return re.findall(r"\]\((daily/[^)\s]+?\.md)\)", idx_text())


def dead_links() -> list[str]:
    return [l for l in daily_links() if not (PROJ / "docs" / l).exists()]


def gate(script: str) -> tuple[int, str]:
    sh = PROJ / "scripts" / script
    if not sh.exists():
        return 127, f"scripts/{script} 不存在"
    p = subprocess.run(["bash", str(sh), "--strict", "--root", str(PROJ)],
                       capture_output=True, text=True, timeout=180)
    return p.returncode, (p.stdout + p.stderr).strip()[-400:]


def scripts_missing(names: list[str]) -> list[str]:
    miss = []
    for n in names:
        p = PROJ / "scripts" / n
        if not (p.exists() and os.access(p, os.X_OK)):
            miss.append(n)
    return miss


def has_block() -> bool:
    p = PROJ / "AGENTS.md"
    return p.exists() and "KNOWLOG:START" in p.read_text(encoding="utf-8", errors="ignore")


def baseline_files() -> set[str]:
    """夹具快照（setup_iteration4.sh 写在用例目录下）"""
    b = OUT.parent.parent / "baseline_files.json"          # <case>/baseline_files.json
    if not b.exists():
        b = OUT.parent / "baseline_files.json"
    if not b.exists():
        return set()
    return set(json.loads(b.read_text(encoding="utf-8")).get("files", []))


def new_files() -> list[str]:
    base = baseline_files()
    now = {str(p.relative_to(PROJ)) for p in PROJ.rglob("*")
           if p.is_file() and counted(p)}
    return sorted(now - base) if base else []


def knowledge_index_mentions(needle: str) -> bool:
    for p in PROJ.rglob("index.md"):
        if "knowledge" in p.parts and needle in p.read_text(encoding="utf-8", errors="ignore"):
            return True
    return False


# ---- 扩评（eval-10..12）用到的通用工具 ----
CATS = ["architecture", "guides", "troubleshooting", "best-practices"]


def index_table_rows() -> list[str]:
    """只取表格行（以 | 开头）—— 判占位残留只能看这里，说明文字里本就会出现 <slug> 等写法。"""
    return [ln for ln in idx_text().splitlines() if ln.strip().startswith("|")]


def residue_rows() -> list[str]:
    return [ln for ln in index_table_rows()
            if re.search(r"(待填|待回填|待提交|<TODO>|<slug>|TODO)", ln)]


def log_rels() -> set[str]:
    """磁盘上的日志，转成与索引链接同形的相对路径（daily/<月>/<文件>）。"""
    return {str(p.relative_to(PROJ / "docs")) for p in daily()}


def month_mismatches() -> list[str]:
    out = []
    for p in daily():
        if not re.fullmatch(r"\d{4}-\d{2}", p.parent.name):
            out.append(f"{p.relative_to(PROJ)}（父目录 {p.parent.name} 不是月份目录）")
            continue
        m = re.match(r"(\d{4}-\d{2})-\d{2}_.+\.md$", p.name)
        if not m or p.parent.name != m.group(1):
            out.append(f"{p.relative_to(PROJ)}（目录月 {p.parent.name}）")
    return out


def recall_check(probes: list[str]) -> tuple[bool, bool, str]:
    """跑项目里的 knowledge-retrieve.sh：命中吗？命中的文档真实存在吗？

    故意同时试两种调用形式：`bash scripts/knowledge-retrieve.sh "<probe>"`（任务里给用户的原话）
    与加 `--root` 的形式 —— 免得把"自建了等价召回、但 CLI 契约不同"的基线误判为"没有召回"。
    """
    sh = PROJ / "scripts" / "knowledge-retrieve.sh"
    if not sh.exists():
        return False, False, "scripts/knowledge-retrieve.sh 不存在（召回入口缺失）"
    attempts = []
    for probe in probes:
        attempts.append(([str(sh), probe], f"probe={probe!r}（cwd 形式）"))
        attempts.append(([str(sh), "--root", str(PROJ), probe], f"probe={probe!r}（--root 形式）"))
    for args, label in attempts:
        try:
            p = subprocess.run(["bash", *args], cwd=str(PROJ),
                               capture_output=True, text=True, timeout=60)
        except Exception as e:
            return False, False, f"调用失败：{e}"
        out = (p.stdout + p.stderr).strip()
        if p.returncode == 0 and "命中" in out:
            docs = [d.rstrip(")）.,。、") for d in re.findall(r"(docs/knowledge/\S+\.md)", out)]
            if docs:
                ok = all((PROJ / d.split("#")[0]).exists() for d in docs)
                return True, ok, f"{label} docs={docs[:2]}"
    return False, False, f"探针均未命中：{probes}"


def knowledge_docs() -> list[pathlib.Path]:
    know = PROJ / "docs" / "knowledge"
    if not know.is_dir():
        return []
    return [p for p in know.rglob("*.md")
            if counted(p) and p.name not in {"README.md", "index.md"}]


def end_layer_dirs() -> list[str]:
    """知识库里的「端层」目录：非四分类，且含 index.md 或含分类子目录。"""
    know = PROJ / "docs" / "knowledge"
    if not know.is_dir():
        return []
    out = []
    for d in sorted(know.iterdir()):
        if not d.is_dir() or d.name in CATS:
            continue
        if (d / "index.md").exists() or any((d / c).is_dir() for c in CATS):
            out.append(d.name)
    return out


def keyword_rules() -> dict:
    kmap = PROJ / "docs" / "knowledge" / ".keyword-map.json"
    if not kmap.exists():
        return {}
    try:
        d = json.loads(kmap.read_text(encoding="utf-8") or "{}")
    except Exception:
        return {}
    return {k: v for k, v in d.items() if isinstance(v, dict) and not k.startswith("_")}


# ---------------- 用例 ----------------
if EVAL == "eval-7":
    # 全新项目：从零搭结构（夹具里什么都没有）
    logs = daily()
    check("建立了 docs/daily 且没有散落在根上的日志", bool(logs) and not loose(),
          f"日志 {len(logs)} 篇；散落 {[str(p.relative_to(PROJ)) for p in loose()]}")
    check("日志按月份目录归位（至少 1 篇）", bool(monthly()),
          f"月份目录下 {len(monthly())} 篇")
    kn = PROJ / "docs" / "knowledge"
    cats = [d for d in kn.glob("*") if d.is_dir()] if kn.is_dir() else []
    check("建立知识库分类目录 + 分端/分类索引", bool(cats) and (kn / "index.md").exists(),
          f"分类: {[c.name for c in cats]}；根索引={(kn / 'index.md').exists()}")
    check("建立 docs/domain context/（业务领域记忆层）", (PROJ / "docs" / "domain context").is_dir() or (PROJ / "docs" / "domain-context").is_dir(),
          f"docs/ 下有: {[d.name for d in (PROJ / 'docs').glob('*') if d.is_dir()] if (PROJ / 'docs').is_dir() else []}")
    miss = scripts_missing(["check-daily-index.sh", "docs-doctor.sh", "new-daily-log.sh"])
    check("关键门禁/工具脚本就位且可执行", not miss, f"缺失: {miss}")
    check("AGENTS.md 写入托管块（KNOWLOG:START）", has_block(), f"AGENTS.md 存在={(PROJ / 'AGENTS.md').exists()}")
    rc, out = gate("check-daily-index.sh")
    check("门禁 check-daily-index.sh --strict 通过", rc == 0, f"rc={rc} {out}")
    check("索引里登记了日志链接", bool(daily_links()), f"链接数={len(daily_links())}")
    check("索引链接可达（无死链）", bool(daily_links()) and not dead_links(), f"死链={dead_links()}")

elif EVAL == "eval-8":
    # 一团乱的历史文档：采纳 + 反向补齐索引 + 识别死链
    t = text_all()
    check("旧平铺日志内容未丢失（toFixed 兜底仍在仓库里）", "toFixed" in t,
          "原 docs/logs/2026-09-01-money-format.md 的独特片段")
    check("该日志被归位到月份目录", any("toFixed" in p.read_text(encoding="utf-8", errors="ignore") for p in monthly()),
          f"月份目录日志: {[str(p.relative_to(PROJ)) for p in monthly()]}")
    check("裸放在 daily 根的日志进了月份目录", any("status=2" in p.read_text(encoding="utf-8", errors="ignore") for p in monthly()),
          f"月份目录日志数={len(monthly())}")
    check("索引里的死链已清除", "money-format-ghost" not in idx_text(), f"死链={dead_links()}")
    check("索引链接全部可达", not dead_links(), f"死链={dead_links()}")
    check("无索引的知识文档已被登记", knowledge_index_mentions("excel-import"),
          "在某个 knowledge/**/index.md 里能找到 excel-import")
    check("随笔目录（notes/）内容未丢失", "导出重试" in t, "原 notes/todo.md 的独特片段")
    miss = scripts_missing(["check-daily-index.sh"])
    rc, out = gate("check-daily-index.sh")
    check("项目装上了可运行的门禁脚本", not miss and rc == 0, f"缺失={miss} rc={rc} {out}")
    check("AGENTS.md 写入托管块（KNOWLOG:START）", has_block(), "")

elif EVAL == "eval-9":
    # 体系已就位 + 刚做完的任务：收尾质量（写日志 / 沉淀知识 / 索引同步）
    new = new_files()
    new_logs = [f for f in new if f.startswith("docs/daily/")]
    check("新增了一篇日志", bool(new_logs), f"新增: {new[:8]}")
    check("日志落在月份目录（不是 daily 根）",
          any(re.match(r"docs/daily/\d{4}-\d{2}/", f) for f in new_logs), f"新增日志: {new_logs}")
    body = "\n".join((PROJ / f).read_text(encoding="utf-8", errors="ignore") for f in new_logs
                     if (PROJ / f).exists())
    check("日志写清了「改了什么」（提到 CalcConsume 或 packaging）",
          ("CalcConsume" in body) or ("packaging" in body), f"正文长度={len(body)}")
    check("日志写了验证方式（测试/单测/回归）",
          any(k in body for k in ("单测", "测试", "unit_test", "回归")), "")
    check("日志写了遗留风险（调拨/transfer/未覆盖）",
          any(k in body for k in ("调拨", "transfer", "遗留", "未覆盖", "还没")), "")
    # 只检查"表格行"里的占位残留：索引说明文字里本来就会出现 <slug>、<YYYY-MM> 这类写法（不是残留）
    table_rows = [ln for ln in idx_text().splitlines() if ln.strip().startswith("|")]
    residue = [ln for ln in table_rows if re.search(r"(待填|待回填|<TODO>|<slug>|TODO)", ln)]
    check("索引同步且无占位残留",
          any(f.replace("docs/", "") in idx_text() for f in new_logs) and not residue,
          f"新增日志在索引={(any(f.replace('docs/', '') in idx_text() for f in new_logs))}；残留行={residue[:2]}")
    new_knowledge = [f for f in new if f.startswith("docs/knowledge/") and f.endswith(".md")]
    check("把可复用结论沉淀成知识并登记进索引",
          bool(new_knowledge) and any(knowledge_index_mentions(pathlib.Path(f).stem) for f in new_knowledge),
          f"新增知识: {new_knowledge}")

elif EVAL == "eval-10":
    # 跨月补写：任务日期早于当前月 → 按任务日期归月 + 索引行落对表格 + 占位填实
    logs = daily()
    check("建立了月份目录，日志未散落在 daily 根", bool(logs) and not loose(),
          f"日志 {len(logs)} 篇；散落 {[str(p.relative_to(PROJ)) for p in loose()]}")
    sep = [p for p in monthly() if re.match(r"2026-09-12_", p.name)]
    check("9 月任务按「任务日期」归入 daily/2026-09/（不是塞进 10 月）", bool(sep),
          f"月份目录日志: {[str(p.relative_to(PROJ)) for p in monthly()]}")
    octp = [p for p in monthly() if re.match(r"2026-10-15_", p.name)]
    check("10 月任务按「任务日期」归入 daily/2026-10/", bool(octp),
          f"2026-10 下: {[p.name for p in (PROJ / 'docs' / 'daily' / '2026-10').glob('*.md')] if (PROJ / 'docs' / 'daily' / '2026-10').is_dir() else []}")
    sepbody = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in sep)
    octbody = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in octp)
    check("两篇日志都写实（9 月提到 packaging/CalcConsume；10 月提到 toFixed/精度/负零）",
          ("packaging" in sepbody or "CalcConsume" in sepbody)
          and any(k in octbody for k in ("toFixed", "精度", "负零", "money")),
          f"9月正文={len(sepbody)} 10月正文={len(octbody)}")
    idx = idx_text()
    check("索引同时登记了 9 月与 10 月两笔（都按任务日期）",
          ("2026-09-12" in idx) and ("2026-10-15" in idx),
          f"9月={'2026-09-12' in idx} 10月={'2026-10-15' in idx}")
    check("索引里新起了 2026-09 月份表格（跨月落对表）", "2026-09" in idx, "")
    check("索引表格行无占位残留（只查表格行）", not residue_rows(), f"残留行={residue_rows()[:2]}")
    check("索引链接全部可达（无死链）",
          bool(daily_links()) and not dead_links(), f"链接={len(daily_links())} 死链={dead_links()}")
    rc, out = gate("check-daily-index.sh")
    check("门禁 check-daily-index.sh --strict 通过（含三处月份一致）", rc == 0, f"rc={rc} {out}")
    check("AGENTS.md 写入托管块且门禁脚本就位",
          has_block() and not scripts_missing(["check-daily-index.sh"]), "")

elif EVAL == "eval-11":
    # 索引漂移修复（测「修」不测「搭」）：夹具自带体系 + 人为注入四类漂移
    rc, out = gate("check-daily-index.sh")
    check("最终 日志↔索引 门禁 --strict 通过", rc == 0, f"rc={rc} {out}")
    check("索引无死链", not dead_links(), f"死链={dead_links()}")
    mism = month_mismatches()
    check("所有日志 目录月 == 文件名月", not mism, f"不符: {mism}")
    files, links = log_rels(), set(daily_links())
    check("每篇日志都有索引行（且索引无多余链接）",
          bool(files) and not (files - links) and not (links - files),
          f"缺行={sorted(files - links)} 多余={sorted(links - files)}")
    t = text_all()
    check("三篇历史日志内容均未丢失（游标/OFFSET、幂等键、审计）",
          all(k in t for k in ("OFFSET", "幂等", "审计")), "原 8/9/10 月日志的独特片段")
    check("孤儿知识文档已登记进知识索引", knowledge_index_mentions("redis-timeout"),
          "docs/knowledge/troubleshooting/redis-timeout.md")
    doc = PROJ / "scripts" / "docs-doctor.sh"
    if doc.exists():
        p = subprocess.run(["bash", str(doc), "--strict", "--root", str(PROJ)],
                           capture_output=True, text=True, timeout=240)
        check("体检总入口 docs-doctor.sh --strict 三项全绿", p.returncode == 0,
              f"rc={p.returncode} {(p.stdout + p.stderr).strip()[-300:]}")
    else:
        check("体检总入口 docs-doctor.sh --strict 三项全绿", False, "scripts/docs-doctor.sh 不存在")
    check("AGENTS.md 托管块未被破坏", has_block(), "")
    check("索引里用户手写的「团队约定」段落未被删", "团队约定" in idx_text(), "")

elif EVAL == "eval-12":
    # 单面项目：知识库应落 flat（不造端层）+ 关键词召回真能用
    know = PROJ / "docs" / "knowledge"
    endd = end_layer_dirs()
    check("知识库未造端层（单面项目不建 <端>/<分类>/ 结构）",
          know.is_dir() and not endd, f"端层目录: {endd}")
    kdocs = knowledge_docs()
    flat_ok = bool(kdocs) and all(len(p.relative_to(know).parts) <= 2 for p in kdocs)
    check("知识库为 flat（知识文档直接挂在 docs/knowledge/ 或其分类下，不另起端层）",
          flat_ok, f"知识文档: {[str(p.relative_to(know)) for p in kdocs]}")
    check("知识根索引 docs/knowledge/index.md 就位", (know / "index.md").exists(), "")
    topic = [p for p in kdocs
             if re.search(r"csvColumns|列顺序|列序|column", p.read_text(encoding="utf-8", errors="ignore"), re.I)]
    check("沉淀了「CSV 列顺序」可复用知识文档", bool(topic),
          f"知识文档: {[str(p.relative_to(PROJ)) for p in kdocs]}")
    check("该知识文档已登记进知识索引",
          bool(topic) and any(knowledge_index_mentions(p.stem) for p in topic),
          f"登记={[p.stem for p in topic]}")
    rules = keyword_rules()
    check("加了真实召回规则（docs/knowledge/.keyword-map.json）", bool(rules),
          f"规则 {len(rules)} 条: {list(rules)[:3]}")
    hit, docs_ok, ev = recall_check(["csvColumns", "导出 CSV 的 csvColumns 列顺序", "列顺序 导出"])
    check("关键词召回可被命令行命中（用标识符 probe）", hit, ev)
    check("召回指向的文档真实可达", hit and docs_ok, ev)
    rc, out = gate("check-knowledge-index.sh")
    check("知识门禁 check-knowledge-index.sh --strict 通过", rc == 0, f"rc={rc} {out}")
    rc2, out2 = gate("check-docs-structure.sh")
    check("结构门禁 check-docs-structure.sh --strict 通过（flat 布局不混端层）", rc2 == 0,
          f"rc={rc2} {out2}")
    check("AGENTS.md 写入托管块", has_block(), "")

else:
    print(f"未知 eval_id: {EVAL}", file=sys.stderr)
    sys.exit(2)

# ---------------- 输出 ----------------
passed = sum(1 for r in R if r["passed"])
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({
    "eval_id": EVAL,
    "project": str(PROJ),
    "summary": {"passed": passed, "failed": len(R) - passed, "total": len(R),
                "pass_rate": round(passed / len(R), 4) if R else 0.0},
    "expectations": R,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# 人工评审骨架（同目录）
mr = OUT.parent / "manual_review.md"
if not mr.exists():
    mr.write_text(
        f"# 人工评审 — {EVAL} / {OUT.parent.name}\n\n"
        "> 量表见 `evals/review-rubric.md`（D1 日志重点 / D2 知识可复用 / D3 尊重既有约定，各 0–2 分）\n\n"
        "| 维度 | 分 | 依据（一句话，附 文件:行） |\n|---|---|---|\n"
        "| D1 日志记得住重点 | /2 |  |\n"
        "| D2 知识可复用 | /2 |  |\n"
        "| D3 尊重既有约定与事实 | /2 |  |\n"
        "| **合计** | /6 |  |\n\n评审人：      日期：\n", encoding="utf-8")

print(f"{EVAL}: {passed}/{len(R)} 通过  →  {OUT}")
for r in R:
    print(("  ✅ " if r["passed"] else "  ❌ ") + r["text"] + (f"   （{r['evidence']}）" if r["evidence"] else ""))
