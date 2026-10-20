# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## 0.4.0 — 2026-10-20　（破坏性变更：目录改名）

**项目内工具目录 `scripts/` → `.knowlog/`：归属明确，升级不再需要用户做选择**

- 📁 **改名**：knowlog 在项目里的工具目录从 `scripts/` 改为 **`.knowlog/`**（隐藏 + 一看就知道是谁的）。
  不再与项目自己的 `scripts/` 混淆（很多项目本来就有这个目录）；命令变为 `bash .knowlog/new-daily-log.sh …`，
  AGENTS 托管块会自动改写。
- 🔁 **自动迁移**：`init` / `bootstrap` 检测到旧布局（`scripts/` 里有 `bootstrap-docs.sh` + `assets/`）时，
  把 knowlog 名下的文件迁到 `.knowlog/`；**你自己的业务脚本原样留在 `scripts/`**（目录非空就不删）。
- ⬆️ **升级不需要用户选**：`.knowlog/VERSION` 与 skill 版本不一致 → **自动同步整套脚本**并打印清单；
  `--no-force-scripts` 仅作应急开关。（此前要用户自己判断加不加 `--force-scripts`，不该由用户承担。）
- 🔌 **兼容**：所有脚本、Claude/Codex 钩子薄壳、DSH 桥接都同时支持 `.knowlog/`（优先）与旧 `scripts/`。
- 🧪 自测 **118 项**（新增 5 条：版本变旧自动同步、旧布局迁移、业务脚本不被误迁、迁移后体检仍绿）。

## 0.3.7 — 2026-10-20

- 🐛 **`knowlog init --force-scripts` 被静默吞掉**：CLI 只透传了 `ends/project-name/knowledge-layout`，
  这个 flag 根本没到脚本 → 想用它升级项目内脚本时，"看起来跑了、其实什么都没换"。
  现在会透传；`npx knowlog init --force-scripts` 即可刷新**当前项目**的 `scripts/`（不动 docs/日志/索引）。
- 🧪 自测 **113 项**（新增 1 条：CLI `--force-scripts` 真的覆盖项目内脚本）。

## 0.3.6 — 2026-10-20

**召回不再「永远空转」：日志 → 沉淀 → 规则，全链路自动**

- 📝 **沉淀即挂召回规则**：`new-knowledge.sh` 从「来源日志（`--source`）里的代码标识符」自动提取，
  保守策略（只认 camelCase / snake_case / kebab-case，最多 3 条，排除路径与常用命令词）——不拿自然语言标题猜。
  `--keywords "a,b"` 显式指定（agent 更清楚写码时会出现哪个标识符）；`--no-keyword` 表示**明确不需要召回**，
  记入 `_exempt`，门禁不会因此变红。
- 🚦 **门禁拦住空转**：有知识文档但 0 条真实召回规则 → `check-docs-structure.sh --strict` **失败**
  （以前只是一条 info：项目可以永远空表、永远全绿、召回永远没意义）。
- 🧰 **存量补齐**：`reindex-knowledge.sh` 新增「召回复盘」，列出没有规则的知识文档与候选标识符；`--apply` 写盘。
- 🔧 **路径归一化**：`new-keyword.sh` 自动把 `knowledge/...` 补成 `docs/knowledge/...`，避免召回输出 `(not found)`。
- 📄 **收尾两问**：`new-daily-log.sh` 与 AGENTS 托管块明确"有可复用结论才沉淀，沉淀即挂规则"。
- 🧪 自测 **112 项**（新增 4 条覆盖整条链路：自动挂规则 / 召回命中可达 / 空转门禁 / 豁免）。

## 0.3.5 — 2026-10-20

- 🐛 **exFAT / 网络卷上 `install-skill --agent auto` 会在 dsh 步骤崩掉**（`UnicodeDecodeError: 0xb0`）：
  `install-recall.sh` 的整树拷贝把 `scripts/adapters/**/._xxx`（AppleDouble 影子文件，二进制）当 UTF-8 读。
  现在 `put_tree` 跳过 `._*`，`put_from` 也跳过影子文件、遇到非 UTF-8 源文件只记一条警告（不再让整脚本挂掉）。
- 🧪 自测 **108 项**（新增 3 条：往适配器目录塞假影子文件后整树拷贝仍成功、真文件就位、影子文件不被复制）。

## 0.3.4 — 2026-10-20

**修掉「在非 git 目录 / exFAT 卷上安装」暴露的 3 个真机 bug**（把 0.3.3 装到真实项目时踩出来的）

