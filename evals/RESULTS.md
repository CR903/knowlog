# 评测结论（evals）

> 这份文件回答一个问题：**这套 skill 到底有没有用？** 方法是"同一批任务，带 skill vs 不带 skill 各跑一遍，再看评分"。
> 逐次运行的 `grading.json` / `run_meta.json` / `transcript.txt` / `manual_review.md` 落在临时工作区（`${TMPDIR}/knowlog-iter4/`），**不随仓库保留**（体积大、且是运行产物）；
> 结论与复现命令见下面各节。跑法说明书在 `evals/README.md`。

## 1. 历史结论（iteration-1..3）

| 轮次 | skill 版本 | 用例特点 | 带 skill | 不带 skill（基线） |
|---|---|---|---|---|
| iteration-1 | v1 | 从零搭体系、记日志、体检修复 | **100%** | 76.7% |
| iteration-2 | v0.2.0 | 新增：采纳异构 `docs/`、单面项目 flat 布局 | — | — |
| iteration-3 | v0.3.0 | 刁钻：跨月补写、索引占位、散落日志、死链、布局混用 | 2 个用例 **0 差异** | 2 个用例 0 差异 |

基线失分集中在**体系完整性**（结构/索引/门禁），不在"会不会写文档"。

## 2. iteration-3 暴露的三个评测设计缺陷（已全部修）

| # | 缺陷 | 后果 | 修法（iteration-4，已实施） |
|---|---|---|---|
| 1 | **夹具里放了"已建好的体系"** | 两边都照抄现成结构 → **0 差异**，等于没测 | `evals/build_fixtures_v4.sh`：夹具只给**原始素材**（代码 + 散落/异构旧文档 + 刚做完的任务描述），不给现成体系（唯一例外 eval-9，原因见 `evals-v4.json` 的 `design_notes`） |
| 2 | **基线不干净**：以为"不带 skill"，其实全局装着，模型照样能读到 | "带 skill 更好"的结论偏乐观 | `evals/run_case.sh`：**机械隔离** —— 跑基线时把已安装 skill 临时改名移开 + `--disable-slash-commands` 双保险；移开失败**直接中止**（宁可没数据，不要假基线）；证据写进 `run_meta.json.isolation` |
| 3 | **只评"结构对不对"**，不评"写得好不好" | 会把"形状不同"误判成"质量更差" | `evals/review-rubric.md`：3 条人工维度（D1 日志重点 / D2 知识可复用 / D3 尊重既有约定，各 0–2 分）；`grade_v4.py` 自动生成 `manual_review.md` 骨架 |

## 3. iteration-4 结果（三个用例，带/不带各跑一次）

| 用例 | 它测什么 | 结构断言 | 人工量表 |
|---|---|---|---|
| eval-7 全新项目（连 `docs/` 都没有） | 从零搭结构 | **9/9** vs **0/9** | **6/6** vs **5/6** |
| eval-8 一团乱的历史文档 | 归位/合并 + 补索引 + 识别死链 | **9/9** vs **6/9** | **6/6** vs **4/6** |
| eval-9 体系已就位 + 刚做完的任务 | 收尾质量（写日志/沉淀知识/同步索引） | **7/7** vs **7/7** | **6/6** vs **6/6** |
| **合计** | | **25/25（100%）** vs **13/25（52%）** | **18/18** vs **15/18（83%）** |

### 逐例解读（人话）

- **eval-7（差距最大）**：带 skill 建出完整体系（月份目录日志、by-end 知识库 + 两级索引、`domain context`、`scripts/` 且门禁 `--strict` 通过、`AGENTS.md` 托管块）。
  基线建了 `CLAUDE.md` + `docs/conventions.md` + `docs/dev-log.md` + `docs/pitfalls.md`（带 `P-001` 编号索引）+ 两套模板 —— **内容质量并不差（5/6）**，
  但它没有任何"能自动拦人"的东西：没有门禁、没有两级索引、没有月份目录。所以结构 0/9 这个数字**只说明"形状不同"**。
- **eval-8（差距具体）**：基线把两篇日志搬进了 `docs/daily/2026-09/`（显眼的搬家它做得对），但漏掉三件"不显眼却决定长期可用"的事：
  孤儿知识文档没归位也没登记、没有可运行的门禁、没有 `AGENTS.md` 托管块、也没给本次整理留一篇收尾记录（人工量表 D1/D2 各扣 1 分）。
