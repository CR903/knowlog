# 安装、分发与升级

> 这份文件回答：「skill 怎么装？要不要自造一个 skill 管理器？能不能按 agent 分别装？跟 Trellis 的安装流程像不像？」

## 两层安装，别混（最常见的误解）

| 层 | 装什么 | 谁来做 | 范围 |
|----|--------|--------|------|
| ① **本体安装** | 让 agent *知道有这个 skill*（SKILL.md 能被发现） | `scripts/install-skill.sh` | 机器级 / 仓库级 |
| ② **项目内适配** | 让**某个具体项目**的召回与约束落到 agent 的钩子/插件/规则文件 | `.knowlog/install-recall.sh` + `bootstrap-docs.sh` | 项目级 |

只做①：agent 知道有这个 skill，但项目里没有 `.knowlog/`、没有 `AGENTS.md` 托管块 → 触发后它得从零搭（也能干，只是每次都要重新决定结构）。
只做②：项目结构齐全，但别的 agent/别的机器上的 agent 不知道有这套 skill 的来源与用法（不过 `AGENTS.md` 托管块本身已经把规则写进了项目，这层其实相当抗丢）。
**推荐**：① 装一次（每台机器），② 每个项目跑一次。

## ① 本体安装：各 agent 的真实位置（本机实测）

```bash
bash scripts/install-skill.sh --list                  # 看各 agent 的目标位置 + 已装版本
bash scripts/install-skill.sh --agent auto            # 本机检测到的 agent 全装（user scope）
bash scripts/install-skill.sh --agent claude,opencode
bash scripts/install-skill.sh --agent claude --scope project --root /path/to/repo
bash scripts/install-skill.sh --check                 # 已装版本 vs 当前版本（升级提示）
```

| agent | 形态 | user 位置 | project 位置 | 实测状态 |
|-------|------|-----------|--------------|----------|
| Claude Code | skill 目录 | `~/.claude/skills/knowlog/` | `https://github.com/CR903/knowlog/.claude/skills/knowlog/` | ✅ 目录结构与本机既有 skill 一致 |
| OpenCode | skill 目录（**格式与 Claude 相同**） | `~/.config/opencode/skills/knowlog/` | `https://github.com/CR903/knowlog/.opencode/skills/knowlog/` | ✅ 本机 `~/.config/opencode/skills/` 下已有同类 skill |
| Codex | **没有 skill 目录** | — | 项目级：`AGENTS.md` 托管块 + `.codex/hooks.json`（走 ②/`install-recall.sh`） | ⚠️ Codex 的插件是 marketplace 制（`codex plugin add`），本脚本不假装能装；子代理定义在 `~/.codex/agents/*.toml` |
| Cursor | 规则文件 | — | `https://github.com/CR903/knowlog/.cursor/rules/knowlog.mdc` | ✅ 文件级（Cursor 无 skill 概念） |
| Gemini CLI | 项目上下文文件 | — | `https://github.com/CR903/knowlog/GEMINI.md` 指针块 | ✅ 文件级 |
| GitHub Copilot | 指令文件 | — | `https://github.com/CR903/knowlog/.github/copilot-instructions.md` 指针块 | ✅ 文件级 |
| DSH | 插件（pnpm 包 + cordis patch 层） | profile 的 `node_modules` + `cordis.patch.yml` | `.dsh/docs-recall.patch.yml` + 桥接包骨架 | ⚠️ patch 格式已核实，钩子注册需按其 API 补一行 |
| 其它 agent（Aider/Cline/Roo/Qwen/iFlow/Antigravity/Kilo/Windsurf/Devin/Amp…） | 无 skill 机制 | — | `https://github.com/CR903/knowlog/AGENTS.md` 托管块 + `https://github.com/CR903/knowlog/scripts/` | ✅ 最通用形态（与有钩子的 agent 同源） |

安装产物：`SKILL.md` + `VERSION` + `scripts/` + `adapters/` + `assets/` + `references/` + `.knowlog-install.json`（记录版本/来源/时间，供 `--check` 对比）。
**不装** `evals/`（那是开发 skill 用的，装进去只会让 agent 误会项目里有测试）。

## 安装模式：共享副本 + 软链，还是每 agent 各存一份？

这台机器（以及多数"多 agent 并存"的机器）已经有既成事实的**共享 skill 仓库**：

```
~/.agents/skills/<name>/            # 权威副本（129 个 skill 的实体在这）
~/.agents/.skill-lock.json          # 来源/哈希/时间（谁装的、装自哪里）
~/.claude/skills/<name>          -> ../../.agents/skills/<name>      # 软链
~/.config/opencode/skills/<name> -> /Users/…/.agents/skills/<name>   # 软链
```

`install-skill.sh` 默认 `--mode auto` 就按这个事实走：