- 🐛 **最严重：非 git 目录下 `init` 会把体系写进 skill / npx 包自己，而不是你的项目**。
  根因：脚本在 `git rev-parse --show-toplevel` 失败后兜底到「脚本所在目录的上一级」——从 CLI 运行时
  那就是 npx 缓存里的包目录；项目里一行都收不到，**还打印"已建立"**（看起来像成功）。
  现在：CLI **永远显式传 `--root <当前目录>`**；脚本兜底也区分「项目内副本」与「skill/包本体」
  （后者用 `$PWD`，前者仍用项目根。识别标记：`SKILL.md` + `assets/`）。
- 🐛 **exFAT / 网络卷上的 `._xxx` 影子文件被当成文档**：macOS 会为每个文件生成 AppleDouble `._*`，
  日志/知识门禁把它们判成"文件名不合规范 / 索引未登记"→ 体系一建就红（实测 4 个错误）。
  现在日志、知识、reindex、adopt 四处枚举统一忽略 `._*` 与 `.DS_Store`。
- 🐛 **CLI 带值参数被吞**：`knowlog init --project-name "X"` 只把 `--project-name` 传下去、值丢了
  → 脚本静默空跑（退出码 2 但没提示价值）。现在带值参数连同值一起传；脚本侧缺值也会明确报错。
- 🧪 自测 **105 项**：新增「非 git 目录」（3）、「影子文件」（3）、「CLI 参数透传」（2）。

> 非 git 项目仍**建议 `git init`**：没有历史，日志里的"改了什么"就无法回溯；exFAT 上还请把 `._*` 加进 `.gitignore`。

## 0.3.3 — 2026-10-19

**从真实评测与真实故障里长出来的五处改进**（0.3.2 之后的增量，接口不变）

- 🐛 **自测可安全并发跑**（修掉那类「偶发红」的真根因，不是玄学）：
  ① 默认沙箱是固定路径且开头 `rm -rf` → 两个并发运行**互相删目录**；② 测试用 `/tmp/ndl.bak`、`/tmp/ag.bak` 做备份、
  `docs-doctor` 子检查日志写 `/tmp/docs-doctor-$i.log` → 并发**互相覆盖**。
  现在：默认每次运行用**独有**临时沙箱（退出即清理）、备份落进本次沙箱、日志带 PID。
- 📝 **「修完记一笔」提示**（来源：评测 eval-11 发现"带/不带 skill 两边都不给这次修复留记录"，人工量表 D1/D2 双双 0 分）：
  `adopt-docs.sh`（迁移历史文档后）、`reindex-knowledge.sh`（补齐索引后）、`docs-doctor.sh`（体检失败时）
  都会明确提示**记一笔**并给出可直接跑的命令 —— 把"我修了什么、为什么"变成收尾的一部分。
- 📊 **模型对照结论落盘**（`evals/RESULTS.md` §3c）：同一批 6 用例、只换模型重跑
  → **带 skill 两模型都 55/55（100%）**；基线 `deepseek-v4-flash` 63.6% vs `deepseek-v4-pro` 54.5%
  （差异全在 eval-12：pro 基线把知识放在仓库根 `knowledge/`、无索引/门禁）。
  **结论**：skill 把"靠模型自觉"换成"靠结构约束"——带 skill 时结果与模型无关。
- 🛠️ **评分器健壮性**（`grade_v4.py`）：夹具快照查找改为"离项目最近优先"，不再依赖评分输出路径
  （真踩过：复核时把 `grading.json` 写到 `/tmp`，导致所有"新增了什么"断言**集体假红**，eval-9 一度显示 0/7）。
- 💡 **升级路径提示**（`bootstrap-docs.sh`）：`--force-scripts` 无差异时明确提示"很可能是**已安装副本较旧**，
  先 `npx skills update knowlog`"——真机踩过：副本没更新时升级会**静默地无事发生**，让人误以为功能坏了。
- 🔧 **`verify.sh` 的失败/跳过分支不再崩**：那些分支的信息串里有"变量紧跟中文"的写法 → `set -u` 下当场 unbound，
  于是**出错时看不到诊断信息**（只在失败路径触发，所以平时全绿看不出来）。已修，并**新增 lint 守卫**：
  自测会扫描全仓 shell 脚本，禁止这种写法（本项目为此踩过 8 次）。
- 🧪 确定性自测 **97 项**（新增 3 条覆盖"记一笔"提示 + 1 条脚本卫生 lint）。

## 0.3.2 — 2026-10-19

**DSH 适配器可用 + 评测方法可信 + 安装模板修复**（0.3.1 之后的增量，接口不变）

### 🔌 DSH（DeepSeek Harness）适配器：从「静默失效」到真机可用