- **eval-9（打平，重要发现）**：两边都照项目里既有的 `docs/template.md` 写出了同样的五段式日志与知识文档，基线甚至把真实提交 hash 填了进去（7/7、6/6）。
  → 这说明：**体系一旦装好，模板与钩子本身就把"收尾质量"拉齐了** —— 这个 skill 的增量主要在"**搭与整**"（eval-7/8），而不在"每次收尾都需要它"。

### 一句话结论

**增量在「可校验的约束与索引」，不在「帮你写字」。** 结构断言 100% : 52% 说明它确实带来了别处没有的机器可校验性；
人工量表 18:15 说明它并不会让人写得更漂亮。两把尺子同时看，结论才不偏。

## 4. 已知干扰与教训（跑之前先看这节）

1. **第三方钩子会污染运行目录**：本机另一个记忆工具（`.remember/`）会在任何项目里写文件，
   它的记忆文件可能恰好包含断言搜索的关键词。
   → `grade_v4.py` 已把 `.remember/`、`.trellis/`、`node_modules/` 与评测自产文件列入 `IGNORE_DIRS/IGNORE_FILES`；
   跑正式评测时最好把这类钩子临时关掉。
2. **隔离是"临时改全局状态"**：基线运行期间 `~/.claude/skills/knowlog` 等会变成 `.hidden-<pid>`（宿主 harness 的 skill 列表会短暂变化），
   `run_case.sh` 用 `trap` 自动还原；`run_iteration4_pilot.sh` 开头/结尾也会兜一次。
   **若被强杀**：手工检查 `ls -d ~/.claude/skills/*.hidden-*`。
3. **模型会变**：本环境 `claude` CLI 实际路由到 `deepseek-v4-flash`（运行时会打印 `unrecognized_model` 警告），
   数字是"**该模型在该配置下**"的结果，换模型必须重跑，不能直接引用。
4. **断言误伤是最隐蔽的偏差**（本轮真踩到）：第一版 `grade_v4.py` 把索引**说明文字**里的 `<slug>` 当成"占位残留"，
   于是 eval-9 两边同时被扣分（7/7 → 6/7）——**误伤会同时压低两边，让结论看起来"都差不多"，从而掩盖真实差异**。
   修法：只检查表格行（`| ... |`）里的占位符。写断言时务必分清"说明文字"与"残留内容"。
5. **串行跑**：基线要动全局 skill，with/without 不能并行。

## 5. 复现命令

```bash
# ① 93 项确定性自测（不依赖模型，最快；CI 也跑这个）
bash evals/test_scripts.sh

# ② iteration-4：造夹具 + 三个用例 × 两配置，全部跑完并出对照表（串行，自带隔离残留修复）
bash evals/run_iteration4_pilot.sh "${TMPDIR:-/tmp}/knowlog-iter4"

# 单跑某个用例（先造目录，再跑两次，再评分）
WS="${TMPDIR:-/tmp}/knowlog-iter4"; D="$WS/iteration-4/eval-8-messy-legacy-docs-adopt"
bash evals/setup_iteration4.sh "$WS"
bash evals/run_case.sh "$D/with_skill"    with_skill
bash evals/run_case.sh "$D/without_skill" without_skill
python3 evals/grade_v4.py eval-8 "$D/with_skill"    "$D/with_skill/grading.json"
python3 evals/grade_v4.py eval-8 "$D/without_skill" "$D/without_skill/grading.json"
# 然后按 evals/review-rubric.md 填各自目录下的 manual_review.md
```

> iteration-1..3 的夹具/评分器仍在（`build_fixtures.sh` / `setup_runs.sh` / `grade.py` / `run_grading.sh`），保留是为了让历史结论可追溯；
> **新一轮请用 iteration-4 这一套**（夹具设计与隔离机制都不同，数字不可混用）。

## 6. 与"确定性自测"的分工

| | `evals/test_scripts.sh` | 本文件的真实评测 |
|---|---|---|
| 测什么 | 脚本行为：布局/幂等/采纳/召回/体检/安装/打包/防泄露 | **模型行为**：给真实任务，agent 会不会照这套体系做 |
| 依赖模型 | ❌ 纯确定性（93 项） | ✅ 需要跑 agent |
| 何时跑 | 每次提交（CI + pre-commit） | 发版前 / 大改提示词与工作流后 |
