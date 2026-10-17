#!/usr/bin/env node
/**
 * knowlog CLI — 把 skill 里的脚本收成一个命令，降低上手成本
 *
 * 设计取舍（为什么是"薄壳"而不是把逻辑搬到 JS）：
 *   真正的逻辑（建结构/体检/采纳/召回/索引写入）都在 bash+python 脚本里，那些脚本**项目自己也要用**
 *   （收尾记日志、CI 门禁）。CLI 只做"发现 payload + 转发命令 + 打印下一步"，避免同一逻辑两份实现。
 *   → 也正因为这样，这个包**零依赖**：任何机器 `npx knowlog …` 即可，不需要装 bash 之外的运行时。
 *
 * 用法：
 *   npx knowlog init [--agent auto|claude,opencode] [--root DIR] [--dry-run]
 *   npx knowlog doctor [--root DIR] [--strict]
 *   npx knowlog adopt [--apply]
 *   npx knowlog log <slug> [YYYY-MM-DD]
 *   npx knowlog knowledge <端|--flat> <分类> <name> "<说明>"
 *   npx knowlog install-skill [--agent auto] [--scope user|project] [--mode auto|link|copy]
 *   npx knowlog package [--out DIR]
 *   npx knowlog version
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PAYLOAD = resolve(HERE, "..");                  // 包根 = skill 根（SKILL.md/scripts/assets/adapters/references/VERSION）
const SCRIPTS = resolve(PAYLOAD, "scripts");

const C = { dim: "\x1b[2m", b: "\x1b[1m", g: "\x1b[32m", y: "\x1b[33m", r: "\x1b[31m", x: "\x1b[0m" };
const ok = (m) => console.log(`${C.g}✅${C.x} ${m}`);
const info = (m) => console.log(`${C.dim}ℹ️  ${m}${C.x}`);
const bad = (m) => console.error(`${C.r}❌${C.x} ${m}`);

function version() {
  try { return readFileSync(resolve(PAYLOAD, "VERSION"), "utf8").trim(); } catch { return "0.0.0"; }
}

/** 转发到 skill 里的脚本（保持单一实现） */
function run(script, args, { optional = false } = {}) {
  const p = resolve(SCRIPTS, script);
  if (!existsSync(p)) {
    if (optional) { info(`跳过 ${script}（payload 里没有）`); return 0; }
    bad(`找不到脚本 ${script}（payload: ${PAYLOAD}）`);
    process.exit(1);
  }
  const argv = [p, ...args];
  const cmd = p.endsWith(".py") ? "python3" : "bash";
  const r = spawnSync(cmd, argv, { stdio: "inherit" });
  return r.status ?? 1;
}

function parseFlags(argv) {
  const flags = {}; const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const k = a.slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
      flags[k] = v;
    } else rest.push(a);
  }
  return { flags, rest };
}

const HELP = `
${C.b}knowlog${C.x} v${version()} — 项目文档体系（日志 / 知识库 / 领域上下文 / 索引 / 召回）

${C.b}最常用${C.x}
  knowlog init [--agent auto] [--root DIR] [--dry-run]    给当前项目建/补齐文档体系（含收尾门禁）
  knowlog doctor [--strict] [--fix-hint]                  体检：结构规范 + 日志↔索引 + 知识↔索引
  knowlog log <slug> [YYYY-MM-DD]                         收尾记一笔（自动落月份目录 + 插索引行）
  knowlog knowledge <端|--flat> <分类> <name> "<说明>"    沉淀一条可复用结论（自动更新索引）

${C.b}其它${C.x}
  knowlog adopt [--apply]                                 采纳既有异构文档（默认只看计划）
  knowlog reindex [--apply]                               从磁盘反向补齐知识索引
  knowlog install-skill [--agent auto] [--scope user|project] [--mode auto|link|copy]
                                                              把 skill 本体装到各 agent
  knowlog package [--out DIR]                             打包 .skill（离线分发用）
  knowlog version | help

${C.dim}提示：init 之后，项目内就有全套脚本（scripts/），日常用项目自己的那份即可，不必每次走 npx。${C.x}
`;

function main() {
  const [cmd = "help", ...argv] = process.argv.slice(2);
  const { flags, rest } = parseFlags(argv);
  const root = flags.root ? ["--root", flags.root] : [];
  const dry = flags["dry-run"] === "true";
  const pass = (...k) => k.filter((x) => flags[x] !== undefined).map((x) => `--${x}`);

  switch (cmd) {
    case "help": case "--help": case "-h": console.log(HELP); return 0;

    case "version": case "--version": case "-v": console.log(version()); return 0;

    case "init": {
      console.log(`${C.b}knowlog init${C.x} v${version()}`);
      let rc = run("bootstrap-docs.sh", [...root, ...pass("ends", "project-name", "knowledge-layout"), ...(dry ? ["--dry-run"] : [])]);
      if (rc !== 0) return rc;
      if (flags.agent !== undefined || flags["with-recall"] !== undefined) {
        const target = resolve(flags.root || process.cwd());
        if (!dry) rc = run("install-recall.sh", ["--root", target, "--agent", flags.agent || "auto", "--verify"]);
        else info("（--dry-run：跳过召回适配器安装）");
      } else {
        info("未指定 --agent 时不会改各 agent 的配置；要装召回：knowlog init --agent auto");
      }
      console.log(`\n${C.b}下一步${C.x}\n  1. 记日志：knowlog log <slug>\n  2. 体检：knowlog doctor\n  3. 让 agent 自动记：knowlog install-skill --agent auto`);
      return rc;
    }

    case "doctor": return run("docs-doctor.sh", [...root, ...pass("strict"), ...pass("fix-hint"), ...pass("quiet")]);
    case "adopt": return run("adopt-docs.sh", [...root, ...(flags.apply === "true" ? ["--apply"] : [])]);
    case "reindex": return run("reindex-knowledge.sh", [...root, ...(flags.apply === "true" ? ["--apply"] : [])]);
    case "recall": case "retrieve": return run("knowledge-retrieve.sh", [...root, ...rest]);
    case "log": case "new-log": return run("new-daily-log.sh", [rest[0], rest[1], ...root].filter(Boolean));
    case "knowledge": case "new-knowledge": return run("new-knowledge.sh", [...rest, ...root]);
    case "keyword": case "new-keyword": return run("new-keyword.sh", [...rest, ...root]);
    case "package": return run("package-skill.sh", [...pass("out")]);
    case "install-skill": return run("install-skill.sh", [...pass("agent", "scope", "mode", "root"), ...(dry ? ["--dry-run"] : [])]);
    default:
      bad(`未知命令：${cmd}`);
      console.log(HELP);
      return 2;
  }
}

process.exit(main());