| 模式 | 行为 | 什么时候用 |
|------|------|-----------|
| `auto`（默认） | user 范围 + 存在 `~/.agents/skills` → **link**；否则 → **copy** | 大多数情况 |
| `link` | 权威副本装到 `~/.agents/skills/<name>`，各 agent 只放**软链** | 一台机器多个 agent；改一处、全部生效 |
| `copy` | 每个 agent 各存一份真目录 | 没有共享仓库的机器；或希望 agent 目录可独立拷贝/提交 |

**project 范围默认 `copy`** —— 项目里的 `.claude/skills/` 通常要被提交，软链指向个人 home 在别人机器上会坏。

```bash
bash scripts/install-skill.sh --list                      # 看检测结果 + 默认会用哪种模式
bash scripts/install-skill.sh --agent auto                # 默认（推荐）
bash scripts/install-skill.sh --agent claude,opencode --mode link
bash scripts/install-skill.sh --agent claude --scope project    # 装进仓库（真复制）
```

软链是否会被 agent 正常发现？——**本机既有 129 个 skill 就是这么铺的**，且本会话的可用 skill 列表里就有这些软链条目，属于已验证事实。

## 打包（分发单元）

```bash
bash scripts/package-skill.sh                 # → ~/.agents/skills/.packages/knowlog-v<版本>.skill
bash scripts/package-skill.sh --out ./dist    # 自定义输出目录
```

自带打包（纯 `zip`），**不依赖任何第三方打包工具**。内容与安装一致：`SKILL.md` + `VERSION` + `package.json` +
`bin/` + `scripts/` + `adapters/` + `assets/` + `references/`（不含 `evals/`）。

> 历史坑：早期借用某个第三方打包器时，产物会落到那个工具自己的目录下（因为它把包写在自己所在目录的父级），
> 位置不可控且多一层依赖 —— 所以改成自带打包。

## 怎么分发给别人？（三种方式，按"傻瓜程度"排序）

**先说结论：首选「一个 git 仓库 + 一行 `npx skills add`」，不是 npm 发包、也不是让人手动解压。**

| 方式 | 用户要做的 | 跨 agent | 可升级 | 适合 |
|------|-----------|----------|--------|------|
| **① `npx skills add https://github.com/CR903/knowlog`**（推荐） | 一条命令 | ✅ 自动装到 40+ agent 的 skill 目录 + 建软链 | ✅ `npx skills update`（按 `skillFolderHash` 比对） | 绝大多数人 |
| ② `npx knowlog init`（自带 CLI，已发 npm） | 一条命令 | ⚠️ 装"本项目"的文档体系；agent 侧要再 `install-skill --agent auto` | 重跑即升级 | 只想给"某个项目"搭体系、不关心全局 skill |
| ③ 给 `.skill` 包 / 目录（离线） | 解压 + `bash scripts/install-skill.sh --agent auto` | ✅ 但要用户跑脚本 | 手动重新解压 | 内网、无 npm、无外网 |

### 为什么首选 ①（而不是 npm 发包）

- **skill 的本质是文件**，装的位置是各 agent 的 skills 目录；npm 的强项（依赖解析、语义化版本范围）在这里几乎用不上 —— 本 skill 零依赖。
- 这台机器上**已经有一个 skill 管理器**在管 `~/.agents/skills/`（见下一节），`skills add` 就是它的入口；
  实测：`npx -y skills@latest add <本地路径> -g -y` → `✓ knowlog (copied) → ~/.agents/skills/knowlog`，
  并写进 `~/.agents/.skill-lock.json`（`sourceType: "local"` + `skillFolderHash`），`skills list` 可见。
- 用户不需要 npm 账号、不需要我们维护发布流程；**一个公开 git 仓库就够**（`skills add` 支持 `owner/repo`、
  GitHub URL、Notion 页面 URL、本地路径）。
- npm 在这里有两个身份：**安装器**（`npx skills@latest`）与 **CLI 的分发**（`npx knowlog`，0.3.1 起发布，
  顺带把包名占了、消除被抢注的风险）。skill **本体**仍然只走 git 仓库 —— 因为 skill 的本质是文件。

### 怎么做到"傻瓜式"（本次已实现的细节）

1. **一条命令搞定多半事**：`npx knowlog init --agent auto`
   = 建结构 + 装脚本 + 写 `AGENTS.md` 托管块 + 装各 agent 召回适配器 + 自检（`--dry-run` 可先看计划）。
2. **不改用户的配置除非明说**：`init` 不带 `--agent` 时只搭项目结构，不碰 `.claude/settings.json`、`opencode.json` 等。
3. **零依赖 + 零构建**：CLI 是纯 Node 标准库（`bin/knowlog.mjs`），payload 是 bash + python3 脚本 ——
   不装任何依赖即可跑；项目内那份脚本也让"不装 CLI 的人"照样能用。
4. **幂等 + 不毁已有内容**：重复跑只刷新脚本/资产/托管块；块外手工内容（领域路由表）只创建一次、永不改写。
5. **先看后做**：`--dry-run`（init）、默认 dry-run（adopt）、`--fix-hint`（doctor）—— 降低"不敢跑"的心理成本。
6. **README 里给三条命令**（建/记/体检），别给十个参数：
   ```bash
   npx knowlog init --agent auto     # 搭好
   npx knowlog add <slug>            # 收尾记一笔（= log）
   npx knowlog doctor                # 体检
   ```

