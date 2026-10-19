# 评测结论（evals）

> 这份文件回答一个问题：**这套 skill 到底有没有用？** 方法是"同一批任务，带 skill vs 不带 skill 各跑一遍，再看评分"。
> 逐次运行的 `grading.json` / `run_meta.json` / `transcript.txt` 落在临时工作区（`${TMPDIR}/…-iter4/`），**不随仓库保留**（体积大、且是运行产物）；
> 结论与复现命令见下面各节。

## 1. 历史结论（iteration-1..3）

| 轮次 | skill 版本 | 用例特点 | 带 skill | 不带 skill（基线） |
|---|---|---|---|---|
| iteration-1 | v1 | 从零搭体系、记日志、体检修复 | **100%** | 76.7% |
| iteration-2 | v0.2.0 | 新增：采纳异构 `docs/`、单面项目 flat 布局 | — | — |
| iteration-3 | v0.3.0 | 刁钻：跨月补写、索引占位、散落日志、死链、布局混用 | 2 个用例 **0 差异** | 2 个用例 0 差异 |

基线失分集中在**体系完整性**（结构/索引/门禁），不在"会不会写文档"。

## 2. iteration-3 暴露的评测设计缺陷（三个，已全部修）

| # | 缺陷 | 后果 | 修法（iteration-4，已实施） |
|---|---|---|---|
| 1 | **夹具里放了"已建好的体系"** | 两边都照抄现成结构 → **0 差异**，等于没测 | `evals/build_fixtures_v4.sh`：夹具只给**原始素材**（代码 + 散落/异构旧文档 + 一个刚做完的任务描述），不给现成体系（唯一例外 eval-9，原因见 `evals-v4.json` 的 `design_notes`） |
| 2 | **基线不干净**：以为"不带 skill"，其实全局装着，模型照样能读到/触发 | "带 skill 更好"的结论偏乐观 | `evals/run_case.sh`：**机械隔离** —— 跑基线时把已安装的 skill 临时改名移开 + `--disable-slash-commands` 双保险；移开失败**直接中止**（宁可没数据，也不要假基线）；证据写进 `run_meta.json` 的 `isolation` 字段 |
| 3 | **只评"结构对不对"**，不评"写得好不好" | 会把"形状不同"误判成"质量更差" | `evals/review-rubric.md`：新增 3 条人工维度（D1 日志重点 / D2 知识可复用 / D3 尊重既有约定，各 0–2 分）；`grade_v4.py` 自动在每个 run 目录生成 `manual_review.md` 骨架 |

## 3. iteration-4 试点结果（eval-7「全新项目，连 docs/ 都没有」）

跑法（串行两次，因为基线要临时移开全局 skill）：

```bash
WS="${TMPDIR:-/tmp}/knowlog-iter4"
bash evals/setup_iteration4.sh "$WS"
D="$WS/iteration-4/eval-7-fresh-project-no-docs"
bash evals/run_case.sh "$D/with_skill"    with_skill      # ①
bash evals/run_case.sh "$D/without_skill" without_skill   # ②（机械隔离）
python3 evals/grade_v4.py eval-7 "$D/with_skill"    "$D/with_skill/grading.json"
python3 evals/grade_v4.py eval-7 "$D/without_skill" "$D/without_skill/grading.json"
```

| 维度 | 带 skill | 基线（真隔离） |
|---|---|---|
| **结构断言（9 条）** | **9 / 9** | **0 / 9** |
| 人工量表（D1/D2/D3，各 2 分） | **6 / 6** | **5 / 6** |
| 它实际做了什么 | 建 `docs/daily/2026-10/` 日志、by-end 知识库 + 两级索引、`domain context`、`scripts/`（门禁 `--strict` 通过）、`AGENTS.md` 托管块；沉淀 2 篇带"触发条件+根因+处置"的知识 | 建 `CLAUDE.md` + `docs/conventions.md` + `docs/dev-log.md` + `docs/pitfalls.md`（含编号索引 P-001）+ 两套模板；日志写了「做了什么/验证/坑与后续」 |

