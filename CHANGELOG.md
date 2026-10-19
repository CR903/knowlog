# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## Unreleased

**安全防线 + 升级路径 + 首次分发后的文档校正**（0.3.0 之后的增量，接口不变）

- 🔒 **自带防泄露扫描**：`scripts/check-secrets.sh`（密钥形态 / 赋值型密钥 / 个人绝对路径 / 内网地址；支持 `--staged`），
  并接进仓库 `.githooks/pre-commit`（改动工具链时顺带跑确定性自测）。自测补 3 条扫描器用例（干净 / 抓到假密钥 / 不误报占位符）。
- ⬆️ **升级路径**：`bootstrap-docs.sh --force-scripts` 把项目内脚本整体升到上游版本；
  在**项目内那份**上跑会被识别为"同源自拷"并提示正确命令（必须从已安装的 skill 跑）。
- 🛡️ **托管块更安全**（三条都来自真实事故）：刷新/迁移前把旧块备份到 `<file>.block.bak`；
  旧标记 `DOCS-SYSTEM` 迁移**只规范化标记行、块内内容原样保留**；标记识别改**前缀/正则**（说明文字被改过也认得）；
  判"手工区是否已存在"时**先剥离托管块**。
- 🐛 **确定性自测 93 项**（0.3.0 时 84 项）。
- 📄 **文档校正**：CLI 的真实调用方式（**未发布 npm → 不要用 `npx knowlog`**，改用 `node <已安装 skill>/bin/knowlog.mjs …`）；
  `knowlog add` 作为 `log` 的别名；`-h/--help` 不再透传给脚本；自测项数、升级命令、clone 后启用钩子的说明。
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