## 需要自造一个 skill 管理器吗？

**不需要 —— 而且这台机器上已经有一个了，它叫 [`skills`](https://github.com/vercel-labs/skills)（Vercel Labs）**：

- 它维护 `~/.agents/skills/`（本机 129 个 skill 的实体）+ `~/.agents/.skill-lock.json`
  （v3：`source` / `sourceType` / `sourceUrl` / `skillFolderHash` / `installedAt` / `updatedAt`；
  来源含 `github/awesome-copilot`、`open.feishu.cn/.well-known/skills/...` 与本地路径）
- 安装者形如 `installer.ts`，就是 **symlink / copy 到各 agent 目录** → 与我们的 `--mode link` 完全同构
- 命令：`skills add <package>` / `list` / `find` / `update` / `remove` / `use`
- 本机实测：`npx -y skills@latest add <本 skill 路径> -g -y` → `✓ knowlog (copied)`，写入 lock，`skills list` 可见

所以正确姿态是**接入它**（`--mode link`；或干脆让用户用 `skills add` 装），而不是自造第二套。
我们唯一补充的是**项目级**那层（`.claude/hooks`、`opencode.json`、`.cursor/rules`… 与项目内 `.knowlog/`），
那是 `skills` CLI 不负责的部分。

同时补上两个"管理器该有"的东西 —— 都在脚本里：

1. **版本与升级**：`VERSION` 文件 + 安装时写 `.knowlog-install.json`；`install-skill.sh --check` 对比已装/当前版本并给升级命令。
2. **幂等 + 不毁用户内容**：安装与 `bootstrap-docs.sh` 都可重复执行；`AGENTS.md` 只在 `KNOWLOG:START/END` 之间替换，用户手编的「领域路由表」在块外、**只创建一次永不改写**。
   → 升级 = 重跑 `bootstrap-docs.sh`（刷新脚本/资产/托管块，跳过你改过的东西）。

不做的部分（也是**故意**不做的）：不引入远端 registry、不做全局 lock 文件、不接管"哪个项目用了哪个版本"的账本 —— 这些只有在"多团队 × 多版本并存"时才值钱，而现在的分发单元（一个 zip 包 + 一个目录）已经够用。

## 跟 Trellis 的安装流程像吗？

**机制像、规模不像，且不需要复制它的整套体系。**

| 维度 | Trellis | knowlog |
|------|---------|-------------|
| 分发 | CLI（`trellis init` / `trellis update`）+ 模板渲染 | 一个 `.skill` 包 + 目录复制（`install-skill.sh`） |
| 平台矩阵 | 为每个平台生成原生文件（`.claude/`、`.codex/`、`.opencode/`、`.cursor/`…） | 同样按 agent 生成原生文件（`install-skill.sh` 表格 + `install-recall.sh` 的适配器） |
| 升级方式 | `trellis update` 做**块级托管替换** | `bootstrap-docs.sh` 重跑 + `KNOWLOG:START/END` 托管块（同样的思路） |
| 项目状态 | `.trellis/`（任务/spec/journal/config）+ `trellis` CLI 运行时 | `docs/`（日志/知识/领域）+ `.knowlog/`（体检/建日志/召回），**无守护进程、无运行时** |
| 依赖 | Node CLI + config.yaml + 平台 hook 注入 | 只要 bash + python3；hook 是可选增强 |

一句话：**Trellis 是"工作流框架 + 平台渲染器"，本 skill 是"文档体系脚手架 + 平台适配器"**。
两者的托管块/幂等/平台矩阵思路可以直接照搬（我就是照搬的），但没必要为了装文档体系引入一整套 CLI 与配置。
如果这个仓库本来就在用 Trellis，两者**不冲突**：`.trellis/` 管任务，`docs/` 管沉淀；本 skill 负责后者，且不会碰前者。

## 升级与迁移注意

- 升级后会新增脚本：跑一次 `bootstrap-docs.sh` 就会补齐；**已有且内容不同的脚本默认保留你的版本**并打印提示。
- 想把项目内那套整体升到上游版本（确认没自己改过）：

  ```bash
  # 从"已安装的 skill"跑，而不是项目内那份（后者等于自拷，不会有变化）
  bash ~/.agents/skills/knowlog/scripts/bootstrap-docs.sh --root . --force-scripts
  # 或用 CLI：npx knowlog init --agent auto   （CLI 随 npm 包更新；也可用已安装 skill 里的那份）
  ```
- 布局切换（flat ⇄ by-end）：见 `maintenance.md §2.5`，老文档不会自动搬家。
- 卸载：删掉安装目录（`~/.claude/skills/knowlog/` 等）即可；项目内的体系是**你的资产**，不随 skill 删除而消失（这是刻意的：skill 是工具，文档体系是项目的一部分）。