**怎么读这个差距（重要）**：

- 结构上 9:0 是**压倒性**的 —— 基线那套没有月份目录、没有两级索引、没有可运行的门禁，所以我的断言（都是 knowlog 形状）一条都过不了。
- 但内容质量是 **6:5，几乎打平** —— 基线不是"不会写文档"，它建了一套自洽的轻量约定（日志模板 + 坑位编号 + grep 检索）。
- 因此结论是：**这套 skill 的增量在「可校验的约束与索引」，不在「帮你写字」**。这既印证了它的价值主张，也说明评测必须"结构断言 + 人工量表"两把尺子同时用 —— 只用结构断言会把基线冤枉成 0 分。

## 4. 已知干扰与注意事项（下次跑之前先看这节）

1. **第三方钩子会污染运行目录**：本机另一个记忆工具（`.remember/`）会在任何项目里写文件，
   不排除就会干扰"内容关键词"类断言（比如它的记忆文件里恰好出现 `toFixed`）。
   → `grade_v4.py` 已把 `.remember/`、`.trellis/`、`node_modules/`、以及评测自产文件列入 `IGNORE_DIRS/IGNORE_FILES`。
2. **隔离是"临时改全局状态"**：基线运行期间 `~/.claude/skills/knowlog` 等会被改名为 `.hidden-<pid>`（宿主 harness 的 skill 列表会短暂变化），
   脚本用 `trap` 自动还原。**若被强杀**，手工检查并还原：`ls -d ~/.claude/skills/*.hidden-*`。
3. **结构断言是"knowlog 形状"的**：基线拿 0 只说明"没按这个形状做"，不代表产出没用 —— 判"有没有用"要用 §2 的人工量表。
4. **模型会变**：本环境下 `claude` CLI 实际路由到 `deepseek-v4-flash`（运行时会打印 `unrecognized_model` 警告），
   所以数字是"**该模型在该配置下**"的结果。换模型/换版本要重跑，不能直接引用。
5. **eval-8 / eval-9 尚未跑**：夹具、运行目录、评分器都已就绪（`setup_iteration4.sh` 一次生成 3 个用例），只差跑（每个用例 2 次 agent 调用）。

## 5. 复现命令

```bash
# ① 93 项确定性自测（不依赖模型，最快；CI 也跑这个）
bash evals/test_scripts.sh

# ② iteration-4：造夹具 + 运行目录
WS="${TMPDIR:-/tmp}/knowlog-iter4"
bash evals/setup_iteration4.sh "$WS"       # → 3 个用例 × (with_skill, without_skill)

# ③ 跑用例（务必串行：基线要临时移开全局 skill）
D="$WS/iteration-4/eval-7-fresh-project-no-docs"
bash evals/run_case.sh "$D/with_skill"    with_skill
bash evals/run_case.sh "$D/without_skill" without_skill

# ④ 客观评分 + 生成人工评审骨架
python3 evals/grade_v4.py eval-7 "$D/with_skill"    "$D/with_skill/grading.json"
python3 evals/grade_v4.py eval-7 "$D/without_skill" "$D/without_skill/grading.json"
# 然后按 evals/review-rubric.md 填 manual_review.md
```

> iteration-1..3 的夹具/评分器仍在（`build_fixtures.sh` / `setup_runs.sh` / `grade.py`），保留是为了让历史结论可追溯；
> **新一轮请用 iteration-4 这一套**（夹具设计与隔离机制都不同，数字不可混用）。

## 6. 与"确定性自测"的分工

| | `evals/test_scripts.sh` | 本文件的真实评测 |
|---|---|---|
| 测什么 | 脚本行为：布局/幂等/采纳/召回/体检/安装/打包/防泄露 | **模型行为**：给真实任务，agent 会不会照这套体系做 |
| 依赖模型 | ❌ 纯确定性（93 项） | ✅ 需要跑 agent |
| 何时跑 | 每次提交（CI + pre-commit） | 发版前 / 大改提示词与工作流后 |
