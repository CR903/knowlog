# 维护配方

> 日常高频操作的"怎么做"。每条都尽量给可复制命令。

## 1. 加一个「端」（新子仓 / 新平台）

```bash
# 建目录 + 骨架（幂等，不会动已有文件）
bash .knowlog/bootstrap-docs.sh --ends "backend frontend mobile app" --project-name "<项目名>"
```

`bootstrap-docs.sh` 会自动为每个端建 `README.md` / `index.md` / 四个分类目录，并把根索引的端表格与 section 补齐。
**注意**：已有的端文件不会被覆盖，所以加端是安全的。

判断要不要加端：知识明显按不同技术栈/仓分开复用（如 Go 后端 + Angular 前端）→ 加端；
只是同一栈里的分层（如 api/service/repo）→ 不加端，用知识分类表达。

## 2. 加一个知识分类

1. 建目录：`mkdir -p docs/knowledge/<端>/<新分类>`
2. 在分端 `index.md` 补一节：`## <新分类>` + 表头 `| 文档 | 说明 | 来源 |`
3. 在 `docs/knowledge/README.md` 的分类表补一行
4. 若希望 `new-knowledge.sh` 接受它，需要改 `new-knowledge.sh` 里的分类白名单（`architecture|guides|troubleshooting|best-practices`）

**先别急着加分类**：四个分类覆盖了绝大多数情况。分类越多，写文档时越犹豫，最后就没人写了。

## 2.5 切换知识库布局（flat ⇄ by-end）

```bash
# 单面 → 多端（例如后来加了前端/移动端）
bash .knowlog/bootstrap-docs.sh --knowledge-layout by-end --ends "backend frontend"
# 多端 → 单面（知识其实通用，分层反而让人犹豫）
bash .knowlog/bootstrap-docs.sh --knowledge-layout flat
```

两个**不会自动做**的事，切换后要手工收口：

1. **老文档不会自动搬家**：by-end 后旧文档（在分类目录下）不会自动进 `<端>/<分类>/`。
   做法：`git mv docs/knowledge/<分类>/x.md docs/knowledge/<端>/<分类>/x.md`，再用
   `bash .knowlog/new-knowledge.sh <端> <分类> <name> "<说明>"` 重新登记（或手工改索引两处）。
2. **索引会多出/残留 section**：切换后跑 `bash .knowlog/check-knowledge-index.sh --strict --fix-hint`，
   按提示把行搬到正确 section；残留的空 section 手工删掉即可（脚本不猜你的意图，不会自动删）。

## 2.6 让召回覆盖到各 agent

```bash
bash .knowlog/install-recall.sh --list        # 检测本机 agent
bash .knowlog/install-recall.sh --agent auto --verify
```

- **Claude Code**：钩子装好即生效（实测：`claude -p` 能让模型复述注入内容）
- **Codex**：钩子文件装好后，**需要人在交互式会话里一次性批准**（写入 `~/.codex/config.toml` 的
  `hooks.state."<项目>/.codex/hooks.json:user_prompt_submit:0:0".trusted_hash`）。
  未批准时钩子静默不跑（实测现象："hook: UserPromptSubmit Completed" 有、但模型看不到注入内容）。
  **不要让脚本替你写信任** —— 那等于绕过 host 的安全模型；信任应由人授予。
- **OpenCode v2**：用项目 `opencode.json` 的 `instructions`（实测生效），不是插件钩子
- **OpenCode v1**：才支持 `.opencode/plugins/*.ts` 的 `chat.message` 每轮注入（`DOCS_RECALL_OPENCODE_V1_PLUGIN=1`）
- **DSH**：patch 层（`insert: [{id, name}]`）已验证格式；桥接包的钩子注册要按其 API 补一行
- **其它 agent**：`AGENTS.md` 托管块 + `bash .knowlog/knowledge-retrieve.sh "<prompt>"`（与有钩子的同源）

## 3. 迁移历史日志（从"平铺 + 按日流水"到新规范）

> 先试 `bash .knowlog/adopt-docs.sh`（默认 dry-run）——能扫出来就别手工干；下面是它覆盖不到时的手工流程。

