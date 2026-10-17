/**
 * docs-recall-dsh — DSH 召回桥接插件（Cordis 插件）
 *
 * 职责：在"用户提交 prompt"时调用项目内的 `scripts/recall-core.py`，把命中的规范/坑点送进上下文。
 * 与 Claude Code / Codex 的钩子、OpenCode 的插件**同源**：匹配逻辑只有一份（recall-core.py），
 * 本文件只负责"怎么送进 DSH 的上下文"。
 *
 * ── 已验证（本机 v0.6.x profile=web）──
 * · patch 层写法：`- insert: [{id, name}]`（照 dsh-context 的真实样例）→
 *   `dsh --profile web --patch <本包 cordis.patch.yml> --dump-config` 里能看到 `- id: docs-recall`
 * · Cordis 插件惯用法（照 dsh-context 的真实实现）：`ctx.effect(() => () => cleanup)`、
 *   `ctx.get(name, false)`、`ctx.inject([...], cb)`
 * · DSH 原生把 skill 当**一等上下文类别**（dsh-context 的类型里 `Category = 'user' | 'inject' | 'skill' | …`，
 *   且 `<available_skills>` 目录与 skill 加载结果都算 `skill` 类）→ 所以"让 DSH 认识 knowlog"
 *   其实不需要插件：用 `npx skills add <本 skill>` 装进去即可；插件只解决"每轮自动召回"。
 *
 * ── 需要按你的 DSH 版本补一行（TODO_INJECT）──
 * "把一段文本注入当前轮上下文"的官方调用名请对照你机上的实现确认，可参考：
 *   ~/.dsh/profiles/<profile>/node_modules/dsh-context/lib/index.js
 * 找它订阅会话/上下文节点的方式（本文件已把注入点单独抽成 injectHint()，只需改那一处）。
 * 找不到时本插件**静默退出**，不会弄坏宿主；此时用命令行兜底：
 *   bash scripts/knowledge-retrieve.sh "<prompt>"
 *
 * 本文件刻意不 import 任何 DSH 内部包：依赖装不上时也不会连带炸掉宿主。
 */
import { execFileSync } from "node:child_process";
import { existsSync, appendFileSync } from "node:fs";
import { join, resolve } from "node:path";

const MAX_BYTES = 8000;

function log(root, line) {
  if (process.env.DOCS_RECALL_DEBUG !== "1") return;
  try {
    appendFileSync(join(root, ".dsh", "docs-recall.log"), `[${new Date().toISOString()}] ${line}\n`);
  } catch {}
}

/** 调项目内的召回核心（唯一实现）；任何失败都返回空串 */
function recall(root, core, query) {
  try {
    if (!query || !query.trim()) return "";
    return execFileSync("python3", [join(root, core), "--query", query.slice(0, MAX_BYTES)], {
      cwd: root, timeout: 3000, maxBuffer: 1 << 20,
    }).toString().trim();
  } catch {
    return "";
  }
}

export default function plugin(ctx, config = {}) {
  const root = resolve(config.root ?? ".");
  const core = config.core ?? "scripts/recall-core.py";
  if (!existsSync(join(root, core))) return;          // 项目没装文档体系 → 安静退出
  if (typeof ctx?.effect !== "function") return;      // 非 Cordis 宿主 → 安静退出

  // TODO_INJECT：这里是唯一的"版本相关"代码点。
  // 思路：拿到"当前轮的用户输入文本" → 调 recall() → 把结果交给宿主的注入通道。
  // 下面的实现只做"探测 + 记录"，不会误改宿主状态（宁可不动，也不要写坏上下文）。
  const candidates = ["prompt", "context", "systemPrompt", "messages"];
  const seen = candidates.filter((k) => typeof ctx.get?.(k, false)?.inject === "function"
                                      || typeof ctx.get?.(k, false)?.append === "function");

  ctx.effect(() => {
    log(root, `plugin loaded（root=${root} core=${core} 可注入通道=${seen.length ? seen.join(",") : "未识别"}）`);
    if (seen.length === 0) {
      log(root, "未识别到注入通道：请按 README 的 TODO_INJECT 对照 dsh-context 补一行；" +
                "在此之前用命令行兜底 knowledge-retrieve.sh");
      return () => {};
    }
    const svc = ctx.get(seen[0], false);
    const onInput = (text) => {
      const hint = recall(root, core, String(text ?? ""));
      if (!hint) return;
      try {
        if (typeof svc.inject === "function") svc.inject(hint);
        else if (typeof svc.append === "function") svc.append(hint);
        log(root, `injected ${hint.length} chars via ${seen[0]}`);
      } catch (e) {
        log(root, `inject failed: ${e?.message ?? e}`);
      }
    };
    // 若宿主暴露了"用户提交"事件总线，就挂上去（名称按上一步探测结果）
    try { ctx.on?.("user_prompt_submit", (p) => onInput(p?.prompt ?? p?.text ?? "")); } catch {}
    return () => {};
  });

  return undefined;
}
