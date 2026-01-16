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

# 获取当前安装版本
get_current_version() {
    local binary_path="$1"
    if [ -x "$binary_path" ]; then
        # 尝试从二进制获取版本，如果失败则返回 unknown
        "$binary_path" --version 2>/dev/null | head -1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
    else
        echo "未安装"
    fi
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

# 显示帮助
show_help() {
    echo "Codex MCP Server 安装/更新脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help      显示帮助信息"
    echo "  -u, --update    更新到最新版本"
    echo "  -c, --check     检查更新"
    echo "  -d, --dir DIR   指定安装目录"
    echo "  -y, --yes       跳过确认提示"
    echo ""
    echo "示例:"
    echo "  $0              交互式安装"
    echo "  $0 -u           更新到最新版本"
    echo "  $0 -c           检查是否有新版本"
    echo "  $0 -d /usr/local/bin -y  静默安装到指定目录"
}

# 检查更新
check_update() {
    print_info "检查更新..."

    local latest_version=$(get_latest_version)
    if [ -z "$latest_version" ]; then
        print_error "无法获取最新版本"
        exit 1
    fi

    # 查找已安装的二进制
    local binary_path=""
    for dir in "$DEFAULT_INSTALL_DIR" "/usr/local/bin" "$HOME/bin"; do
        if [ -x "$dir/$BINARY_NAME" ]; then
            binary_path="$dir/$BINARY_NAME"
            break
        fi
    done

    if [ -z "$binary_path" ]; then
        echo "当前状态: 未安装"
        echo "最新版本: $latest_version"
        echo ""
        echo "运行 '$0' 进行安装"
        return
    fi

    local current_version=$(get_current_version "$binary_path")
    echo "安装路径: $binary_path"
    echo "当前版本: $current_version"
    echo "最新版本: $latest_version"
    echo ""

    if [ "$current_version" = "$latest_version" ]; then
        print_success "已是最新版本"
    else
        print_warn "有新版本可用"
        echo "运行 '$0 -u' 进行更新"
    fi
}

# 下载并安装
do_install() {
    local install_dir="$1"
    local platform="$2"
    local version="$3"
    local is_update="$4"

    local asset_name="${BINARY_NAME}-${platform}"
    local download_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"

    print_info "下载 ${asset_name}..."
    local tmp_file=$(mktemp)
    if ! curl -fsSL "$download_url" -o "$tmp_file" --progress-bar; then
        print_error "下载失败"
        rm -f "$tmp_file"
        exit 1
    fi

    print_info "安装到 ${install_dir}..."
    mkdir -p "$install_dir"
    local binary_path="${install_dir}/${BINARY_NAME}"

    # 如果是更新，先备份
    if [ "$is_update" = "true" ] && [ -f "$binary_path" ]; then
        mv "$binary_path" "${binary_path}.bak"
    fi

    mv "$tmp_file" "$binary_path"
    chmod +x "$binary_path"

    # 删除备份
    rm -f "${binary_path}.bak"

    if [ "$is_update" = "true" ]; then
        print_success "更新完成: ${binary_path}"
    else
        print_success "安装完成: ${binary_path}"
    fi
}

# 更新模式
do_update() {
    local install_dir="$1"
    local skip_confirm="$2"

    print_info "检测系统平台..."
    local platform=$(detect_platform)
    echo "    平台: ${platform}"

    print_info "获取最新版本..."
    local latest_version=$(get_latest_version)
    if [ -z "$latest_version" ]; then
        print_error "无法获取最新版本"
        exit 1
    fi
    echo "    最新版本: ${latest_version}"

    # 查找已安装的二进制
    local binary_path=""
    if [ -n "$install_dir" ] && [ -x "$install_dir/$BINARY_NAME" ]; then
        binary_path="$install_dir/$BINARY_NAME"
    else
        for dir in "$DEFAULT_INSTALL_DIR" "/usr/local/bin" "$HOME/bin"; do
            if [ -x "$dir/$BINARY_NAME" ]; then
                binary_path="$dir/$BINARY_NAME"
                install_dir="$dir"
                break
            fi
        done
    fi

    if [ -z "$binary_path" ]; then
        print_warn "未找到已安装的 $BINARY_NAME"
        if [ "$skip_confirm" != "true" ]; then
            if prompt_confirm "是否进行全新安装?" "y"; then
                main_install "$install_dir" "$skip_confirm"
            fi
        fi
        return
    fi

    local current_version=$(get_current_version "$binary_path")
    echo "    当前版本: ${current_version}"
    echo "    安装路径: ${binary_path}"
    echo ""

    if [ "$current_version" = "$latest_version" ]; then
        print_success "已是最新版本，无需更新"
        return
    fi

    if [ "$skip_confirm" != "true" ]; then
        if ! prompt_confirm "是否更新到 ${latest_version}?" "y"; then
            echo "已取消"
            return
        fi
    fi

    do_install "$install_dir" "$platform" "$latest_version" "true"
}

# 主安装流程
main_install() {
    local install_dir="$1"
    local skip_confirm="$2"

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
    if [ -z "$install_dir" ]; then
        print_info "选择安装路径"
        install_dir=$(prompt_input "安装目录" "$DEFAULT_INSTALL_DIR")
    fi
    install_dir="${install_dir/#\~/$HOME}"  # 展开 ~
    echo ""

    # 检查是否已安装
    local binary_path="${install_dir}/${BINARY_NAME}"
    local is_update="false"
    if [ -f "$binary_path" ]; then
        local current_version=$(get_current_version "$binary_path")
        print_warn "检测到已安装版本: ${current_version}"
        if [ "$skip_confirm" != "true" ]; then
            if ! prompt_confirm "是否覆盖安装?" "y"; then
                echo "已取消"
                exit 0
            fi
        fi
        is_update="true"
        echo ""
    fi

    # 下载安装
    do_install "$install_dir" "$platform" "$version" "$is_update"
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
    if [ "$skip_confirm" != "true" ]; then
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

# 解析参数
main() {
    local mode="install"
    local install_dir=""
    local skip_confirm="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -u|--update)
                mode="update"
                shift
                ;;
            -c|--check)
                mode="check"
                shift
                ;;
            -d|--dir)
                install_dir="$2"
                shift 2
                ;;
            -y|--yes)
                skip_confirm="true"
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    case $mode in
        install)
            main_install "$install_dir" "$skip_confirm"
            ;;
        update)
            do_update "$install_dir" "$skip_confirm"
            ;;
        check)
            check_update
            ;;
    esac
}

main "$@"
