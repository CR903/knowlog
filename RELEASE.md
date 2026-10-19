# 发版与发布（维护者）

> 面向维护者。使用者看 `README.md` / `references/installation.md`。
> 分发有两条路：**主路径 = GitHub 仓库**（`npx skills add CR903/knowlog`）；**辅路径 = npm**（只发布 CLI，让命令短一点）。

## 0. 发布前：四处版本号必须一致

| 位置 | 字段 |
|---|---|
| `VERSION` | 裸版本号，如 `0.3.1` |
| `package.json` | `version` |
| `skills.json` | `version` |
| `CHANGELOG.md` | 顶部有对应版本小节（不要留着 `Unreleased` 里已经发布的内容） |

```bash
grep -H "" VERSION package.json skills.json | grep -E "0\.[0-9]+\.[0-9]+"
head -8 CHANGELOG.md
```

## 1. 发布到 npm（发布 CLI）

```bash
npm login                 # 需要 npm 账号；开了 2FA 会要一次性码
npm publish --dry-run     # 先看会发哪些文件（约 90 kB / 56 个文件）
npm publish               # 正式发布（public 包无需 --access）
```

- `prepublishOnly` 会自动跑 **93 项确定性自测 + 密钥扫描**：任一不过就**发不出去**（故意这么设的：坏包不上架）。
- 包内容由 `package.json` 的 `files` 白名单决定：`bin/ SKILL.md VERSION scripts/ assets/ adapters/ references/ CHANGELOG.md`（**不含** `evals/`、`.github/`）。
- 发布后验证：`npx -y knowlog@<版本> version`。

### ⚠️ 已知限制

- 包里是 **bash + python3 脚本**（CLI 只是薄壳转发）→ **Windows 原生不行**，需要 WSL / Git Bash；macOS / Linux 直接可用。
- 发布**不可逆**：同一版本号不能重发。72 小时内可 `npm unpublish knowlog@<版本>`；超过 72 小时只能 `npm deprecate` 并另发新版本。
- 发布后请把文档里的长路径**换回短形式**（见第 3 步）。

## 2. 发布 GitHub 侧（skill 主路径）

```bash
git tag -a v0.3.1 -m "knowlog 0.3.1"
git push origin main --tags
# 可选：GitHub Release 里贴 CHANGELOG 对应小节的正文
```

- `npx skills add CR903/knowlog` / `skills update` 按仓库内容与 `skillFolderHash` 工作，**不依赖 tag**；tag 是给人看的历史锚点。
- 建议顺序：**先 npm publish，再打 tag**（保证 tag 对应的提交与上架内容一致）。

## 3. 发布后：把文档改回短形式

npm 上有了 `knowlog` 之后，才能把 `node ~/.agents/skills/knowlog/bin/knowlog.mjs <cmd>` 换回 `npx knowlog <cmd>`：

```bash
grep -rln "node ~/.agents/skills/knowlog/bin/knowlog.mjs" README.md SKILL.md references/ bin/
# 逐个改成 `npx knowlog <cmd>`，并删掉"未发布 npm，勿用 npx knowlog"的警示
```

> 注意：**只在真的发布之后才改**。没发布就写 `npx knowlog` 会 404；而如果 `knowlog` 这个名字被别人抢注，照文档敲 `npx knowlog` 的人就会执行陌生代码。

## 4. 离线分发（不发 npm 也能给别人）

```bash
bash scripts/package-skill.sh              # 产出 ~/.agents/skills/.packages/knowlog-vX.Y.Z.skill
# 对方：解压后 bash scripts/install-skill.sh --agent auto
```

## 5. 每次发版的检查清单

1. `bash evals/test_scripts.sh` → 全绿
2. `bash scripts/check-secrets.sh` → 干净
3. 四处版本号一致（§0）
4. `CHANGELOG.md` 写清"改了什么 / 为什么"（含**事故记录**：踩过的坑要留痕）
5. `npm publish` → `git tag vX.Y.Z` → `git push --tags`
6. 用时若发现文档与实现不一致：**先改文档再发**（文档里的每条命令都要在"别人的起点"实测一遍，别只在作者环境里试）
