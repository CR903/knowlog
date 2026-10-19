# knowlog（知录）

> 给任何项目建立并维护一套**会自我校验的文档体系**：任务日志 + 结构化知识库 + 领域上下文 + 索引 + 门禁 + 关键词召回。
> 目标很朴素：**agent 的上下文会丢，文件不会**——让下个会话（人或 AI）能靠文件重建上下文，而不是翻聊天记录。

**知录 = 知（知识） + 录（记录）**：把项目发生过的事记下来（日志），把反复用得到的结论沉淀下来（知识），
用索引与门禁保证它们**找得到、不会漂移**，并让各 agent 在正确的时刻自动想起它们。

```
┌── 记忆三层 ──────────────┐   ┌── 索引与门禁 ────────────┐   ┌── 召回 ──────────────┐
│ daily/<YYYY-MM>/  时序记忆 │   │ docs/index.md 日志索引    │   │ 关键词 → 提示+文档路径 │
│ knowledge/        结构化   │   │ knowledge/index.md 知识索引│   │ （非全量，按需读）    │
│ domain context/   业务规则 │   │ docs-doctor.sh 三合一门禁 │   │ Claude/Codex/OpenCode… │
└───────────────────────────┘   └───────────────────────────┘   └───────────────────────┘
```

## 安装（推荐：一条命令）

```bash
npx skills add CR903/knowlog        # 装到本机所有已检测的 agent（Claude Code / OpenCode / Codex / Cursor / …）
```

没有 `skills` CLI 时，也可以直接：

```bash
git clone https://github.com/CR903/knowlog ~/.local/share/knowlog && bash ~/.local/share/knowlog/scripts/install-skill.sh --agent auto
# 或离线：拿到 knowlog-vX.Y.Z.skill，解压后跑同一个 install-skill.sh
```

装完新开一个会话，直接说：**「帮我把这个项目的文档体系建起来」**（skill 会按描述自动触发）。

## 给某个项目落地（三条命令）

```bash
K=~/.agents/skills/knowlog        # `skills add` 的落点（也可用你机器上的实际路径）
node $K/bin/knowlog.mjs init --agent auto   # ① 建结构 + 装脚本 + 写 AGENTS.md 托管块 + 装各 agent 召回 + 自检
node $K/bin/knowlog.mjs add <slug>          # ② 收尾记一笔（自动落 <月份> 目录 + 在索引里插好行；add 是 log 的别名）
node $K/bin/knowlog.mjs doctor              # ③ 体检：结构规范 + 日志↔索引 + 知识↔索引（--fix-hint 给修复命令）
```

> ⚠️ **别用 `npx knowlog`**：本 skill 只走 `skills add` 分发、**尚未发布到 npm**，`npx knowlog` 会 `404`
> （而且万一 `knowlog` 这个包名被别人抢注，`npx knowlog` 就会执行陌生代码）。想少打字就加个别名：
> `alias knowlog='node ~/.agents/skills/knowlog/bin/knowlog.mjs'`。

> 更省事的日常姿势：`init` 之后项目里就有全套 `scripts/`，直接用它 —— `bash scripts/new-daily-log.sh <slug>`、`bash scripts/docs-doctor.sh`。

**不指定 `--agent` 时不会碰你的 agent 配置**（`.claude/settings.json`、`opencode.json`…）；要装召回再说一句。

## 它到底解决什么

| 失败模式 | 后果 | knowlog 的机制 |
|---|---|---|
| 上下文丢了，只能翻聊天记录 | 每次重开会话都要重新摸索 | **日志**：一任务一篇，路径是日期的纯函数，索引可查 |
| 同一个坑踩第二、第三次 | 重复浪费，每次都像第一次 | **知识库**：可复用结论 + 关键词召回（命中只给提示+路径） |
| agent 不懂业务却写得很像真的 | 代码能跑、测试能过，业务是错的 | **领域上下文**：按 `AGENTS.md` 路由表全量加载 |
| 约定靠自觉，慢慢就烂了 | 索引漂移、日志散落、路径不一致 | **门禁**：`docs-doctor.sh --strict` 非零退出，可接 CI / pre-commit |

## 关键不变量（也是它与"随便建个 docs 目录"的区别）

1. **路径是日期的纯函数**：`docs/daily/<YYYY-MM>/YYYY-MM-DD_<slug>.md`，月份取**日志日期所在月** → 没有"事后归档"，永不回改链接
2. **三处月份一致**：目录月 == 文件名月 == `index.md` 所在表格月
3. **索引双向一致**：每篇日志有且仅有一行；每条链接可达（`check-daily-index.sh`）
4. **知识登记到索引**：按端两级（by-end）或单级（flat），布局自动适配（`check-knowledge-index.sh`）
5. **召回非全量**：命中只给"提示 + 文档路径"，上限 4 条（~800 token），确认相关再全量读
6. **约束写进 `AGENTS.md` 托管块**：块内脚本幂等维护；块外的手工内容（领域路由表）**只创建一次、永不改写**

## 目录结构（skill 本体）

