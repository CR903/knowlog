# 评测结论（evals）

> 这份文件回答一个问题：**这套 skill 到底有没有用？** 用的是"同一批刁钻任务，带 skill vs 不带 skill 各跑一遍，再看评分"。
> 逐次运行的 `grading.json` / `benchmark.json` 落在临时工作区（`${TMPDIR}/…-ws/`），**未随仓库保留**（体积大且是运行产物）；
> 下面的数字与结论来源已标注，可按 §3 的命令原样重跑复核。

## 1. 三轮结果

| 轮次 | skill 版本 | 用例特点 | 带 skill | 不带 skill（基线） |
|---|---|---|---|---|
| iteration-1 | v1 | 从零搭体系、记日志、体检修复 | **100%** | 76.7% |
| iteration-2 | v0.2.0 | 新增：采纳异构 `docs/`、单面项目 flat 布局 | 见下汇总 | 见下汇总 |
| iteration-3 | v0.3.0 | 刁钻：跨月补写、索引占位、散落日志、死链、布局混用、文件名带空格 | 见下汇总 | 见下汇总 |

**三轮汇总（本轮会话运行记录；带 skill 63/63 = 100%，基线 53/63 = 84.1%）**

基线的 10 处失分**全部集中在"体系完整性"**，不是写文档的能力：

| 失分点 | 基线表现 | 带 skill |
|---|---|---|
| iteration-1 eval-0：从零搭一套体系 | 3/10（缺索引/门禁/路径规范等硬结构） | 10/10 |
| iteration-2 eval-3 | 6/8（缺结构自检与体检入口） | 8/8 |
| iteration-2 eval-4 | 6/7（结构自检不通过） | 7/7 |
| iteration-3 eval-5 / eval-6 | **0 差异** | 0 差异（见 §2 缺陷 1） |

> 结论：**差距来自"门禁与索引的硬约束"，而不是"会不会写 markdown"。** 基线也能把日志写得很像样，
> 但索引会漂、路径会乱、没有任何东西会在收尾时拦它 —— 这正是这个 skill 卖的东西。

## 2. 已知的评测设计缺陷（iteration-4 要修）

1. **夹具自带体系 → 差异恒为 0**：iteration-3 的两个用例把"已建好的 docs 体系"直接塞进夹具，
   于是"带 skill"与"不带 skill"的产出完全一样（0 差异），**这一轮实际上没有测到东西**。
   修法：夹具只放"任务与原始素材"（散落的日志、乱掉的索引），**不放已经建好的体系**。
2. **基线可以从 README 抄答案**：部分用例的期望结构在 skill 的 README/`references/` 里写得很细，
   基线 agent 读到后照着做就能拿高分（iteration-1 基线 76.7% 就偏乐观）。
   修法：评测环境**不给基线看 skill 仓库**（隔离 sandbox），或改成"只给任务描述"的黑盒形态。
3. **评分器主要看脚本判定**：`grade.py` 用的是可判定的断言（索引一致、路径合规、门禁非零退出），
   对"内容质量"覆盖弱。修法：补 2–3 条人工评审维度（可读性、是否复述 diff、坑位是否写清）。

## 3. 怎么复现

```bash
# ① 93 项确定性自测（不依赖模型，最快）
bash evals/test_scripts.sh

# ② 建夹具 + 准备 with/without 运行目录（iteration-1；2、3 换成同名脚本）
WS="${TMPDIR:-/tmp}/knowlog-ws"
bash evals/build_fixtures.sh  "$WS"
bash evals/setup_runs.sh      "$WS"          # 或 setup_iteration2.sh / setup_iteration3.sh
bash evals/setup_iteration2.sh "$WS"
bash evals/setup_iteration3.sh "$WS"

# ③ 在 $WS 的各 run-1/ 目录里跑 agent（带 skill 的目录里有 SKILL.md；不带的是对照）
# ④ 脚本评分 + 汇总
bash evals/run_grading.sh "$WS" iteration-1
#   benchmark 汇总与静态评审页面需要一个可选的第三方汇总器（未设则只出脚本评分）：
#   BENCH_TOOL=/path/to/tool bash evals/run_grading.sh "$WS" iteration-1
```

## 4. 与"确定性自测"的分工

| | `evals/test_scripts.sh` | 本文件的真实评测 |
|---|---|---|
| 测什么 | 脚本行为：布局/幂等/采纳/召回/体检/安装/打包/防泄露 | **模型行为**：给真实任务，agent 会不会照这套体系做 |
| 依赖模型 | ❌ 纯确定性（93 项） | ✅ 需要跑 agent |
| 何时跑 | 每次提交（CI + pre-commit） | 发版前 / 大改提示词与工作流后 |
