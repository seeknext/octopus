# Octopus 自定义修改记录

## 概述

基于 octopus v0.13.2 的个人定制版本，主要添加了 **group 级别的 round-robin/随机轮询** 功能，以及 **Docker 多阶段构建**。

## 修改文件清单

### 1. Group 分发模式（核心功能）

| 文件 | 修改内容 |
|------|----------|
| `internal/model/group.go` | 新增 `GroupModeRoundRobin`/`GroupModeRandom` 常量，更新 binding 校验 |
| `internal/relay/route.go` | `pickGroupItem` 中实现 round-robin（原子计数器+冷却跳过）和随机选择逻辑 |
| `internal/server/handlers/setting.go` | backup 校验接受新模式 |

### 2. 前端 UI

| 文件 | 修改内容 |
|------|----------|
| `web/src/api/group.ts` | `GroupMode` 类型新增 `'round_robin' \| 'random'` |
| `web/src/components/modules/group/Editor.tsx` | 模式下拉选项新增 round_robin 和 random |

### 3. 国际化

| 文件 | 新增翻译 |
|------|----------|
| `web/src/locales/en.json` | `"roundRobin": "Round Robin"`, `"random": "Random"` |
| `web/src/locales/zh_hans.json` | `"roundRobin": "轮询"`, `"random": "随机"` |
| `web/src/locales/zh_hant.json` | `"roundRobin": "輪詢"`, `"random": "隨機"` |

### 4. Docker 构建

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 多阶段构建：node 前端 → go 后端 → scratch 导出。GOPROXY 使用 goproxy.cn |

### 5. 日志详情面板展示（本仓库另一次定制）

> 背景：round_robin/random 模式下，日志详情左侧 Group 面板原来高亮 `runtime.current_item_id`
> （分组全局当前路由成员），会被其它并发请求随时翻动，导致与日志卡片渠道不一致。

| 文件 | 修改内容 |
|------|----------|
| `web/src/components/modules/log/Item.tsx` | 日志详情左侧 Group 面板高亮改为按日志自身渠道匹配（`item.channel_name === log.target_channel && item.model_name === log.target_model`），不再依赖分组实时路由状态；成员按钮全部禁用（移除手动切换渠道功能）；命中的成员显示"本次请求"标签 |
| `web/src/locales/en.json` | 新增 `"thisRequestChannel": "This Request"` |
| `web/src/locales/zh_hans.json` | 新增 `"thisRequestChannel": "本次请求"` |
| `web/src/locales/zh_hant.json` | 新增 `"thisRequestChannel": "本次請求"` |

> 注意：该改动同时删除了 LogDetail 中基于 `runtime.current_item_id`/`switchingItemId` 的高亮
> 与切换逻辑，并清理了 `useUpdateGroup`、`switchingItemId` 等不再使用的状态。

## 架构说明

### Group 分发流程

```
请求进入 → 选择 Group → pickGroupItem 选择成员 → ChannelGrantGet 获取授权 → 转发
```

- **故障转移模式**：按优先级选择，失败后冷却并切换下一个
- **轮询模式**：原子计数器递增，跳过冷却中的成员，均匀轮询
- **随机模式**：随机选择，跳过冷却中的成员

### 关键设计决策

1. **为什么不实现 channel 级别的 key 轮询**：
   - octopus 的路由单元是 `Grant = Model + Key` 的组合
   - group member 绑定的是 GrantID，换 key 会导致 grant 的协议信息不匹配
   - 统计数据也会混乱
   - **正确做法**：一个 key 一个渠道，用 group 级别的 round_robin 轮询

2. **Docker 构建**：
   - 使用 `goproxy.cn` 加速国内 Go 模块下载
   - 前端输出到 `static/out`（vite outDir 配置）
   - Go embed 通过 `static/static.go` 的 `//go:embed all:out` 嵌入

3. **日志详情展示（渠道/模型一致性）**：
   - 日志详情左侧 Group 面板高亮一律按 `log.target_channel` + `log.target_model` 反查成员
   - 不再依赖 `runtime.current_item_id`（全局滚动游标，与单条日志无关）
   - 不提供手动切换渠道功能（不需要）
   - `thisRequestChannel` 标签用于区分命中的成员

## 如何修改

### 添加新的分发模式

1. 在 `internal/model/group.go` 添加常量：
   ```go
   GroupModeXxx GroupMode = "xxx"
   ```

2. 在 `internal/relay/route.go` 的 `pickGroupItem` 中添加逻辑

3. 在 `internal/server/handlers/setting.go` 更新 backup 校验

4. 更新前端 `web/src/api/group.ts` 的 `GroupMode` 类型

5. 更新 `web/src/components/modules/group/Editor.tsx` 添加选项

6. 添加 i18n 翻译

### 修改转发逻辑

主要逻辑在 `internal/relay/handler.go` 的 `Forward` 函数中，转发循环的核心是：
- `pickGroupItem` 选择成员
- `ChannelGrantGet` 获取授权
- `buildOutbound` 构造出站请求

## 已知问题

- 版本号显示 `dev`/`unknown`（cosmetic only，不影响功能）
- Docker Hub 连接可能超时，需要手动 pull 镜像
- 日志详情重试轮次（rounds）不完整：`RequestState` 是单快照结构，每轮 `startRound`/`finishRound` 覆盖同一份字段，中间轮次历史不保留；且前端 rounds 累积逻辑（`Item.tsx` 中 `!log.sending && current.every(...)`）会丢弃已结束且未观察到的新轮次。所有渠道限流快速切换时，日志详情看不到每轮切换记录。这是原始项目（v0.13.2）就存在的问题，非本仓库修改引入；若要修复需后端补轮次历史（对齐旧版 v0.9.x 的 `attempts` 数组）
