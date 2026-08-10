#!/bin/bash
# One-click release for launchPad.
#
# Usage: bash dist/release.sh [X.Y.Z]
#
# Steps: bump the app version -> build the DMG -> commit everything -> tag ->
# push. The pushed tag triggers the GitHub Actions release workflow, which
# builds the DMG again in CI and creates the GitHub Release with the asset.
#
# Notes:
# - All uncommitted changes in the working tree are committed with the release
#   message, so commit or stash anything you do not want shipped first.
# - Requires the gh CLI (https://cli.github.com) authenticated as the repo
#   owner: brew install gh && gh auth login
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    read -r -p "版本号 (X.Y.Z，例如 0.2.0): " VERSION
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: 版本号格式应为 X.Y.Z，收到: $VERSION" >&2
    exit 1
fi
TAG="v$VERSION"

if ! command -v gh >/dev/null 2>&1; then
    echo "错误: 未安装 gh CLI，请先执行 brew install gh" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "错误: gh 未登录，请先执行 gh auth login" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "错误: 标签 $TAG 已存在，请换一个版本号或先删除旧标签" >&2
    exit 1
fi

echo "==> 更新版本号到 $VERSION (LoginItemInstaller.swift)"
sed -i '' \
    "s/\"CFBundleShortVersionString\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"CFBundleShortVersionString\": \"$VERSION\"/" \
    Sources/launchPadCore/LoginItemInstaller.swift

echo "==> 构建 DMG"
VERSION="$VERSION" bash dist/build_dmg.sh

echo "==> 提交代码与制品"
git add -A
git add -f dist/launchPad.dmg
if git diff --cached --quiet; then
    echo "没有需要提交的改动"
else
    git commit -m "chore: release $TAG"
fi

echo "==> 打标签 $TAG"
git tag -a "$TAG" -m "launchPad $VERSION"

echo "==> 推送 main 与标签"
git push origin main
git push origin "$TAG"

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

echo "==> 标签已推送;GitHub Actions 将自动构建 DMG 并创建 Release"
echo "完成: https://github.com/$REPO/releases/tag/$TAG"
