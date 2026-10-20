# 体系结构：每个文件干什么

```
<项目根>/
├── AGENTS.md                      # ★ 约束入口：托管块声明"日志/知识/领域"的规则（各大 agent 都读它）
├── .claude/hooks/inject-knowledge.py   # 可选：Claude Code 的关键词召回钩子
├── .claude/settings.json          # 可选：注册 UserPromptSubmit → inject-knowledge.py
├── .knowlog/
│   ├── bootstrap-docs.sh          # 搭/补建体系（幂等；两种布局；复制 assets 使其自包含）
│   ├── adopt-docs.sh              # 采纳既有异构文档（默认 dry-run）
│   ├── install-recall.sh          # 把召回装到各 agent（钩子/插件/规则文件）
│   ├── recall-core.py             # 召回匹配与渲染的唯一实现（所有适配器都调它）
│   ├── index-util.py              # 索引写入的唯一实现（new-daily-log / adopt 都调它）
│   ├── check-knowledge-index.sh   # 知识库索引一致性门禁（flat/by-end 自适应）
│   ├── new-daily-log.sh           # 建日志 + 插索引行
│   ├── check-daily-index.sh       # 门禁：日志↔索引一致性
│   ├── new-knowledge.sh           # 建知识 + 更新两级索引
│   ├── new-keyword.sh             # 加召回规则
│   ├── knowledge-retrieve.sh      # 召回入口（命令行，兜底一切 agent）
│   └── inject-knowledge.py        # 召回钩子本体（被复制到 .claude/hooks/）
└── docs/
    ├── index.md                   # ★ 日志唯一索引（按年月倒序；`## 📅 YYYY年` + `### YYYY-MM` 表格）
    ├── README.md                  # 使用指南（人看：怎么记、怎么查、为什么）
    ├── template.md                # 日志模板（被 new-daily-log.sh 复制）
    ├── templates/
    │   └── knowledge-doc.md       # 知识文档模板（可被项目改写；缺失时脚本用内置默认）
    ├── daily/
    │   └── <YYYY-MM>/             # 月份目录，写入时即建
    │       └── YYYY-MM-DD_<slug>.md
    ├── knowledge/                 # 结构化记忆（两种布局，见下）
    │   ├── README.md              # 总说明：分类标准、贡献规范、召回用法
    │   ├── index.md               # ★ 索引（by-end：各端表格 + 各端 section；flat：四个分类 section）
    │   ├── .keyword-map.json      # 召回规则：正则 → {docs, hint}
    │   ├── <端>/                  # 【by-end 布局】backend / frontend / mobile / common / <子仓名> …
    │   │   ├── README.md          # 本端说明 + 文档模板 + 写作要点
    │   │   ├── index.md           # ★ 本端索引（按分类分节）
    │   │   └── {architecture,guides,troubleshooting,best-practices}/
    │   │       └── <kebab-name>.md
    │   └── {architecture,guides,troubleshooting,best-practices}/   # 【flat 布局】单面项目直接放这里
    │       └── <kebab-name>.md
    ├── domain context/            # 领域记忆（业务长期规则）
    │   ├── README.md              # 这层是干什么的 + 路由说明 + 维护约定
    │   └── domain-<name>.md       # 一个业务领域一份
    └── agents/                    # 给 agent 看的约定（不是产品文档）
        ├── domain.md              # agent 怎么消费领域文档（何时必须全量读）
        ├── issue-tracker.md       # issue/spec 用本地 markdown 的约定（.scratch/）
        └── triage-labels.md       # 五个 canonical 状态词
```

## 两种知识库布局（选一个，不要混）

| 布局 | 目录形态 | 适用 | 索引形态 |
|------|----------|------|----------|
| `flat` | `docs/knowledge/<分类>/` | 单面项目（一个服务/CLI/管道） | 根 `index.md` 四个分类 section |
| `by-end` | `docs/knowledge/<端>/<分类>/` | 多端项目（后端+前端+移动端，知识不通用） | 根 `index.md` 各端 section + 每端 `index.md` |

选择标准是**知识会不会被复用**，不是"仓库里有几个语言"。`--knowledge-layout auto` 按端数量自动定（≥2 端 → by-end）。

## 四层记忆的分工（唯一真相）

| 层 | 位置 | 记住什么 | 生命周期 | 读法 |
|----|------|----------|----------|------|
| 时序记忆 | `docs/daily/<YYYY-MM>/` | 哪个任务在何时做了什么、为什么、怎么验证的 | 只追加，不修改历史（除非发现记录有错） | 按 `docs/index.md` 定位，或 grep |
| 结构化记忆 | `docs/knowledge/<端>/<分类>/` | 可复用结论：坑位、约定、最佳实践 | **活文档**：过期就改，不新旧并存 | 先查索引，再关键词召回 |
| 领域记忆 | `docs/domain context/` | 业务长期规则：术语、状态机、公式、数据流 | 业务变了就改 | 靠 `AGENTS.md` 路由表**全量**读 |
| 约束 | `AGENTS.md` 托管块 + `.knowlog/*.sh` | 「必须做什么」和「做错即红灯」 | 随体系演进 | 每轮自动进入上下文（AGENTS.md） |

**边界判断**（常被问）：

- 「XX 字段大小写在 Scan 里敏感」→ 结构化记忆（技术结论，跨任务复用）
- 「归还时用量 ÷ 换算系数 = 扣减量」→ 领域记忆（业务规则，与具体任务无关）
- 「10-17 把导出改成按瓶」→ 时序记忆（一次任务的事实）

## 索引约定

**日志索引 `docs/index.md`**

```
## 📅 2026年
### 2026-10
| 日期 | 任务 | 工作内容 | 提交 | 备注 |
|------|------|----------|------|------|
| [2026-10-17](daily/2026-10/2026-10-17_add-billing-export.md) | 10-17-add-billing-export | ... | 待提交 | ... |
```

- 年份分组 `## 📅 YYYY年`，月份 `### YYYY-MM`，**按年月倒序**（新的在上）
- 表格内**按日期升序**（脚本插入时会自动定位）
- 链接必须是 `daily/<YYYY-MM>/...` 形式（`check-daily-index.sh` 会拒绝扁平路径）

**知识索引（两级）**

- 分端 `docs/knowledge/<端>/index.md`：按 `## architecture` / `## guides` / `## troubleshooting` / `## best-practices` 分节，每节一张 `| 文档 | 说明 | 来源 |` 表
- 根 `docs/knowledge/index.md`：各端一张 `| 端 | 索引 | 说明 |` 总表 + 每端一个 `## 📦 <端> 知识 \`docs/knowledge/<端>/\`` section（`| 分类 | 文档 | 说明 | 来源 |`）
- `new-knowledge.sh` 两处都会写：分端按**分类**插入；根索引进**本端 section**（找不到 section 时提示手工补，不猜结构）

## 关键词召回机制

`.keyword-map.json` 的唯一职责：**在正确的时刻把正确的文档路径推到台面上**。

```json
{
  "tenantId|ShardingSphere": {
    "docs": ["docs/knowledge/backend/guides/database-guidelines.md"],
    "hint": "分片：所有查询必须带 tenantId，否则全库扫描"
  }
}
```

- 键 = 正则，跑在「用户 prompt + `git diff --cached`」上（很多坑是在"正要写的那段代码"里踩的，光看 prompt 会漏）
- 值 = `{docs: [建议读的文档], hint: 一句话提醒}`
- 注入上限 4 条、只给路径不给全文（控制在 ~800 token）
- 命中后**由 agent 判断**是否相关，相关再用 Read 全量加载
