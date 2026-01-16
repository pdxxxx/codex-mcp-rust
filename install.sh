#!/bin/bash
set -e

REPO="pdxxxx/codex-mcp-rust"
BINARY_NAME="codex-mcp"
DEFAULT_INSTALL_DIR="$HOME/.local/bin"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}==>${NC} $1"; }
print_warn() { echo -e "${YELLOW}==>${NC} $1"; }
print_error() { echo -e "${RED}错误:${NC} $1"; }

# 检测系统架构
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="macos" ;;
        *)       print_error "不支持的操作系统"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             print_error "不支持的架构 $(uname -m)"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# 获取最新版本
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 读取用户输入
prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$prompt: " result
        echo "$result"
    fi
}

# 确认提示
prompt_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local result

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " result
        result="${result:-y}"
    else
        read -p "$prompt [y/N]: " result
        result="${result:-n}"
    fi

    [[ "$result" =~ ^[Yy]$ ]]
}

main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Codex MCP Server 安装程序          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # 检测平台
    print_info "检测系统平台..."
    local platform=$(detect_platform)
    echo "    平台: ${platform}"

    # 获取版本
    print_info "获取最新版本..."
    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        print_error "无法获取最新版本"
        exit 1
    fi
    echo "    版本: ${version}"
    echo ""

    # 选择安装路径
    print_info "选择安装路径"
    local install_dir=$(prompt_input "安装目录" "$DEFAULT_INSTALL_DIR")
    install_dir="${install_dir/#\~/$HOME}"  # 展开 ~
    echo ""

    # 下载
    local asset_name="${BINARY_NAME}-${platform}"
    local download_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"

    print_info "下载 ${asset_name}..."
    local tmp_file=$(mktemp)
    if ! curl -fsSL "$download_url" -o "$tmp_file" --progress-bar; then
        print_error "下载失败"
        rm -f "$tmp_file"
        exit 1
    fi

    # 安装
    print_info "安装到 ${install_dir}..."
    mkdir -p "$install_dir"
    local binary_path="${install_dir}/${BINARY_NAME}"
    mv "$tmp_file" "$binary_path"
    chmod +x "$binary_path"
    print_success "二进制文件已安装到: ${binary_path}"
    echo ""

    # 检查 PATH
    if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
        print_warn "${install_dir} 不在 PATH 中"
        echo "    请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
        echo ""
        echo "    export PATH=\"\$PATH:${install_dir}\""
        echo ""
    fi

    # 询问是否配置 Claude Code
    if prompt_confirm "是否将 codex-mcp 添加到 Claude Code 配置中?" "y"; then
        echo ""
        print_info "配置 Claude Code..."

        if command -v claude &> /dev/null; then
            if claude mcp add codex -s user --transport stdio -- "$binary_path" 2>/dev/null; then
                print_success "已添加到 Claude Code 配置"
            else
                print_warn "添加失败，请手动执行:"
                echo "    claude mcp add codex -s user --transport stdio -- $binary_path"
            fi
        else
            print_warn "未找到 claude 命令，请手动配置:"
            echo "    claude mcp add codex -s user --transport stdio -- $binary_path"
        fi
    fi

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║           安装完成!                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "使用方法:"
    echo "    ${BINARY_NAME}"
    echo ""
}

main