- 🎯 **找到官方每轮注入机制** = `agent/pre-step` 瀑布钩子（`dsh-agent` 的类型契约；同形先例：`dsh-time-context`、
  `dsh-agent-instructions`、`dsh-tool-skill`、第三方 `dsh-mnemon`）。原实现探测 `prompt/context.inject()` 的方向是错的。
- 🧭 **会话目录改为每轮解析**（`ctx.workingDirectory.ensure(agent, signal)`，第一方 `dsh-tool-skill` 同款）——
  常驻宿主（web profile 由 launchd 托管）cwd 常是 `/`，用进程 cwd 会让插件在**任何项目**里都失效
  （兜底顺序：显式绝对 root → workingDirectory → `agent.session.meta.cwd` → 进程 cwd）。
- 🛡️ **兼容性**：改用 `engines.dsh` 一锤定音，删除会被判定为不兼容的 optional peer。
  真事故：`@deepseek-ai/dsh-llm ^0.1.6-alpha.2` vs 运行时 `0.2.1-rc.2` → **整行插件被禁用且零报错**。
  回归守卫：`verify.sh` 新增 V6，直接调 DSH 自己的 `evaluatePluginCompatibility`。
- 📄 **安装模板 `name` 指「入口文件」**（`./bridge/lib/index.js`）：指目录会走 `ERR_UNSUPPORTED_DIR_IMPORT`
  （真机复现），插件静默加载失败。
- 🪵 **两处日志各司其职**：加载/卸载写 `~/.dsh/docs-recall.log`（加载那行**不需要调试开关**，每次启动一行）；
  每轮注入写 `<项目>/.dsh/docs-recall.log`；`log()` 自动 `mkdir -p`，不再静默丢日志。
- ✅ **真机闭环已验证**：`turn 1 step 1: 注入 338 chars … root=<项目目录>`（2026-10-19，DSH `0.2.1-rc.2` + `web` profile）。

### 🧪 评测方法（iteration-4）：第一次有了可信的对照

- 🧰 夹具**不再预置「已建好的体系」**（iteration-3 出现 0 差异的根因）；只给原始素材。
- 🔒 基线**机械隔离**：跑基线时临时移开已安装的 skill + `--disable-slash-commands`；移开失败即中止并把证据写进 `run_meta.json`。
- 📋 新增**人工量表**（D1 日志重点 / D2 知识可复用 / D3 尊重既有约定，各 0–2 分），`grade_v4.py` 自动生成评审骨架。
- 📈 用例扩到 **6 个**（新增：跨月补写+索引占位、索引漂移修复、单面项目 flat+关键词召回）：
  **结构断言 55:35（100% vs 63.6%）**、**人工量表 32:36（89% vs 69%）**。
- 🎯 结论：**增量在「可校验的约束与索引」，不在「帮你写字」**；体系一旦装好（eval-9 / eval-11）两者打平 —— 这是能力边界，不是缺陷。
- 🐛 工程修复：`setup_iteration4.sh` 幂等（`--force` / `--only <id>`）；召回断言同时接受"任务原话"形式
  （避免把"自建等价召回"的基线误判为没有召回）。

### 🧹 其它

- 全仓去掉个人绝对路径（本仓自带的 `check-secrets` 扫描器**拦下了作者自己的提交**——它该干的事）。
- `RELEASE.md`（维护者发版清单）、`evals/README.md`（评测说明书）。

## 0.3.1 — 2026-10-19

**安全防线 + 升级路径 + 首次分发后的文档校正**（0.3.0 之后的增量，接口不变）

- 🔒 **自带防泄露扫描**：`scripts/check-secrets.sh`（密钥形态 / 赋值型密钥 / 个人绝对路径 / 内网地址；支持 `--staged`），
  并接进仓库 `.githooks/pre-commit`（改动工具链时顺带跑确定性自测）。自测补 3 条扫描器用例（干净 / 抓到假密钥 / 不误报占位符）。
- ⬆️ **升级路径**：`bootstrap-docs.sh --force-scripts` 把项目内脚本整体升到上游版本；
  在**项目内那份**上跑会被识别为"同源自拷"并提示正确命令（必须从已安装的 skill 跑）。
- 🛡️ **托管块更安全**（三条都来自真实事故）：刷新/迁移前把旧块备份到 `<file>.block.bak`；
  旧标记 `DOCS-SYSTEM` 迁移**只规范化标记行、块内内容原样保留**；标记识别改**前缀/正则**（说明文字被改过也认得）；
  判"手工区是否已存在"时**先剥离托管块**。
- 🐛 **确定性自测 93 项**（0.3.0 时 84 项）。
- 📦 **发布到 npm**：`npx knowlog …` 从本版起可用（顺带占住包名，消除被抢注的风险）；不想用 npx 仍可
  `node <已安装 skill>/bin/knowlog.mjs …`。新增 `RELEASE.md`（发版清单）。
