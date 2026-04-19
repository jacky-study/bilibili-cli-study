---
article_id: OBA-ajc8b3pk
tags: [open-source, bilibili-cli, RESEARCH-LOG.md, chrome-extension, cli, git]
type: note
updated_at: 2026-03-26
---

# 研究日志

## 2026-03-26: 整体架构设计

**研究主题**: 整体架构设计

**研究问题**: bilibili-cli 的整体架构是如何设计的？

**仓库**: [bilibili-cli](https://github.com/public-clis/bilibili-cli)

**核心发现**:
- **分层架构**：CLI Layer → Business Layer → Service Layer → External Layer
- **命令模式**：使用 Click 装饰器定义命令，按功能模块分散组织
- **认证策略**：三级降级（保存凭证 → 浏览器 Cookie → 二维码登录）
- **输出格式化**：双模式（Rich 表格 / 结构化 JSON/YAML）+ Schema Envelope
- **异步桥接**：`run_or_exit()` 透明桥接 async → sync
- **错误处理**：层次化异常映射，隔离第三方依赖

**产出**:
- 📄 研究笔记: [architecture-overview.md](./architecture-overview.md)
- 📘 实操指南: [architecture-guide.md](./architecture-guide.md)

**进度（持续更新）**:
- questions: 1
- notes: 1
- guides: 1
- skill templates: 0
- runnable skills: 0

---

## 2026-03-26: 风控解决方案

**研究主题**: 风控解决方案

**研究问题**: bilibili-cli 是如何解决风控问题的？

**仓库**: [bilibili-cli](https://github.com/public-clis/bilibili-cli)

**核心发现**:
- **额外 Cookie 字段**：`buvid3`、`buvid4`、`dedeuserid` 模拟真实浏览器
- **凭证 TTL 管理**：7 天自动刷新，避免使用过期凭证
- **浏览器 Cookie 提取**：从 Chrome/Firefox/Edge/Brave 提取完整 Cookie
- **错误识别**：HTTP 412 → `RateLimitError`，提供友好提示
- **多层防护**：Cookie 字段 → TTL 管理 → 友好错误处理

**产出**:
- 📄 研究笔记: [anti-scrape-solution.md](./anti-scrape-solution.md)

**进度（持续更新）**:
- questions: 1
- notes: 1
- guides: 0
- skill templates: 0
- runnable skills: 0

---
