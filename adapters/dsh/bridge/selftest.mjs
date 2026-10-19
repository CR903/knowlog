/**
 * selftest.mjs — docs-recall-dsh 的离线功能自测（不起 DSH、不碰用户配置、不联网）
 *
 * 干什么：import 本包的 `apply()`，喂一个假的 Cordis ctx，捕获它注册的
 * `agent/pre-step` 监听器，然后用合成的 payload 驱动它，断言：
 *   1. 用 `{ prepend: true }` 注册（与第一方 dsh-time-context / dsh-mnemon 同形）
 *   2. 委托上游 decision 后，往后追一条 `source.kind === 'plugin'` 的 UserMessage
 *   3. 注入文本 = `scripts/recall-core.py` 的 stdout，且查询词确实传进去了
 *   4. 每个 turn 只注入一次（step !== 1 不注入）
 *   5. 幂等：decision 里已有本插件来源的消息时不再重复
 *   6. 不自己喂自己：`messages` 里只有 plugin 来源时不算查询词
 *   7. decision 为 reject 时原样透传（添加上下文不构成否决）
 *   8. 同文本命中不跨轮重复注入
 *   9. 找不到 recall-core.py 时完全不注册监听器（静默退出）
 *
 * 用法：node selftest.mjs            （测本地兜底构造器）
 *       node selftest.mjs --verbose  （多打印）
 *
 * 环境变量 DOCS_RECALL_PLUGIN_ENTRY 可指向另一份 index.js —— verify.sh 用它
 * 把插件放到 `~/.dsh/profiles/` 下的临时目录里跑一次，以覆盖"官方
 * createUserMessage 可用"的分支。
 */

import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ENTRY = process.env.DOCS_RECALL_PLUGIN_ENTRY ?? join(HERE, "lib", "index.js");
const VERBOSE = process.argv.includes("--verbose");

let pass = 0;
let fail = 0;
const ok = (m) => { pass += 1; console.log(`  ✅ ${m}`); };
const bad = (m) => { fail += 1; console.log(`  ❌ ${m}`); };
const chk = (m, cond) => (cond ? ok(m) : bad(m));
const say = (m) => { if (VERBOSE) console.log(`     · ${m}`); };

/** 假 Cordis ctx：只实现本插件用到的最小面。 */
function fakeCtx() {
  const listeners = new Map();
  const disposers = [];
  return {
    listeners, disposers,
    on(event, listener, options) {
      listeners.set(event, { listener, options });
      const dispose = () => listeners.delete(event);
      disposers.push(dispose);
      return dispose;
    },
    effect(fn) {
      const d = fn();
      if (typeof d === "function") disposers.push(d);
      return d;
    },
  };
}

const userMsg = (text) => ({
  id: `u-${Math.random().toString(16).slice(2)}`,
  role: "user",
  content: [{ type: "text", text }],
  source: { kind: "user" },
});

const pluginMsg = (text, plugin = "docs-recall") => ({
  id: `p-${Math.random().toString(16).slice(2)}`,
  role: "user",
  content: [{ type: "text", text }],
  source: { kind: "plugin", plugin },
});

/** 造一个临时"项目"：只有 scripts/recall-core.py 这个桩。 */
function fixtureProject(stdoutLine) {
  const root = mkdtempSync(join(tmpdir(), "docs-recall-selftest-"));
  mkdirSync(join(root, "scripts"), { recursive: true });
  writeFileSync(
    join(root, "scripts", "recall-core.py"),
    `import sys\nprint(${JSON.stringify(stdoutLine)} + " :: " + " ".join(sys.argv[1:]))\n`,
    "utf8",
  );
  return root;
}

/** 驱动已注册的 pre-step 监听器。agent 默认复用同一个对象（真实宿主也是每会话一个）。 */
const AGENT = { id: "selftest-agent" };
async function fire(ctx, { messages, turn = 1, step = 1, aborted = false, base, agent = AGENT }) {
  const entry = ctx.listeners.get("agent/pre-step");
  if (!entry) throw new Error("agent/pre-step 监听器未注册");
  const payload = { agent, messages, turn, step, signal: { aborted } };
  return entry.listener(payload, async () => base ?? { kind: "enter", messages });
}

const { default: apply } = await import(`file://${ENTRY}`);

console.log(`\n\u001b[1mdocs-recall-dsh selftest\u001b[0m  entry=${ENTRY}`);