```
knowlog/
├── SKILL.md              # 给 agent 的三条工作流（搭建 / 收尾记日志 / 体检修复）
├── VERSION
├── bin/knowlog.mjs       # 零依赖 CLI（node bin/knowlog.mjs …；未发布 npm），只是转发下面的脚本
├── scripts/              # 真正干活的全套脚本（bash + python3，项目里也会各存一份）
│   ├── bootstrap-docs.sh       # 搭/补建体系（幂等；flat/by-end 自适应；自包含 assets）
│   ├── new-daily-log.sh        # 记日志（落月份目录 + 插索引行）
│   ├── new-knowledge.sh        # 沉淀知识（两级索引自动登记；--flat 支持单面项目）
│   ├── docs-doctor.sh          # 体检总入口（结构 + 两项索引）
│   ├── check-docs-structure.sh # 结构规范自检
│   ├── check-daily-index.sh    # 日志 ↔ 索引
│   ├── check-knowledge-index.sh# 知识 ↔ 索引
│   ├── adopt-docs.sh           # 采纳既有异构文档（默认 dry-run）
│   ├── reindex-knowledge.sh    # 从磁盘反向补齐知识索引
│   ├── new-keyword.sh / knowledge-retrieve.sh / recall-core.py   # 召回（唯一实现 + 入口）
│   ├── install-recall.sh       # 把召回装到各 agent（钩子/插件/规则文件）
│   ├── install-skill.sh        # 把 skill 本体装到各 agent（--mode link|copy|skills）
│   └── package-skill.sh        # 打包 .skill（离线分发）
├── adapters/             # 各 agent 的薄适配器 + 为什么有的只能静态注入
├── assets/               # 模板（索引/README/日志/知识/领域/AGENTS 托管块）
├── references/           # structure / memory-and-constraints / maintenance / installation
└── evals/                # 自带测试：93 项确定性自测 + 三轮真实评测的夹具与评分器（结论见 evals/RESULTS.md）
```

## 支持的 agent

| agent | 机制 | 状态 |
|---|---|---|
| Claude Code | `.claude/settings.json` 的 `UserPromptSubmit` 钩子 | ✅ 端到端实测（模型能复述注入内容） |
| OpenCode v2 | 项目 `opencode.json` 的 `instructions` | ✅ 端到端实测 |
| Codex | `.codex/hooks.json` 的 `UserPromptSubmit` | ⚠️ 钩子本体可用；**需人工一次性信任**才会执行 |
| OpenCode v1 | `.opencode/plugins/*.ts` 的 `chat.message` | ⚠️ v2 上不触发（版本所限），默认不装 |
| Cursor / Gemini / Copilot | `.cursor/rules`、`GEMINI.md`、`.github/copilot-instructions.md` | ✅ 指针文件（不复制规则） |
| DSH | cordis patch 层 + 桥接包 | ⚠️ patch 已实测被接受；每轮注入那一行待按宿主 API 确认 |
| 其它（Aider/Cline/Roo/Qwen/iFlow/Kilo/Windsurf/Devin/Amp…） | `AGENTS.md` 托管块 + 命令行召回 | ✅ 与有钩子的 agent 同源（都调 `recall-core.py`） |

**取舍**：宁可"静态规则 + 命令行召回"，也不装"看起来能自动、实际不触发"的适配器——后者会让人以为有保护，实则没有。

## 升级 / 卸载

```bash
npx skills update knowlog        # 用管理器升级（按 skillFolderHash 比对）
npx skills remove knowlog        # 卸载
```

项目里的 `docs/` 与 `scripts/` 是**你的资产**，不随 skill 卸载而消失（这是刻意的：skill 是工具，文档体系是项目的一部分）。
重新升级项目内那套：`bash scripts/bootstrap-docs.sh`（幂等，只刷新脚本/资产/托管块，不覆盖你手改的内容）；
要**整体升到上游脚本版本**：`bash ~/.agents/skills/knowlog/scripts/bootstrap-docs.sh --root . --force-scripts`（必须从已安装的 skill 跑）。

## 安全 / 防泄露

本仓库自带两道防线（`.githooks/pre-commit`）。**clone 之后跑一次把它启用**（git 不会随仓库携带 hook 配置）：

```bash
git config core.hooksPath .githooks       # 每个人 clone 后各跑一次
bash scripts/check-secrets.sh             # 扫全仓：密钥/令牌/私钥 + 个人绝对路径 / 内网地址
bash scripts/check-secrets.sh --staged    # 只扫暂存区（pre-commit 用）
```

命中即非零退出；误报可 `SKIP_SECRET_SCAN=1 git commit …` 临时跳过。
**给 fork / 协作者**：把这条钩子留着 —— 泄露一旦进了 git 历史，收回成本极高（rewrite history + 通知所有协作者 + 轮换凭据）。

## 开发

```bash
bash evals/test_scripts.sh       # 93 项确定性自测（布局/幂等/adopt/召回/体检/安装/打包/边界/防泄露）
# 推送到 GitHub 后，.github/workflows/ci.yml 会自动跑同一套自测 + 密钥扫描
bash scripts/package-skill.sh    # 打包 .skill
```

## License

MIT
