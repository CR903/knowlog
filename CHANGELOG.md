# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## 0.3.0 — 2026-10-17

**改名 + 独立仓库 + 接入 skill 管理器**（原 `docs-system`，代码与协议向后兼容）

- 🏷️ **改名**：`docs-system` → **`knowlog`（知录）**。托管块标记随之改为 `KNOWLOG:START/END`，
  **工具侧保留对旧标记 `DOCS-SYSTEM` 的兼容**（`bootstrap-docs.sh` 跑一次即自动迁移，用户块外内容不动）。
  安装元数据文件名同步改为 `.knowlog-install.json`（读取时兼容旧名）。
- 📦 **独立仓库**：从某使用方生产项目中提取为独立仓库，可独立发版与升级。
- 🧩 **接入 skills 管理器**：`npx skills add CR903/knowlog` 即可装到本机所有 agent；
  `install-skill.sh --mode skills` 把安装/升级交给它（写 lock、建软链、`skills update` 可升级）。
- 🖥️ **新增零依赖 CLI**：`bin/knowlog.mjs` —— `npx knowlog init|add|doctor|adopt|reindex|knowledge|install-skill|package`。
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
