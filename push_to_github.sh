#!/bin/bash
# ============================================================
# 口播智能体 App - 一键推送到 GitHub 脚本
# ============================================================
# 使用方法:
#   1. 先在 GitHub 上创建一个空仓库（不要勾选 README）
#   2. 修改下方的 REMOTE_URL 为你的仓库地址
#   3. 给脚本执行权限: chmod +x push_to_github.sh
#   4. 运行: ./push_to_github.sh
# ============================================================

set -e

# ======================== 配置区域 ========================
# ⚠️ 替换为你的 GitHub 仓库地址（HTTPS 或 SSH 均可）
REMOTE_URL="https://github.com/koubo-build/koubo-app.git"
# 示例:
# REMOTE_URL="https://github.com/myuser/koubo-app.git"
# REMOTE_URL="git@github.com:myuser/koubo-app.git"

# 提交信息（可自定义）
COMMIT_MSG="feat: 口播智能体App初始提交"
# ==========================================================

echo "=========================================="
echo "  口播智能体 App - 推送到 GitHub"
echo "=========================================="
echo ""

# 检查 git 是否已安装
if ! command -v git &> /dev/null; then
    echo "❌ 未检测到 git，请先安装: https://git-scm.com"
    exit 1
fi

# 检查是否已在 git 仓库中
if [ ! -d ".git" ]; then
    echo "📦 初始化 Git 仓库..."
    git init
    echo "✅ Git 仓库初始化完成"
else
    echo "✅ 已存在 Git 仓库"
fi

# 设置远程仓库
REMOTE_NAME="origin"
if git remote get-url "$REMOTE_NAME" &> /dev/null; then
    EXISTING_URL=$(git remote get-url "$REMOTE_NAME")
    if [ "$EXISTING_URL" != "$REMOTE_URL" ]; then
        echo "🔄 更新远程仓库地址: $EXISTING_URL -> $REMOTE_URL"
        git remote set-url "$REMOTE_NAME" "$REMOTE_URL"
    else
        echo "✅ 远程仓库已配置: $REMOTE_URL"
    fi
else
    echo "🔗 添加远程仓库: $REMOTE_URL"
    git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

# 创建 .gitignore（如果不存在）
if [ ! -f ".gitignore" ]; then
    echo "📝 创建 .gitignore 文件..."
    cat > .gitignore << 'GITIGNORE'
# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
build/
*.apk
*.aab

# Android
**/gradle-wrapper.jar
**/local.properties
**/.gradle/
**/captures/
**/generated/

# iOS
*.mode1v3
*.mode2v3
*.moved-aside
*.pbxuser
*.perspectivev3
**/xcuserdata/
**/Pods/

# IDE
.idea/
.vscode/
*.iml
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
*.env.local

# Misc
*.log
pubspec.lock
GITIGNORE
    echo "✅ .gitignore 已创建"
else
    echo "✅ .gitignore 已存在"
fi

# 添加所有文件
echo ""
echo "📂 添加文件到暂存区..."
git add -A

# 检查是否有变更
if git diff --cached --quiet; then
    echo "⚠️ 没有新的变更需要提交"
else
    # 提交
    echo "💾 提交变更..."
    git commit -m "$COMMIT_MSG"
    echo "✅ 提交完成: $COMMIT_MSG"
fi

# 设置默认分支为 main
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ -z "$CURRENT_BRANCH" ]; then
    echo "🔀 创建 main 分支..."
    git checkout -b main
elif [ "$CURRENT_BRANCH" != "main" ]; then
    echo "🔀 当前分支: $CURRENT_BRANCH，切换到 main..."
    git branch -m "$CURRENT_BRANCH" main
else
    echo "✅ 当前分支: main"
fi

# 推送到 GitHub
echo ""
echo "🚀 推送到 GitHub..."
git push -u origin main

echo ""
echo "=========================================="
echo "  ✅ 推送成功！"
echo "=========================================="
echo ""
echo "📌 后续步骤:"
echo "  1. 访问仓库的 Actions 页面查看编译进度"
echo "  2. 编译完成后，在 Artifacts 中下载 APK"
echo "  3. 如需发布 Release，打 tag 后推送:"
echo "     git tag v1.0.0"
echo "     git push origin v1.0.0"
echo ""
