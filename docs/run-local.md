# 本地运行指南（PoC）

前提
- 已安装 Docker 与 docker-compose
- 在本地或 CI 环境中有模型 API Key（例如 OpenAI），用环境变量注入：OPENAI_API_KEY

步骤（本地）
1. 在仓库根目录，复制 .env.example 为 .env 并填入你的 API Key：
   OPENAI_API_KEY=sk-xxxx

2. 启动容器：
   docker-compose up --build

3. 启动客户端（Flutter 桌面 / 其他）：
   - 在 koubo-app Flutter 项目中，打开设置页，设置 adapter 地址为 http://localhost:4000
   - 打开“短剧工作台”，尝试生成脚本或角色提取。

注意
- 如果 Toonflow 官方镜像不可用，请在 integrations/toonflow 目录放置 Toonflow 源码并在 docker-compose 中改为 build: ./integrations/toonflow
- 生产环境请使用 secrets 管理 API Key，不要将 Key 提交到仓库。