```bash
cp docs/index.md /tmp/index.bak                 # ① 永远先备份索引
# ② 按文件名月份移动（示例：2026-04）
mkdir -p docs/daily/2026-04
for f in docs/daily/2026-04-*.md; do git mv "$f" "docs/daily/2026-04/"; done
# ③ 改索引链接：](daily/2026-04-XX_x.md) → ](daily/2026-04/2026-04-XX_x.md)
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("docs/index.md"); s = p.read_text(encoding="utf-8")
p.write_text(re.sub(r"\]\(daily/(\d{4}-\d{2})-", r"](daily/\1/\1-", s), encoding="utf-8")
PY
# ④ 验证：文件集合 == 索引集合（无差集才算成功）
bash .knowlog/check-daily-index.sh --strict --fix-hint
```

历史上从没有登记过索引的月份（早期流水日志），先用 `LEGACY_MONTHS` 降级为告警，再逐月回填：

```bash
LEGACY_MONTHS="2026-04 2026-05" bash .knowlog/check-daily-index.sh
```

回填时建议派子代理读旧日志出"日期 + 一句话摘要"（不要自己读几十篇，会吃掉上下文），
再按日期升序插入对应月份表格。

## 4. 接 CI / pre-commit

```bash
# .git/hooks/pre-commit（或 husky / lefthook 的 pre-commit）
#!/bin/bash
set -e
if [ -d docs/daily ]; then
  bash .knowlog/check-daily-index.sh --strict || {
    echo "❌ 日志索引不一致；跑 bash .knowlog/check-daily-index.sh --fix-hint 看修法"; exit 1; }
fi
```

只校验结构（机器能判定的事）。**不要**在 CI 里校验"日志写得够不够详细"——那只会催生敷衍填充。

## 5. 装/卸召回钩子

```bash
bash .knowlog/bootstrap-docs.sh --with-hook        # 复制钩子 + 注册 UserPromptSubmit（幂等，已注册则跳过）
```

- 手动配置等价于在 `.claude/settings.json` 的 `hooks.UserPromptSubmit` 里加：
  `{"hooks":[{"type":"command","command":"python3 .claude/hooks/inject-knowledge.py","timeout":10}]}`
- 临时关闭：`SKIP_KNOWLEDGE_HOOK=1`
- **没有钩子机制的 agent**：不需要任何安装，直接 `bash .knowlog/knowledge-retrieve.sh "<prompt>"` 即可（效果等价）

## 6. monorepo / 多仓

- 单仓多包（子目录各自独立 git）：`bootstrap-docs.sh` 的端探测会看一层子目录；也可显式 `--ends "svc-a svc-b"`
- 多仓（各自独立仓库）：**每个仓各建一套**，但共用同一套脚本（把 `.knowlog/` 拷过去即可）
- 若想跨仓共享知识：在其中一个仓放权威知识库，其他仓用 `knowledge-retrieve.sh --root <权威仓>` 召回，**不要**复制文件

## 7. 非 git 项目

脚本默认用 `git rev-parse --show-toplevel` 找根，找不到时退回"脚本所在目录的上一级"。
非 git 项目请显式传 `--root`，并注意 `check-daily-index.sh` 里"死链/字节比较"等纯文件校验照常工作（`--fix-hint` 给的 `git mv` 建议需换成 `mv`）。

## 8. 排查"门禁红灯但不知道从哪下手"

```bash
bash .knowlog/check-daily-index.sh --fix-hint
```

| 报告 | 修复 |
|------|------|
| `目录月(X) ≠ 文件名月(Y)` | 以文件名日期为准：`mkdir -p docs/daily/Y && git mv docs/daily/X/<file> docs/daily/Y/`，再改索引链接与表格位置 |
| `日志散落在 daily/ 根` | 同上（按文件名月份建目录） |
| `index.md 中无对应索引行` | 在该月份表格追加一行；或若该文件是误建，删除文件 |
| `死链：文件不存在` | 删除该行，或修链接（`--fix-hint` 会指出行号） |
| `所在表格月 ≠ 文件月` | 把该行移到正确月份表格下（不要改文件名去迁就表格） |
| `有 N 行重复索引` | 保留一行；通常是把文件搬到月份目录后又补了一行 |
| `链接仍是旧扁平路径` | 改成 `daily/<YYYY-MM>/…`（正则批量替换，见配方 3） |
