# Codex MCP Server (Rust)

A Rust implementation of the Model Context Protocol (MCP) server that wraps the [Codex CLI](https://github.com/openai/codex) for AI-assisted coding tasks.

## Features

- **MCP Protocol Support**: Full MCP server implementation using the `rmcp` library
- **Codex Integration**: Seamless integration with Codex CLI for AI-powered code generation
- **Session Persistence**: Resume conversations using `SESSION_ID`
- **Sandbox Policies**: Three security levels for safe code execution
  - `read-only`: Most secure, no file modifications (default)
  - `workspace-write`: Allow writing within the workspace
  - `danger-full-access`: Full system access (use with caution)
- **Cross-Platform**: Supports Windows, macOS, and Linux
- **Async Runtime**: Built on Tokio for efficient async I/O

## Prerequisites

- [Rust](https://rustup.rs/) 1.70+
- [Codex CLI](https://github.com/openai/codex) installed and available in PATH

## Installation

### From Source

```bash
git clone https://github.com/pdxxxx/codex-mcp-rust.git
cd codex-mcp-rust
cargo build --release
```

The binary will be available at `target/release/codex-mcp`.

## Usage

### Running the Server

```bash
./target/release/codex-mcp
```

The server communicates via stdio, making it compatible with MCP clients.

### Integration with Claude Code

```bash
claude mcp add codex -s user --transport stdio -- /path/to/codex-mcp
```

### Tool Parameters

The `codex` tool accepts the following parameters:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `PROMPT` | string | Yes | - | Task instruction to send to Codex |
| `cd` | path | Yes | - | Working directory for Codex execution |
| `sandbox` | string | No | `read-only` | Sandbox policy (`read-only`, `workspace-write`, `danger-full-access`) |
| `SESSION_ID` | string | No | - | Resume a previous session |
| `skip_git_repo_check` | bool | No | `true` | Allow running outside Git repositories |
| `return_all_messages` | bool | No | `false` | Return all messages including reasoning and tool calls |
| `image` | array | No | `[]` | Image files to attach to the prompt |
| `model` | string | No | - | Specific model to use |
| `yolo` | bool | No | `false` | Skip all approvals and sandboxing |
| `profile` | string | No | - | Configuration profile from `~/.codex/config.toml` |

### Example Response

```json
{
  "success": true,
  "SESSION_ID": "019bc4ce-610d-7f50-bd2a-fb5b8ac83b61",
  "agent_messages": "I've analyzed the code and found..."
}
```

## Configuration

### Environment Variables

- `RUST_LOG`: Set logging level (e.g., `debug`, `info`, `warn`, `error`)

```bash
RUST_LOG=debug ./target/release/codex-mcp
```

## Development

### Building

```bash
cargo build
```

### Testing

```bash
cargo test
```

### Linting

```bash
cargo clippy
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [rmcp](https://github.com/anthropics/rmcp) - Rust MCP SDK
- [Codex CLI](https://github.com/openai/codex) - OpenAI Codex CLI