// ── 1. 注册形状 ────────────────────────────────────────────
const root = fixtureProject("KNOWLOG_HIT_MARKER");
const ctx = fakeCtx();
apply(ctx, { root, core: "scripts/recall-core.py" });

const entry = ctx.listeners.get("agent/pre-step");
chk("注册了 agent/pre-step 监听器", Boolean(entry));
chk("以 { prepend: true } 注册（先委托下游再追加）", entry?.options?.prepend === true);
chk("没有注册别的探测式服务（只动 agent/pre-step）", ctx.listeners.size === 1);
say(`listeners=${[...ctx.listeners.keys()].join(",")}`);

// ── 2/3. 注入形状与内容 ────────────────────────────────────
{
  const decision = await fire(ctx, { messages: [userMsg("改一下 consumeRate 换算系数")] });
  const injected = decision.messages.at(-1);
  chk("enter 决策里追加了一条消息", decision.kind === "enter" && decision.messages.length === 2);
  chk("新消息 source 是 { kind:'plugin', plugin:'docs-recall' }",
    injected?.source?.kind === "plugin" && injected?.source?.plugin === "docs-recall");
  chk("新消息 source.form 是 'snapshot'（与第一方 dsh-time-context 同形）",
    injected?.source?.form === "snapshot" && injected?.source?.sections?.[0]?.name === "docs-recall");
  chk("新消息有 id 与 role:'user'（是合法 UserMessage，不是裸对象）",
    typeof injected?.id === "string" && injected.id.length > 0 && injected.role === "user");
  chk("注入文本来自 recall-core.py 的 stdout", String(injected?.content?.[0]?.text).includes("KNOWLOG_HIT_MARKER"));
  chk("查询词确实传给了 recall-core.py",
    String(injected?.content?.[0]?.text).includes("consumeRate"));
  say(`injected text = ${JSON.stringify(injected?.content?.[0]?.text)}`);
}

// ── 4. 每轮只在 step 1 注入 ────────────────────────────────
{
  const decision = await fire(ctx, { messages: [userMsg("再改一下 consumeRate")], turn: 2, step: 2 });
  chk("step !== 1 不注入（每轮一次）", decision.messages.length === 1);
}

// ── 5. 幂等 ────────────────────────────────────────────────
{
  const base = { kind: "enter", messages: [userMsg("改一下 consumeRate"), pluginMsg("上一轮已注入")] };
  const decision = await fire(ctx, { messages: base.messages, turn: 3, base });
  chk("decision 已含本插件来源消息时不再重复注入", decision.messages.length === 2);
}

// ── 6. 不自己喂自己 ───────────────────────────────────────
{
  const base = { kind: "enter", messages: [pluginMsg("time-context 快照之类", "time-context")] };
  const decision = await fire(ctx, { messages: base.messages, turn: 4, base });
  chk("messages 里只有 plugin 来源时不当作查询词（拒绝自我喂养）", decision.messages.length === 1);
}

// ── 7. reject 透传 ────────────────────────────────────────
{
  const base = { kind: "reject" };
  const decision = await fire(ctx, { messages: [userMsg("改一下 consumeRate")], turn: 5, base });
  chk("上游 reject 时原样透传（添加上下文不构成否决）", decision.kind === "reject");
}

// ── 8. 同文本不跨轮重复注入 ────────────────────────────────
{
  const decisions = [];
  for (let i = 0; i < 2; i += 1) {
    decisions.push(await fire(ctx, { messages: [userMsg("交期与报警阈值的换算")], turn: 10 + i }));
  }
  chk("同文本首次注入、跨轮重复时跳过",
    decisions[0].messages.length === 2 && decisions[1].messages.length === 1);
}

// ── 9. 缺 recall-core.py → 静默退出 ────────────────────────
{
  const bare = fakeCtx();
  apply(bare, { root: "/nonexistent-knowlog-root", core: "scripts/recall-core.py" });
  chk("找不到 recall-core.py 时完全不注册监听器（静默退出，不动宿主）", bare.listeners.size === 0);
}

// ── 10. abort 透传 ────────────────────────────────────────
{
  const decision = await fire(ctx, { messages: [userMsg("改一下 consumeRate 换算法")], turn: 20, aborted: true });
  chk("signal 已 abort 时不注入", decision.messages.length === 1);
}

console.log(`\n  ${fail === 0 ? "\u001b[32mPASS\u001b[0m" : "\u001b[31mFAIL\u001b[0m"} ${pass} passed, ${fail} failed\n`);

rmSync(root, { recursive: true, force: true });
process.exit(fail === 0 ? 0 : 1);
