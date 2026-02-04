# Codex MCP Server (Rust)

一个用 Rust 实现的 Model Context Protocol (MCP) 服务器，封装了 [Codex CLI](https://github.com/openai/codex) 以提供 AI 辅助编码功能。

## 功能特性

- **MCP 协议支持**: 基于 `rmcp` 库的完整 MCP 服务器实现
- **Codex 集成**: 与 Codex CLI 无缝集成，提供 AI 驱动的代码生成
- **会话持久化**: 通过 `SESSION_ID` 恢复对话
- **沙箱策略**: 三种安全级别保障代码执行安全
  - `read-only`: 最安全，禁止文件修改（默认）
  - `workspace-write`: 允许在工作区内写入
  - `danger-full-access`: 完全访问权限（谨慎使用）
- **跨平台**: 支持 Windows、macOS 和 Linux
- **异步运行时**: 基于 Tokio 构建，高效异步 I/O

## 前置要求

- [Codex CLI](https://github.com/openai/codex) 已安装并添加到 PATH

## 安装

### 一键安装（推荐）

使用 npx 运行交互式安装器（支持 Windows、macOS、Linux）：

```bash
npx codex-mcp-rust@latest
```

该命令会自动检测平台/架构并下载 GitHub Release 的二进制文件，提供以下交互式操作：
1. 安装
2. 更新
3. 检查更新
4. 配置 Claude Code
5. 卸载

### 手动下载

从 [GitHub Releases](https://github.com/pdxxxx/codex-mcp-rust/releases) 下载对应平台的二进制文件：

| 平台 | 文件名 |
|------|--------|
| Linux AMD64 | `codex-mcp-linux-amd64` |
| Linux ARM64 | `codex-mcp-linux-arm64` |
| Windows AMD64 | `codex-mcp-windows-amd64.exe` |
| macOS AMD64 | `codex-mcp-macos-amd64` |
| macOS ARM64 | `codex-mcp-macos-arm64` |

### 从源码构建

```bash
git clone https://github.com/pdxxxx/codex-mcp-rust.git
cd codex-mcp-rust
cargo build --release
```

二进制文件位于 `target/release/codex-mcp`。

## 使用方法

### 运行服务器

```bash
codex-mcp
```

服务器通过 stdio 通信，兼容所有 MCP 客户端。

### 集成到 Claude Code

```bash
claude mcp add codex -s user --transport stdio -- /path/to/codex-mcp
```

### 工具参数

`codex` 工具接受以下参数：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `PROMPT` | string | 是 | - | 发送给 Codex 的任务指令 |
| `cd` | path | 是 | - | Codex 执行的工作目录 |
| `sandbox` | string | 否 | `read-only` | 沙箱策略 |
| `SESSION_ID` | string | 否 | - | 恢复之前的会话 |
| `skip_git_repo_check` | bool | 否 | `true` | 允许在非 Git 仓库中运行 |
| `return_all_messages` | bool | 否 | `false` | 返回所有消息（包括推理和工具调用） |
| `image` | array | 否 | `[]` | 附加到提示的图片文件 |
| `model` | string | 否 | - | 指定使用的模型 |
| `yolo` | bool | 否 | `false` | 跳过所有审批和沙箱 |
| `profile` | string | 否 | - | `~/.codex/config.toml` 中的配置文件名 |

> 注：为兼容部分 MCP 客户端，`bool` 类型参数也支持传入字符串 `"true"`/`"false"`（大小写不敏感）。

### 响应示例

```json
{
  "success": true,
  "SESSION_ID": "019bc4ce-610d-7f50-bd2a-fb5b8ac83b61",
  "agent_messages": "我已分析代码并发现..."
}
```

## 配置

### 环境变量

- `RUST_LOG`: 设置日志级别（如 `debug`、`info`、`warn`、`error`）

```bash
RUST_LOG=debug codex-mcp
```

## 开发

### 构建

```bash
cargo build
```

### 测试

```bash
cargo test
```

### 代码检查

```bash
cargo clippy
```

## 许可证

MIT License

## 致谢

- [codexmcp](https://github.com/GuDaStudio/codexmcp) - 感谢GuDaStudio提供参考
- [rmcp](https://github.com/anthropics/rmcp) - Rust MCP SDK
- [Codex CLI](https://github.com/openai/codex) - OpenAI Codex CLI