- 📄 **文档校正**：`knowlog add` 作为 `log` 的别名；`-h/--help` 不再透传给脚本；自测项数、升级命令、clone 后启用钩子的说明。
- 🧪 **新增 CI**：`.github/workflows/ci.yml`（push / PR 跑确定性自测 + 密钥扫描）。
- 📊 **评测结论落盘**：`evals/RESULTS.md`（三轮结论 + 复现命令 + 已知评测设计缺陷）。

### 事故记录（0.3.0 之后发现，均已修）

1. **托管块内容被通用模板覆盖**：迁移逻辑把旧标记块整体替换成渲染出的模板，**静默吃掉**消费方写进块内的项目规矩。
   → 迁移只换标记 + 刷新前备份。
2. **标记整行相等匹配**：手写块的标记行尾说明文字与常量不同 → 认不出块 → **追加第二份**（消费方 `AGENTS.md` 出现两份规则）。
   → 前缀/正则识别 + 写入时规范化标记行。
3. **手工区判据被托管块正文误命中**：托管块自己有一节 `🧭 领域上下文路由`，宽判据据此认为"手工区已存在"，导致手工区**永远建不出来**。
   → 判据先剥离托管块再匹配。

> 教训（已写进 `references/`）：**"工具维护区"与"人的规矩"必须物理分开**；识别边界要容错匹配；写入前必须备份 ——
> 只靠"约定别在块内写东西"挡不住人。


## 0.3.0 — 2026-10-17

**改名 + 独立仓库 + 接入 skill 管理器**（原 `docs-system`，代码与协议向后兼容）

- 🏷️ **改名**：`docs-system` → **`knowlog`（知录）**。托管块标记随之改为 `KNOWLOG:START/END`，
  **工具侧保留对旧标记 `DOCS-SYSTEM` 的兼容**（`bootstrap-docs.sh` 跑一次即自动迁移，用户块外内容不动）。
  安装元数据文件名同步改为 `.knowlog-install.json`（读取时兼容旧名）。
- 📦 **独立仓库**：从某使用方生产项目中提取为独立仓库，可独立发版与升级。
- 🧩 **接入 skills 管理器**：`npx skills add CR903/knowlog` 即可装到本机所有 agent；
  `install-skill.sh --mode skills` 把安装/升级交给它（写 lock、建软链、`skills update` 可升级）。
- 🖥️ **新增零依赖 CLI**：`bin/knowlog.mjs` —— `init|log(add)|doctor|adopt|reindex|knowledge|install-skill|package`（用已安装路径调用；当时文档误写成 `npx knowlog`，已在 Unreleased 更正）。
- 🧪 **自测 84 项**（新增：安装模式 link/copy/skills、自带打包、结构自检负例、索引落位回归、旧标记兼容）。
- 🐛 修复（均来自三轮真实评测）：
  - `index-util.py` 插入已有月份表格后**漏落盘**；补更早月份时落位成**升序**（应为年内降序）
  - `new-knowledge.sh` / `new-daily-log.sh` 用 `sed` 渲染，说明含 `/` 会写坏并留 0 字节文件 → 改 python 渲染 + 非空校验
  - `install-recall.sh` 在 `set -e` 下以 `[ ] && cmd` 结尾导致整脚本静默退出 → 全改 `if`
  - 结构自检把"手写等价规范"误判为缺托管块；把 `.mnemon/` 运行时目录误判为"体系外日志"
  - 门禁查不出"索引行仍是 `待回填`"（新增占位残留检测）；托管块只写 `docs-doctor` 时误报缺门禁命令
  - flat 项目的托管块仍写 `docs/knowledge/<端>/…`（会诱导建"伪端层"）→ 托管块/README 按布局分叉

## 0.2.0 — 2026-10-17

- 三层自检（结构规范 / 日志↔索引 / 知识↔索引）+ `docs-doctor.sh` 总入口
- 两种知识布局（flat / by-end，auto 按端数量自适应）
- `adopt-docs.sh`（采纳既有异构文档）、`reindex-knowledge.sh`（反向补齐知识索引）
- 各 agent 召回适配器矩阵（一个核心 `recall-core.py` + 薄适配器）
- `install-skill.sh`（本体安装：`--mode auto|link|copy`）、`package-skill.sh`（自带打包）
- 真机验证：Claude Code 钩子端到端、OpenCode v2 `instructions` 端到端

## 0.1.0 — 2026-10-17

- 从某使用方生产项目里沉淀出初版：日志/知识/领域三层记忆 + 索引 + 门禁 + 关键词召回 + `AGENTS.md` 托管块
