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
