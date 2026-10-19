#!/bin/bash
# setup_iteration4.sh — 为 iteration-4 造运行目录（含 PROMPT.md / 基线文件快照 / 元数据）
#
# 用法: bash evals/setup_iteration4.sh <workspace_dir> [--force] [--only <eval-id>]
#   （默认）已存在的用例目录**保留不动** —— 避免把跑过的结果清掉（pilot 每次会调本脚本）
#   --force      重建全部用例目录
#   --only <id>  只重建指定用例（如 --only eval-10）
#
# 目录形态（与 iteration-1 一致，方便沿用评分流程）：
#   <WS>/iteration-4/<eval_id>-<name>/{with_skill,without_skill}/
#     ├── PROMPT.md            给 agent 的任务
#     ├── baseline_files.json  夹具快照（用于判"新增了什么"）
#     └── （夹具内容）
set -uo pipefail
WS="${1:?用法: bash evals/setup_iteration4.sh <workspace_dir> [--force] [--only <eval-id>]}"
shift || true
SETUP_ARGS="${*:-}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

bash "$SKILL_DIR/evals/build_fixtures_v4.sh" "$WS" > /dev/null || exit 1

WS="$WS" SKILL_DIR="$SKILL_DIR" SETUP_ARGS="$SETUP_ARGS" python3 - <<'PY'
import json, os, pathlib, shutil, subprocess

ws = pathlib.Path(os.environ["WS"])
skill = pathlib.Path(os.environ["SKILL_DIR"])
it = ws / "iteration-4"
spec = json.loads((skill / "evals" / "evals-v4.json").read_text(encoding="utf-8"))

args = os.environ.get("SETUP_ARGS", "").split()
force = "--force" in args
only = args[args.index("--only") + 1] if "--only" in args else ""

for ev in spec["evals"]:
    case = f'{ev["id"]}-{ev["name"]}'
    cdir = it / case
    if only and ev["id"] != only:
        continue
    # 幂等：已有跑过结果的用例目录默认保留（pilot 每次都会调本脚本）
    if not force and (cdir / "with_skill").is_dir() and (cdir / "without_skill").is_dir():
        print(f'⏭️  {ev["id"]} 已存在 → 跳过（要重建：--force 或 --only {ev["id"]}）')
        continue
    for cfg in ("with_skill", "without_skill"):
        dest = cdir / cfg
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True)
        shutil.copytree(ws / "fixtures-v4" / ev["fixture"], dest, dirs_exist_ok=True)
        # 每个运行目录独立成 git 仓库：夹具状态作为基线提交（agent 改动一眼可见）
        shutil.rmtree(dest / ".git", ignore_errors=True)
        subprocess.run(["git", "init", "-q", "."], cwd=dest)
        subprocess.run(["git", "add", "-A"], cwd=dest, capture_output=True)
        subprocess.run(["git", "-c", "user.email=e@e", "-c", "user.name=e", "commit", "-qm",
                        f'fixture: {ev["id"]}'], cwd=dest, capture_output=True)
        # 任务提示
        (dest / "PROMPT.md").write_text(
            "# 任务\n\n" + ev["prompt"] + "\n\n"
            "# 验收期望（不给你看，仅评测用）\n"
            + "\n".join(f"- {e}" for e in ev.get("expectations", []))
            + "\n\n（上面的验收期望仅供评测记录；agent 看到的只是「任务」那一段）\n",
            encoding="utf-8")
        # 夹具快照（判新增/改动用）
        files = sorted(str(p.relative_to(dest)) for p in dest.rglob("*")
                       if p.is_file() and ".git" not in p.parts and p.name != "PROMPT.md")
        (cdir / "baseline_files.json").write_text(
            json.dumps({"fixture": ev["fixture"], "files": files}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")
    (cdir / "eval_metadata.json").write_text(json.dumps({
        "iteration": 4, "eval_id": ev["id"], "eval_name": ev["name"], "fixture": ev["fixture"],
        "measures": ev.get("measures", ""),
        "run_dirs": {"with_skill": str(cdir / "with_skill"),
                     "without_skill": str(cdir / "without_skill")},
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f'✅ {ev["id"]} ({ev["name"]}) → {cdir}/{{with_skill,without_skill}}')

print(f"\n下一步：bash evals/run_case.sh {it}/eval-7-fresh-project-no-docs/with_skill with_skill")
print(f"        bash evals/run_case.sh {it}/eval-7-fresh-project-no-docs/without_skill without_skill")
PY
