# Adapter 说明（integrations/toonflow/adapter）

目的：
- 提供一个轻量的 HTTP 适配层，位于 Flutter 客户端与 Toonflow 服务之间。
- 负责注入模型 API Key、处理认证、聚合或简化 Toonflow 的复杂 API 为一组明确的端点。

建议端点（示例）：
- POST /api/script/generate  -> 基于输入文本或章节生成脚本
- POST /api/character/extract -> 从文本提取角色卡
- POST /api/scene/produce -> 触发场景生产/渲染（返回任务 id）
- GET  /api/task/:id/status -> 查询任务状态
- GET  /api/task/:id/result -> 获取导出结果

实现提示：
- adapter 可用 Node/Express 或 Python/Flask 编写。
- adapter 从环境变量读取 OPENAI_API_KEY 等敏感配置并在向 Toonflow 或模型供应商发起请求时使用。
- adapter 仅做必要的验证与适配，不应重复实现 Toonflow 的核心逻辑。
