# Toonflow 集成说明

本文件概述将 Toonflow 功能集成到 koubo-app 的计划与运行方式。

目标
- 快速实现 Toonflow 的全功能（脚本 → 分镜 → 角色 → 导出）作为可安装/可运行的发行版。
- 初期采用“服务化”集成：在容器中运行 Toonflow 原项目（或镜像），并通过一个轻量适配器（adapter）对外提供简化 API，Flutter 客户端调用该 API。

高层架构
- docker-compose（本仓库）负责启动：
  - toonflow 服务（容器或镜像 / 可配置为 build-from-source）
  - adapter 服务（轻量 Node/Python 服务，用于注入 API Keys、做鉴权与前端适配）
  - （可选）数据库/向量存储服务
- Flutter (koubo-app) 作为客户端，通过 adapter 调用 Toonflow 功能。

合规性与许可
- Toonflow 使用 Apache-2.0 协议。我们会在本仓库 PR 中保留并提交原项目的 LICENSE 与 NOTICE（如适用），并在二进制发布中注明来源与版权信息。

运行与发布
- 我们将在 CI 中添加自动构建（镜像 + 桌面安装包）并发布 Release，供用户下载安装。

下一步
- 我会在 feat/toonflow-integration 分支提交 PoC（含 codeact/index.json 配置骨架、docker-compose 模板、adapter 说明与基本运行文档）。
