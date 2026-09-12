# Octopus 定制说明

## 仓库关系

- **原仓**：`git@github.com:bestruirui/octopus.git`
- **个人仓**：`git@github.com:seeknext/octopus.git`

本地开发环境**没有 go 环境和 docker 环境**，代码只做静态检查，最终产物通过 docker 多阶段构建导出：

```bash
docker build --target export -o . .
```

构建后当前目录生成 `octopus` 单文件二进制（已嵌入前端页面），运行 `./octopus start` 即可（数据存 `./data/`）。