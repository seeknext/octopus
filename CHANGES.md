# 个人仓 vs 原仓差异对比

> 个人仓：`git@github.com:seeknext/octopus.git`
> 原仓：`git@github.com:bestruirui/octopus.git`
> 基础：原仓最新 master（v0.13.4，d5a893f）+ 5 个定制提交

## 差异总览

共改动 14 个文件（+172 / -41 行），核心是 **Group 路由新增两种模式**、**日志详情高亮方式**、**Docker 构建**三块。

## 1. Group 路由：新增 round_robin / random 模式（核心定制）

| 模式 | 行为 | 相对原仓 |
|---|---|---|
| `round_robin`（轮询） | **纯顺序轮询**：每分组独立游标，第一请求从 A 开始，失败立即顺延 B/C/D，下个请求从成功渠道的下一个继续；无冷却/亲和 | 🆕 新增 |
| `random`（随机） | 随机选择，失败渠道冷却跳过 | 🆕 新增 |
| `manual` / `failover` | 原仓已有行为 | 未动 |

### 涉及文件

| 文件 | 修改内容 |
|------|----------|
| `internal/model/group.go` | 新增 `GroupModeRoundRobin` / `GroupModeRandom` 常量，Create/Update/Group 的 binding 校验加入新模式 |
| `internal/relay/route.go` | `pickGroupItem` 新增 round_robin（每分组独立游标 `RouteState.rrCursor`，无冷却）与 random 分支；`recordRouteSuccess/Failure` 对 round_robin 直接返回 |
| `internal/relay/handler.go` | 新增 `retryAfterFailure` 失败节奏控制：轮询模式未转完一圈立即顺延，整圈全败才等待重试间隔；`recordRouteFailure` 仅对非轮询模式执行 |
| `internal/server/handlers/setting.go` | backup 导入校验接受 `round_robin` / `random` 模式 |
| `web/src/api/group.ts` | `GroupMode` 类型新增 `'round_robin' \| 'random'` |
| `web/src/components/modules/group/Editor.tsx` | 模式下拉选项新增 round_robin 和 random |
| `web/src/locales/*.json`（en/zh_hans/zh_hant） | 新增 `roundRobin`、`random`、`modeHint` 文案 |

### round_robin 行为语义

```
第一请求从 A 开始 → A 不通立即顺延 B → C → D
选中即游标前移 → 下一请求从成功渠道的下一个继续
全部渠道都挂 → 转完一整圈后等待一次重试间隔（防忙打风暴）
```

## 2. 日志详情：按日志渠道高亮（替代全局路由高亮）

> 背景：原仓日志详情高亮 `runtime.current_item_id`（分组全局当前路由成员），会被并发请求随时翻动，与日志卡片渠道不一致。

| 文件 | 修改内容 |
|------|----------|
| `web/src/components/modules/log/Item.tsx` | 高亮改为按日志自身渠道匹配（`item.channel_name === log.target_channel && item.model_name === log.target_model`）；移除手动切换渠道按钮与 `switchingItemId`/`useUpdateGroup` 状态；命中成员显示"本次请求"标签 |
| `web/src/locales/*.json` | 新增 `thisRequestChannel`（本次请求） |

## 3. Docker 多阶段构建（个人仓独有）

| 文件 | 说明 |
|------|------|
| `Dockerfile` | node 前端（corepack+pnpm）→ go 后端（GOPROXY=goproxy.cn）→ scratch 导出二进制 |

构建命令（本地无 go/docker 环境，最终在服务器执行）：

```bash
docker build --target export -o . .
```

构建后当前目录生成 `octopus` 单文件二进制（已嵌入前端页面），`./octopus start` 即可（数据存 `./data/`）。

## 4. AGENTS.md / .gitignore

| 文件 | 说明 |
|------|------|
| `AGENTS.md` | 仓库关系标注 + 构建说明（新增） |
| `.gitignore` | 忽略 `.omo` 会话目录（新增），并已从 git 历史清除 `.omo/` 误入库文件 |

## 补充说明

- `.omo/run-continuation/*.json` 为 opencode 会话记录，已用 filter-branch 从 git 历史清除，并通过 `.gitignore` 防止再次入库
- 除上述定制外，代码与上游 v0.13.4（d5a893f）保持一致，后续可通过 `git rebase origin/master` 跟进上游更新