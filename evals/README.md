# evals — 怎么证明这套 skill 有用（也给下次改它的人留的说明书）

这里有两类东西，**别混着看**：

| 类别 | 文件 | 测什么 | 依赖模型 | 何时跑 |
|---|---|---|---|---|
| 确定性自测 | `test_scripts.sh` | 脚本行为：布局/幂等/采纳/召回/体检/安装/打包/防泄露（96 项） | ❌ 不需要 | 每次提交（CI + pre-commit） |
| 真实评测 | 下面那两套 | **模型行为**：给真实任务，agent 会不会照这套体系做 | ✅ 需要 | 发版前 / 大改提示词与工作流后 |

## 文件地图

| 文件 | 属于 | 说明 |
|---|---|---|
| `test_scripts.sh` | 通用 | 96 项确定性自测（最快的门禁） |
| `build_fixtures.sh` · `setup_runs.sh` · `setup_iteration2.sh` · `setup_iteration3.sh` · `grade.py` · `run_grading.sh` | **iteration-1..3（历史）** | 保留以便追溯老结论；**数字不可与新一套混用**（夹具设计与隔离机制都不同） |
| `build_fixtures_v4.sh` · `evals-v4.json` | **iteration-4（新）** | 夹具与用例定义（6 个用例：eval-7..12）；夹具只给原始素材，**不预置已建好的体系**（唯一例外 eval-9、eval-11，原因见 `evals-v4.json` 的 `design_notes`） |
| `setup_iteration4.sh` | 新 | 批量造运行目录（含 `PROMPT.md`、基线快照、元数据） |
| `run_case.sh` | 新 | 跑一次（含**机械隔离**：基线时把全局 skill 临时移开） |
| `grade_v4.py` | 新 | 客观断言 + 排除第三方钩子产物 + 生成人工评审骨架 |
| `review-rubric.md` | 新 | 人工量表（D1 日志重点 / D2 知识可复用 / D3 尊重既有约定） |
| `run_iteration4_pilot.sh` | 新 | 一把梭：六个用例全跑 + 出对照表（串行，自带残留修复） |
| `RESULTS.md` | — | **结论与已知干扰**（先读它） |

## 怎么跑（iteration-4）

> ✅ `setup_iteration4.sh` 默认**幂等**：已存在的用例目录保留不动（要重建加 `--force`，或 `--only eval-10` 只重建一个）。
> 只想补跑新用例时：先备份 `<WS>/iteration-4/<用例>`，跑完 setup 再还原，或只对目标用例跑下面三步。

```bash
WS="${TMPDIR:-/tmp}/knowlog-iter4"
bash evals/run_iteration4_pilot.sh "$WS"      # 全跑（含评分 + 对照表）
# 或单跑一个用例：
bash evals/setup_iteration4.sh "$WS"
D="$WS/iteration-4/eval-8-messy-legacy-docs-adopt"
bash evals/run_case.sh "$D/with_skill"    with_skill       # ①
bash evals/run_case.sh "$D/without_skill" without_skill    # ②（隔离）
python3 evals/grade_v4.py eval-8 "$D/with_skill"    "$D/with_skill/grading.json"
python3 evals/grade_v4.py eval-8 "$D/without_skill" "$D/without_skill/grading.json"
# 然后按 review-rubric.md 填 ./manual_review.md
```

六个用例（用例定义与"它到底测什么"见 `evals-v4.json` 的 `measures`）：

| id | 夹具 | 测什么 |
|---|---|---|
| eval-7 | `v4-fresh` | 全新项目从零搭结构 |
| eval-8 | `v4-messy` | 一团乱的历史文档：归位/合并 + 补索引 + 识别死链 |
| eval-9 | `v4-closeout` | 体系已就位时的收尾质量（**自带体系，已备案**） |
| eval-10 | `v4-backfill` | 跨月补写：按**任务日期**（而非今天）归月 + 索引行占位填实 |
| eval-11 | `v4-drift` | 索引漂移修复（用**项目自带门禁**定位并修好；**自带体系，已备案**，测"修"不测"搭"） |
| eval-12 | `v4-flat` | 单面项目 flat 布局（不造端层）+ 关键词召回**真能命中** |

## 三条铁律（都是踩出来的）

1. **夹具里不要放"已建好的体系"**。iteration-3 就是这么得到 0 差异的：两边都能照抄现成结构，等于没测。
   夹具只给**原始素材**（代码 + 散落/异构旧文档 + 任务描述），让 agent 自己决定怎么组织。
2. **基线必须机械隔离**。只要全局装着这个 skill，"不带 skill"就是**假基线**（模型照样能读到）。
   `run_case.sh` 的做法：临时把 `~/.claude/skills/knowlog` 等改名移开 + `--disable-slash-commands`；
   **移开失败就中止**，并把隔离证据写进 `run_meta.json` 的 `isolation` 字段。
3. **两把尺子都要用**：客观断言 + 人工量表。只用客观断言的话，一个"自建了轻量约定"的基线会被判 0 分，
   看起来像"什么都没做"，其实是"形状不同"——结论会失真。

## 已知干扰（跑之前扫一眼）

- **第三方钩子会往运行目录写文件**：例如本机另一个记忆工具（`.remember/`）。它可能恰好包含被断言搜索的关键词。
  `grade_v4.py` 已把 `.remember/`、`.trellis/`、`node_modules/` 与评测自产文件列入忽略清单；
  跑正式评测时最好把这类钩子临时关掉。
- **隔离会临时改动全局状态**：基线运行期间全局 skill 会变成 `.hidden-<pid>`（宿主看到的 skill 列表会短暂变化）。
  脚本用 `trap` 自动还原；**若被强杀**，手工修：`bash evals/run_iteration4_pilot.sh` 开头的 `restore_leftovers` 逻辑，
  或直接 `ls -d ~/.claude/skills/*.hidden-*` 看有没有残留。
- **串行跑**：基线要动全局 skill，所以 with/without 不能并行。
- **`setup_iteration4.sh` 默认幂等**（保留已有结果）；补跑新用例直接跑 pilot 即可，不会清掉旧评分。需要重建时用 `--force` / `--only <id>`。
- **断言只盯"能力有没有"，别盯"用了哪套 CLI 契约"**（扩评踩到）：eval-12 的基线自建了等价的 `scripts/knowledge-retrieve.sh`（实测能命中），
  若断言只认本 skill 的 `--root` 调用形式就会把它误判成"没有召回"。召回的判据同时接受任务里给用户的原话形式（在项目目录里跑 `bash scripts/knowledge-retrieve.sh "<probe>"`）。
- **夹具自带体系 = 基线也会用**（eval-9 / eval-11）：这类用例必然打平或接近打平，属**能力边界**而非缺陷；
  写这种用例要在 `evals-v4.json` 的 `design_notes` 备案，并在 `measures` 里写明"测的是修复/收尾能力，不是搭建能力"。
- **模型会变**：换模型（或换了 agent harness）必须重跑，数字只在同一配置下可比。

## 判定口径

- 客观断言只判**可判定**的事：文件集合关系、门禁退出码、链接可达性、关键内容是否丢失。
- "写得好不好"一律走 `review-rubric.md`，人工打分（0–2 × 3）。
- 报告结论时**两个数字都给**（结构断言 + 人工量表），别只报一个。
