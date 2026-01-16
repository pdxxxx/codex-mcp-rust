#!/bin/bash
set -e

REPO="pdxxxx/codex-mcp-rust"
BINARY_NAME="codex-mcp"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# 检测系统架构
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="macos" ;;
        *)       echo "错误: 不支持的操作系统"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             echo "错误: 不支持的架构 $(uname -m)"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# 获取最新版本
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

main() {
    echo "==> 检测系统平台..."
    local platform=$(detect_platform)
    echo "    平台: ${platform}"

    echo "==> 获取最新版本..."
    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        echo "错误: 无法获取最新版本"
        exit 1
    fi
    echo "    版本: ${version}"

    local asset_name="${BINARY_NAME}-${platform}"
    local download_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"

    echo "==> 下载 ${asset_name}..."
    local tmp_file=$(mktemp)
    if ! curl -fsSL "$download_url" -o "$tmp_file"; then
        echo "错误: 下载失败"
        rm -f "$tmp_file"
        exit 1
    fi

    echo "==> 安装到 ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    mv "$tmp_file" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

    echo "==> 安装完成!"
    echo ""
    echo "二进制文件位置: ${INSTALL_DIR}/${BINARY_NAME}"
    echo ""

    # 检查 PATH
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        echo "提示: ${INSTALL_DIR} 不在 PATH 中"
        echo "请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
        echo ""
        echo "    export PATH=\"\$PATH:${INSTALL_DIR}\""
        echo ""
    fi

    echo "使用方法:"
    echo "    ${BINARY_NAME}"
    echo ""
    echo "集成到 Claude Code:"
    echo "    claude mcp add codex -s user --transport stdio -- ${INSTALL_DIR}/${BINARY_NAME}"
}

main
