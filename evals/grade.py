#!/usr/bin/env python3
"""grade.py — knowlog 评测的客观评分器

用法: python3 evals/grade.py <eval_id> <project_dir> <out_grading_json>

断言尽量直接用「脚本的退出码」和「文件集合的关系」判定，而不是让模型"看着像"就过。
输出 grading.json：{"expectations": [{"text":..., "passed":..., "evidence":...}]}
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

R = []  # (text, passed, evidence)


def check(text: str, passed: bool, evidence: str):
    R.append({"text": text, "passed": bool(passed), "evidence": evidence[:600]})


def run_gate() -> tuple[int, str]:
    sh = PROJ / "scripts" / "check-daily-index.sh"
    if not sh.exists():
        return 127, "scripts/check-daily-index.sh 不存在"
    p = subprocess.run(
        ["bash", str(sh), "--strict", "--root", str(PROJ)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    return p.returncode, (p.stdout + p.stderr).strip()


def daily_logs() -> list[pathlib.Path]:
    d = PROJ / "docs" / "daily"
    return sorted(d.rglob("*.md")) if d.is_dir() else []


def index_text() -> str:
    p = PROJ / "docs" / "index.md"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def links(text: str) -> list[str]:
    return re.findall(r"\]\((daily/[^)\s]+?\.md)\)", text)


if EVAL == "eval-0":
    # ---- 新项目搭建 ----
    logs = daily_logs()
    loose = [p for p in logs if p.parent == PROJ / "docs" / "daily"]
    check(
        "docs/daily 下日志都已按月份目录归位（无散落 .md）",
        not loose,
        f"散落: {[p.name for p in loose]}"
        if loose
        else f"{len(logs)} 篇全部在月份目录",
    )
    check(
        "docs/knowledge 下按端建了目录且每端含四个分类",
        all(
            (PROJ / "docs" / "knowledge" / e / c).is_dir()
            for e in ["backend", "frontend"]
            if (PROJ / "docs" / "knowledge" / e).is_dir()
            for c in ["architecture", "guides", "troubleshooting", "best-practices"]
        )
        and (PROJ / "docs" / "knowledge" / "backend").is_dir(),
        "存在目录: "
        + ", ".join(
            sorted(
                p.name for p in (PROJ / "docs" / "knowledge").iterdir() if p.is_dir()
            )
        )
        if (PROJ / "docs" / "knowledge").is_dir()
        else "无 knowledge/",
    )
    check(
        "知识库两级索引存在（分端 index.md + 根 index.md）",
        (PROJ / "docs" / "knowledge" / "index.md").exists()
        and any(
            (PROJ / "docs" / "knowledge" / e / "index.md").exists()
            for e in ["backend", "frontend"]
        ),
        f"根索引={((PROJ / 'docs' / 'knowledge' / 'index.md').exists())}，分端索引="
        f"{[e for e in ['backend', 'frontend'] if (PROJ / 'docs' / 'knowledge' / e / 'index.md').exists()]}",
    )
    check(
        "docs/domain context/ 已建立（领域记忆层）",
        (PROJ / "docs" / "domain context").is_dir(),
        str(sorted(p.name for p in (PROJ / "docs" / "domain context").iterdir()))
        if (PROJ / "docs" / "domain context").is_dir()
        else "不存在",
    )
    check(
        "docs/agents/ 已建立（给 agent 的约定）",
        (PROJ / "docs" / "agents").is_dir(),
        str(sorted(p.name for p in (PROJ / "docs" / "agents").iterdir()))
        if (PROJ / "docs" / "agents").is_dir()
        else "不存在",
    )
    scripts = [
        "bootstrap-docs.sh",
        "new-daily-log.sh",
        "check-daily-index.sh",
        "new-knowledge.sh",
        "new-keyword.sh",
        "knowledge-retrieve.sh",
    ]
    have = [
        s
        for s in scripts
        if (PROJ / "scripts" / s).exists() and os.access(PROJ / "scripts" / s, os.X_OK)
    ]
    check("scripts/ 下六个脚本齐备且可执行", len(have) == len(scripts), f"有: {have}")
    agents = (
        (PROJ / "AGENTS.md").read_text(encoding="utf-8")
        if (PROJ / "AGENTS.md").exists()
        else ""
    )
    check(
        "AGENTS.md 含托管块标记（KNOWLOG:START/END）且写了日志/门禁约束",
        "KNOWLOG:START" in agents
        and "KNOWLOG:END" in agents
        and ("日志" in agents)
        and ("check-daily-index" in agents),
        f"AGENTS.md 长度 {len(agents)}，含 START={'KNOWLOG:START' in agents}",
    )
    rc, out = run_gate()
    check(
        "门禁 check-daily-index.sh --strict 通过（退出码 0）",
        rc == 0,
        f"rc={rc}; {out.splitlines()[-1] if out else ''}",
    )
    demo = [p for p in logs if p.parent.name.count("-") == 1]
    check(
        "至少演示创建了一篇日志，且落位到 daily/<YYYY-MM>/",
        len(demo) >= 1,
        f"{[str(p.relative_to(PROJ)) for p in demo]}",
    )
    check(
        "索引里的日志链接与磁盘文件一致（无死链）",
        all((PROJ / "docs" / l).exists() for l in links(index_text())),
        f"链接 {len(links(index_text()))} 条",
    )

elif EVAL == "eval-1":
    # ---- 任务收尾记录日志 ----
    logs = daily_logs()
    new = [
        p
        for p in logs
        if p.name
        not in {"2026-10-12_fix-money-format.md", "2026-10-14_add-order-export.md"}
    ]
    check(
        "新建了日志文件（本次任务一篇）",
        len(new) >= 1,
        f"新增: {[str(p.relative_to(PROJ)) for p in new]}",
    )
    check(
        "新日志落在 daily/<YYYY-MM>/ 月份目录下（未散落在 daily 根）",
        bool(new) and all(p.parent.name.count("-") == 1 for p in new),
        f"父目录: {[p.parent.name for p in new]}",
    )
    idx = index_text()
    check(
        "新日志在 docs/index.md 有索引行且链接可达",
        all(f"daily/{p.parent.name}/{p.name}" in idx for p in new)
        and all(
            (PROJ / "docs" / f"daily/{p.parent.name}/{p.name}").exists() for p in new
        ),
        f"索引命中: {[f'daily/{p.parent.name}/{p.name}' in idx for p in new]}",
    )
    body = "\n".join(p.read_text(encoding="utf-8") for p in new)
    check(
        "日志写入了实质内容（根因/判据等，≥300 字）",
        len(body) >= 300,
        f"字符数 {len(body)}",
    )
    check(
        "日志包含根因或验证/判据的痕迹（不是只抄 diff）",
        any(k in body for k in ["根因", "判据", "验证", "为什么"]),
        f"关键词命中: {[k for k in ['根因', '判据', '验证', '为什么'] if k in body]}",
    )
    kdir = PROJ / "docs" / "knowledge"
    kdocs = [p for p in kdir.rglob("*.md") if p.name not in {"index.md", "README.md"}]
    check(
        "沉淀了知识文档（knowledge 下新增/更新一篇）",
        len(kdocs) >= 3,
        f"knowledge 文档数 {len(kdocs)}（初始 2 篇）",
    )
    kroot = (
        (kdir / "index.md").read_text(encoding="utf-8")
        if (kdir / "index.md").exists()
        else ""
    )
    checksum = any(d.name.replace(".md", "") in kroot for d in kdocs)
    check(
        "新知识已在根索引 docs/knowledge/index.md 登记",
        checksum,
        f"根索引长度 {len(kroot)}",
    )
    rc, out = run_gate()
    check(
        "门禁 check-daily-index.sh --strict 通过（退出码 0）",
        rc == 0,
        f"rc={rc}; {out.splitlines()[-1] if out else ''}",
    )

elif EVAL == "eval-2":
    # ---- 体检修复 ----
    logs = daily_logs()
    loose = [p for p in logs if p.parent == PROJ / "docs" / "daily"]
    check(
        "散落在 daily 根的日志已归位到月份目录",
        not loose,
        f"仍散落: {[p.name for p in loose]}"
        if loose
        else f"{len(logs)} 篇都在月份目录",
    )
    mism = [
        p
        for p in logs
        if re.match(r"^\d{4}-\d{2}", p.name) and p.name[:7] != p.parent.name
    ]
    check(
        "不存在「目录月 ≠ 文件名月」的日志",
        not mism,
        f"不合规: {[str(p.relative_to(PROJ)) for p in mism]}",
    )
    idx = index_text()
    flat = [l for l in links(idx) if not re.match(r"^daily/\d{4}-\d{2}/", l)]
    check(
        "索引中不再有旧的扁平链接（daily/YYYY-MM-DD_x.md）",
        not flat,
        f"扁平链接: {flat}",
    )
    check(
        "索引无死链（每条链接都有对应文件）",
        all((PROJ / "docs" / l).exists() for l in links(idx)),
        f"{len(links(idx))} 条链接",
    )
    check("原日志未被误删（≥3 篇仍在）", len(logs) >= 3, f"当前 {len(logs)} 篇")
    missing = [p for p in logs if f"daily/{p.parent.name}/{p.name}" not in idx]
    check(
        "每篇日志都有索引行（无遗漏）",
        not missing,
        f"缺索引: {[str(p.relative_to(PROJ)) for p in missing]}",
    )
    rc, out = run_gate()
    check(
        "门禁 check-daily-index.sh --strict 通过（退出码 0）",
        rc == 0,
        f"rc={rc}; {out.splitlines()[-1] if out else ''}",
    )


elif EVAL == "eval-3":
    # ---- 采纳异构 docs：日志归位 + 不破坏用户内容 + 结构可体检 ----
    logs = daily_logs()
    check("原有日志已按月份归位（≥4 篇在 docs/daily/<YYYY-MM>/ 下）",
          len(logs) >= 4 and all(p.parent.name.count("-") == 1 for p in logs),
          f"{len(logs)} 篇；父目录={sorted({p.parent.name for p in logs})}")
    idx = index_text()
    lk = links(idx)
    check("索引登记了这些日志且链接全部可达（无死链）",
          len(lk) >= 4 and all((PROJ / "docs" / l).exists() for l in lk),
          f"{len(lk)} 条链接")
    check("未把 README/CHANGELOG 当成日志迁移",
          not any(p.name.startswith(("README", "CHANGELOG")) for p in logs),
          f"日志文件名：{[p.name for p in logs]}")
    ag = (PROJ / "AGENTS.md").read_text(encoding="utf-8") if (PROJ / "AGENTS.md").exists() else ""
    check("原有 AGENTS.md 的用户内容被保留（未被整体覆盖）",
          "不要直接改 migration 目录" in ag, f"AGENTS.md 长度 {len(ag)}")
    check("AGENTS.md 已注入 DOCS-SYSTEM 托管块（约束落地）",
          "KNOWLOG:START" in ag and "KNOWLOG:END" in ag, "")
    kn_text = ""
    for q in (PROJ / "docs").rglob("*.md"):
        kn_text += q.read_text(encoding="utf-8", errors="ignore")
    check("原有知识笔记的内容没有丢（内容以任意形式保留）",
          "单位换算三段式" in kn_text, "在 docs/ 下全文检索该特征串")
    st = PROJ / "scripts" / "check-docs-structure.sh"
    check("装上了结构自检脚本并可运行", st.exists(), f"exists={st.exists()}")
    doc = PROJ / "scripts" / "docs-doctor.sh"
    rc_doc = 127
    if doc.exists():
        import subprocess as _sp
        rc_doc = _sp.run(["bash", str(doc), "--root", str(PROJ)], capture_output=True, text=True).returncode
    check("体检总入口通过（结构 + 两项索引）", rc_doc == 0, f"rc={rc_doc}")

elif EVAL == "eval-4":
    # ---- 单面项目（没有前后端）：应自动用 flat 布局 ----
    kdir = PROJ / "docs" / "knowledge"
    cats = ["architecture", "guides", "troubleshooting", "best-practices"]
    check("知识库用 flat 布局：四个分类直接在 docs/knowledge/ 下",
          all((kdir / c).is_dir() for c in cats), f"存在：{[c for c in cats if (kdir / c).is_dir()]}")
    end_dirs = [d.name for d in kdir.iterdir() if d.is_dir() and d.name not in cats
                and (d / "index.md").exists()] if kdir.is_dir() else []
    check("没有多余造出「端层」（单面项目不该有 backend/frontend 之类）",
          not end_dirs, f"意外的端目录：{end_dirs}")
    check("根索引存在且不是空的", (kdir / "index.md").exists(),
          f"{(kdir / 'index.md').read_text(encoding='utf-8')[:80] if (kdir/'index.md').exists() else ''}")
    logs = daily_logs()
    check("演示/真实日志落在 docs/daily/<YYYY-MM>/（路径不变量）",
          len(logs) >= 1 and all(p.parent.name.count("-") == 1 for p in logs),
          f"{[str(p.relative_to(PROJ)) for p in logs]}")
    idx = index_text()
    check("日志在索引里有对应行且链接可达",
          len(logs) >= 1 and all(f"daily/{p.parent.name}/{p.name}" in idx for p in logs), "")
    rc_struct, out_struct = (127, "missing")
    st = PROJ / "scripts" / "check-docs-structure.sh"
    if st.exists():
        import subprocess as _sp
        _p = _sp.run(["bash", str(st), "--root", str(PROJ), "--strict"], capture_output=True, text=True)
        rc_struct, out_struct = _p.returncode, (_p.stdout + _p.stderr).strip().splitlines()[-1]             if (_p.stdout + _p.stderr).strip() else ""
    check("结构自检通过（--strict）", rc_struct == 0, f"rc={rc_struct}; {out_struct}")
    ag = (PROJ / "AGENTS.md").read_text(encoding="utf-8") if (PROJ / "AGENTS.md").exists() else ""
    check("AGENTS.md 托管块存在（约束落地）", "KNOWLOG:START" in ag, f"len={len(ag)}")


elif EVAL == "eval-5":
    # ---- 跨月补写 + 索引占位 + 散落日志 + 死链 ----
    logs = daily_logs()
    loose = [p for p in logs if p.parent == PROJ / "docs" / "daily"]
    check("daily 根下不再有散落日志（已按月份归位）", not loose,
          f"仍散落: {[p.name for p in loose]}" if loose else f"{len(logs)} 篇都在月份目录")
    sept = [p for p in logs if p.parent.name == "2026-09"]
    check("跨月补写的日志落在 2026-09/（按日志日期归月，不是今天所在的月）",
          len(sept) >= 1, f"2026-09/ 下: {[p.name for p in sept]}")
    octo = [p for p in logs if p.parent.name == "2026-10"]
    check("原有 2026-10 日志没有被搬走", len(octo) >= 1, f"2026-10/ 下: {[p.name for p in octo]}")
    idx = index_text()
    lk = links(idx)
    check("索引中不再有旧扁平路径（死链已修）",
          all((PROJ / "docs" / l).exists() for l in lk) and not [l for l in lk if not l.startswith("daily/20")],
          f"{len(lk)} 条链接，示例 {lk[:3]}")
    check("索引行里的占位（待回填/待补记）已填实",
          "待回填" not in idx and "待补记" not in idx,
          f"仍含占位={('待回填' in idx) or ('待补记' in idx)}")
    check("9 月日志的索引行落在 ### 2026-09 表格里",
          "### 2026-09" in idx and any("daily/2026-09/" in l for l in lk), "")
    rc, out = run_gate()
    check("门禁 check-daily-index.sh --strict 通过", rc == 0,
          f"rc={rc}; {out.splitlines()[-1] if out else ''}")
    doc = PROJ / "scripts" / "docs-doctor.sh"
    rc2 = 127
    if doc.exists():
        import subprocess as _sp
        rc2 = _sp.run(["bash", str(doc), "--root", str(PROJ), "--strict", "--quiet"],
                      capture_output=True, text=True).returncode
    check("体检总入口 --strict 通过（结构 + 两项索引）", rc2 == 0, f"rc={rc2}")

elif EVAL == "eval-6":
    # ---- 知识库布局混用 + 非常规目录 + 命名带空格 ----
    kr = PROJ / "docs" / "knowledge"
    text_all = ""
    for q in (PROJ / "docs").rglob("*.md"):
        text_all += q.read_text(encoding="utf-8", errors="ignore")
    check("内容零丢失：混用目录里的知识仍在（特征串可检索到）",
          "箱→瓶→ml" in text_all, "搜 '箱→瓶→ml'")
    check("非常规目录里的内容仍在（特征串可检索到）",
          "结算口径要跟财务对齐" in text_all, "搜 '结算口径要跟财务对齐'")
    check("原有端目录知识仍在", "按 GroupKey 合并时漏了 unitId" in text_all, "搜 backend 那篇")
    st = PROJ / "scripts" / "check-docs-structure.sh"
    out = ""
    rc_st = 127
    if st.exists():
        import subprocess as _sp
        _p = _sp.run(["bash", str(st), "--root", str(PROJ), "--strict"], capture_output=True, text=True)
        rc_st = _p.returncode; out = (_p.stdout + _p.stderr)
    check("结构自检 --strict 通过（布局混用/非常规分类必须已收口）", rc_st == 0,
          f"rc={rc_st}; " + " / ".join([l for l in out.splitlines() if "布局" in l or "非常规" in l][:2]))
    cats = ["architecture", "guides", "troubleshooting", "best-practices"]
    ends = [d.name for d in kr.iterdir() if d.is_dir() and d.name not in cats and (d / "index.md").exists()] \
        if kr.is_dir() else []
    bare = [c for c in cats if (kr / c).is_dir()]
    check("最终只存在一种布局（不会既 by-end 又 flat）",
          not (ends and bare), f"端={ends} 裸分类={bare}")
    doc = PROJ / "scripts" / "docs-doctor.sh"
    rc2 = 127
    if doc.exists():
        import subprocess as _sp
        rc2 = _sp.run(["bash", str(doc), "--root", str(PROJ), "--strict", "--quiet"],
                      capture_output=True, text=True).returncode
    check("体检总入口 --strict 通过", rc2 == 0, f"rc={rc2}")
    unreg = []
    for p in kr.rglob("*.md"):
        if p.name in {"README.md", "index.md"}:
            continue
        if f"]({p.relative_to(kr).as_posix()})" not in (kr / "index.md").read_text(encoding="utf-8") \
           and f"]({p.parent.name}/{p.name})" not in (kr / "index.md").read_text(encoding="utf-8"):
            unreg.append(str(p.relative_to(PROJ)))
    check("所有知识文档都已登记进索引（无遗漏）", not unreg, f"未登记: {unreg[:4]}")

else:
    print(f"未知 eval_id: {EVAL}", file=sys.stderr)
    sys.exit(2)

passed = sum(1 for r in R if r["passed"])
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(
    json.dumps(
        {
            "eval_id": EVAL,
            "project": str(PROJ),
            # 第三方汇总器读的是 summary.*，不要只写扁平字段
            "summary": {
                "passed": passed,
                "failed": len(R) - passed,
                "total": len(R),
                "pass_rate": round(passed / len(R), 4) if R else 0.0,
            },
            "expectations": R,
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)
print(f"{EVAL}: {passed}/{len(R)} 通过  →  {OUT}")
for r in R:
    print(
        f"  [{'PASS' if r['passed'] else 'FAIL'}] {r['text']}\n        {r['evidence'][:160]}"
    )
