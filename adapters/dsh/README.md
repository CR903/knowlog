# DSH（DeepSeek Harness）适配器

## DSH 的机制（已核实）

- **插件 = npm 包 + patch 层**，装在 profile 里：
  ```bash
  dsh plugin --profile web add <pkg>          # pnpm 装包
  dsh --profile web --dump-config | grep <id> # 验证 patch/graph 是否生效
  ```
- profile 的层结构：`$DSH_HOME/profiles/<profile>/cordis.patch.yml`（用户层，最后应用）
- patch 层是**顶层 YAML 数组**，条目可 `insert`（插入插件行）/ 按 `id` 覆盖 config / disable：

  ```yaml
  # 摘自 dsh-context 自带 patch（真实样例）
  - insert:
      - id: dsh-context
        name: dsh-context
  ```

- 也可以用 `dsh --patch <path>` 临时叠加一层（不改用户配置），适合"先验证再固化"。

## 两种落地方式

### 方式 A（推荐，零新代码）：把本仓文档挂进 DSH 的上下文

DSH 的上下文/系统提示由它自己的插件（如 `dsh-context`、`@deepseek-ai/dsh-system-prompt`）构成。
本仓的**静态约束**（日志/知识/领域/门禁）已经写在根 `AGENTS.md` 的 `DOCS-SYSTEM` 托管块里，
被任何 agent 读取；DSH 侧只要保证工作目录是本仓、且按 `AGENTS.md` 行事即可。

**关键词召回**用命令行兜底（与其它 agent 完全同源）：

```bash
bash scripts/knowledge-retrieve.sh "<prompt 或代码片段>"
```

### 方式 B：做一个真正的 DSH 召回桥接插件

`bridge/` 是这个桥接包的骨架（package.json + `dsh.bundle.patch` + cordis patch + `lib/index.js`）。
它做的事和 Claude/Codex 的钩子一样：**每轮把 `scripts/recall-core.py` 的输出注入上下文**。

### 已验证 vs 待确认（别混淆）

| 项 | 状态 |
|----|------|
| patch 层写法 `- insert: [{id, name}]` | ✅ 已核实：抄自 `dsh-context/cordis.patch.yml`，且**实测** `dsh --profile web --patch .dsh/docs-recall.patch.yml --dump-config` 里出现 `- id: docs-recall`（exit 0） |
| Cordis 插件惯用法（`ctx.effect` / `ctx.get(name,false)` / `ctx.inject`） | ✅ 已核实：来自 `dsh-context/lib/index.js` 的真实实现 |
| DSH 原生把 skill 当一等上下文类别 | ✅ 已核实：`dsh-context/lib/index.d.ts` 的 `Category = 'user' \| 'inject' \| 'skill' \| …`，`<available_skills>` 与 skill 加载结果都算 `skill` 类 |
| 每轮注入的官方调用名 | ⚠️ 待确认：`bridge/lib/index.js` 里唯一一处 `TODO_INJECT`（只探测 + 记录，不误改宿主；未识别时静默退出，用命令行兜底） |

**先说结论：在 DSH 上让 agent 认识 knowlog 不需要插件** —— DSH 原生吃 skill，
`npx skills add <本 skill 的仓库或路径>` 装进去即可（本机已有先例：129 个 skill 都是这么装的）。
插件只解决「每轮自动召回」，属加分项；不装也能用（`AGENTS.md` 托管块 + `knowledge-retrieve.sh` 兜底）。

```bash
# 在 bridge/ 目录
pnpm install                     # 或 npm/yarn
dsh plugin --profile web add "$PWD"      # 把本地包加进 profile
# 或者临时验证：
dsh --profile web --patch cordis.patch.yml --dump-config | grep docs-recall
```

## 三档可靠性排序（选型建议）

| 方案 | 是否自动 | 可靠性 | 适合谁 |
|------|----------|--------|--------|
| `AGENTS.md` 托管块（静态约束） | 每轮必读 | 高（各 agent 通用） | 所有人，默认必须 |
| 命令行召回 `knowledge-retrieve.sh` | 手动/由 agent 按规范调用 | 高（同一份 core） | 所有 agent 的兜底 |
| bridge 插件（本目录） | 自动（每轮注入命中） | 中（依赖 DSH 插件 API 版本） | 想吃到"自动召回"的 DSH 用户 |
