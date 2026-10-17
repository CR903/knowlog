#!/usr/bin/env python3
"""sync_assertions.py — 把 evals.json 的 expectations 同步进每个运行目录的 eval_metadata.json
用法: python3 evals/sync_assertions.py <workspace_dir>
"""

import json
import pathlib
import sys

ws = pathlib.Path(sys.argv[1])
skill = pathlib.Path(__file__).resolve().parents[1]
evals = json.loads((skill / "evals" / "evals.json").read_text(encoding="utf-8"))[
    "evals"
]
by_id = {e["id"]: e for e in evals}

n = 0
it = sys.argv[2] if len(sys.argv) > 2 else "iteration-1"
for meta_path in (ws / it).glob("*/eval_metadata.json"):
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    e = by_id.get(meta["eval_id"])
    if not e:
        continue
    meta["assertions"] = [
        {"text": t, "passed": None, "evidence": ""} for t in e["expectations"]
    ]
    meta["prompt"] = e["prompt"]
    meta_path.write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    n += 1
print(f"已同步 {n} 个 eval_metadata.json")
