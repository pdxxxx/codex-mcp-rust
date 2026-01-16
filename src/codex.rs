//! Codex tool implementation for the MCP server.

use std::path::PathBuf;
use std::process::Stdio;

use rmcp::{
    handler::server::{tool::ToolRouter, wrapper::Parameters},
    model::{CallToolResult, Content, ServerCapabilities, ServerInfo},
    tool, tool_handler, tool_router, ErrorData as McpError,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::time::Duration;

use crate::error::CodexError;

/// Sandbox policy for model-generated commands.
#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
#[schemars(inline)]
pub enum SandboxPolicy {
    /// Read-only mode, most secure (default).
    #[default]
    ReadOnly,
    /// Allow writing within the workspace.
    WorkspaceWrite,
    /// Full access, use with caution.
    DangerFullAccess,
}

impl SandboxPolicy {
    fn as_str(&self) -> &'static str {
        match self {
            SandboxPolicy::ReadOnly => "read-only",
            SandboxPolicy::WorkspaceWrite => "workspace-write",
            SandboxPolicy::DangerFullAccess => "danger-full-access",
        }
    }
}

/// Parameters for the codex tool.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct CodexParams {
    /// Instruction for the task to send to codex.
    #[serde(rename = "PROMPT")]
    pub prompt: String,

    /// Set the workspace root for codex before executing the task.
    pub cd: PathBuf,

    /// Sandbox policy for model-generated commands. Defaults to `read-only`.
    #[serde(default)]
    pub sandbox: SandboxPolicy,

    /// Resume the specified session of the codex. Defaults to `None`, start a new session.
    #[serde(rename = "SESSION_ID", default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,

    /// Allow codex running outside a Git repository (useful for one-off directories).
    #[serde(default = "default_true")]
    pub skip_git_repo_check: bool,

    /// Return all messages (e.g. reasoning, tool calls, etc.) from the codex session.
    /// Set to `false` by default, only the agent's final reply message is returned.
    #[serde(default)]
    pub return_all_messages: bool,

    /// Attach one or more image files to the initial prompt.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub image: Vec<PathBuf>,

    /// The model to use for the codex session.
    /// This parameter is strictly prohibited unless explicitly specified by the user.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,

    /// Run every command without approvals or sandboxing.
    /// Only use when `sandbox` couldn't be applied.
    #[serde(default)]
    pub yolo: bool,

    /// Configuration profile name to load from `~/.codex/config.toml`.
    /// This parameter is strictly prohibited unless explicitly specified by the user.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
}

fn default_true() -> bool {
    true
}

/// Result returned by the codex tool.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct CodexResult {
    /// Whether the execution was successful.
    pub success: bool,

    /// Session ID for resuming the conversation.
    #[serde(rename = "SESSION_ID", skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,

    /// Agent's response messages.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_messages: Option<String>,

    /// Error message if execution failed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,

    /// All messages from the session (only included when return_all_messages is true).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub all_messages: Option<Vec<serde_json::Value>>,
}

/// The Codex MCP Server.
#[derive(Clone)]
pub struct CodexServer {
    tool_router: ToolRouter<Self>,
}

#[tool_router]
impl CodexServer {
    pub fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }

    /// Executes a non-interactive Codex session via CLI to perform AI-assisted coding tasks.
    ///
    /// This tool wraps the `codex exec` command, enabling model-driven code generation,
    /// debugging, or automation based on natural language prompts.
    /// It supports resuming ongoing sessions for continuity and enforces sandbox policies
    /// to prevent unsafe operations.
    #[tool(
        name = "codex",
        description = r#"Executes a non-interactive Codex session via CLI to perform AI-assisted coding tasks in a secure workspace.
This tool wraps the `codex exec` command, enabling model-driven code generation, debugging, or automation based on natural language prompts.
It supports resuming ongoing sessions for continuity and enforces sandbox policies to prevent unsafe operations. Ideal for integrating Codex into MCP servers for agentic workflows, such as code reviews or repo modifications.

**Key Features:**
    - **Prompt-Driven Execution:** Send task instructions to Codex for step-by-step code handling.
    - **Workspace Isolation:** Operate within a specified directory, with optional Git repo skipping.
    - **Security Controls:** Three sandbox levels balance functionality and safety.
    - **Session Persistence:** Resume prior conversations via `SESSION_ID` for iterative tasks.

**Edge Cases & Best Practices:**
    - Ensure `cd` exists and is accessible; tool fails silently on invalid paths.
    - For most repos, prefer "read-only" to avoid accidental changes.
    - If needed, set `return_all_messages` to `True` to parse "all_messages" for detailed tracing (e.g., reasoning, tool calls, etc.)."#
    )]
    pub async fn codex(
        &self,
        params: Parameters<CodexParams>,
    ) -> Result<CallToolResult, McpError> {
        let result = match self.execute_codex(params.0).await {
            Ok(r) => r,
            Err(e) => CodexResult {
                success: false,
                session_id: None,
                agent_messages: None,
                error: Some(e.to_string()),
                all_messages: None,
            },
        };

        let json_str = serde_json::to_string_pretty(&result)
            .unwrap_or_else(|_| format!("{:?}", result));

        Ok(CallToolResult::success(vec![Content::text(json_str)]))
    }
}

impl CodexServer {
    /// Execute the codex CLI command and process its output.
    async fn execute_codex(&self, params: CodexParams) -> Result<CodexResult, CodexError> {
        // Find the codex executable
        let codex_path = which::which("codex").map_err(|_| CodexError::ExecutableNotFound)?;

        // Fail fast with a clearer error than whatever the CLI might emit.
        if !params.cd.is_dir() {
            return Err(CodexError::InvalidWorkingDirectory(params.cd));
        }

        // Build command arguments
        let mut cmd = Command::new(&codex_path);
        cmd.kill_on_drop(true); // Ensure process is killed when dropped
        cmd.arg("exec")
            .arg("--sandbox")
            .arg(params.sandbox.as_str())
            .arg("--cd")
            .arg(&params.cd)
            .arg("--json");

        // Add optional arguments
        if !params.image.is_empty() {
            let images: Vec<String> = params.image.iter().map(|p| p.display().to_string()).collect();
            cmd.arg("--image").arg(images.join(","));
        }

        if let Some(ref model) = params.model {
            if !model.is_empty() {
                cmd.arg("--model").arg(model);
            }
        }

        if let Some(ref profile) = params.profile {
            if !profile.is_empty() {
                cmd.arg("--profile").arg(profile);
            }
        }

        if params.yolo {
            cmd.arg("--yolo");
        }

        if params.skip_git_repo_check {
            cmd.arg("--skip-git-repo-check");
        }

        // Handle session resumption
        if let Some(ref session_id) = params.session_id {
            if !session_id.is_empty() {
                cmd.arg("resume").arg(session_id);
            }
        }

        // Add the prompt (with Windows escaping if needed)
        let prompt = if cfg!(windows) {
            windows_escape(&params.prompt)
        } else {
            params.prompt.clone()
        };
        cmd.arg("--").arg(&prompt);

        // Configure process I/O
        // Use inherit for stderr to avoid buffer blocking issues
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit());

        // Avoid logging the full command line because it includes the prompt content.
        tracing::debug!(
            sandbox = params.sandbox.as_str(),
            cd = %params.cd.display(),
            has_session_id = params.session_id.is_some(),
            yolo = params.yolo,
            return_all_messages = params.return_all_messages,
            image_count = params.image.len(),
            "Executing codex"
        );

        // Spawn the process
        let mut child = cmd.spawn()?;
        let stdout = child
            .stdout
            .take()
            .ok_or(CodexError::StdoutCaptureFailed)?;
        let mut reader = BufReader::new(stdout).lines();

        // Process output - only collect all_messages if needed
        let mut all_messages: Option<Vec<serde_json::Value>> =
            params.return_all_messages.then_some(Vec::new());
        let mut agent_messages = String::new();
        let mut thread_id: Option<String> = None;
        let mut err_message = String::new();
        let mut success = true;

        while let Some(line) = reader.next_line().await? {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            match serde_json::from_str::<serde_json::Value>(line) {
                Ok(line_dict) => {
                    if let Some(all) = all_messages.as_mut() {
                        all.push(line_dict.clone());
                    }

                    // Extract agent messages
                    if let Some(item) = line_dict.get("item") {
                        if let Some(item_type) = item.get("type").and_then(|t| t.as_str()) {
                            if item_type == "agent_message" {
                                if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                    agent_messages.push_str(text);
                                }
                            }
                        }
                    }

                    // Extract thread_id
                    if let Some(tid) = line_dict.get("thread_id").and_then(|t| t.as_str()) {
                        thread_id = Some(tid.to_string());
                    }

                    // Check for failures
                    if let Some(msg_type) = line_dict.get("type").and_then(|t| t.as_str()) {
                        if msg_type.contains("fail") {
                            success = false;
                            if let Some(error) = line_dict.get("error") {
                                if let Some(error_msg) = error.get("message").and_then(|m| m.as_str())
                                {
                                    err_message.push_str("\n\n[codex error] ");
                                    err_message.push_str(error_msg);
                                }
                            }
                        }

                        if msg_type.contains("error") {
                            if let Some(error_msg) = line_dict.get("message").and_then(|m| m.as_str())
                            {
                                // Ignore "Reconnecting..." noise
                                if error_msg.starts_with("Reconnecting...") {
                                    continue;
                                }

                                success = false;
                                err_message.push_str("\n\n[codex error] ");
                                err_message.push_str(error_msg);
                            }
                        }

                        // Check for turn completion
                        if msg_type == "turn.completed" {
                            break;
                        }
                    }
                }
                Err(e) => {
                    success = false;
                    err_message.push_str("\n\n[json decode error] ");
                    err_message.push_str(&e.to_string());
                    err_message.push_str(": ");
                    err_message.push_str(line);
                }
            }
        }

        // Wait for process to finish with proper error handling
        let wait_timeout = Duration::from_secs(5);
        match tokio::time::timeout(wait_timeout, child.wait()).await {
            Ok(Ok(status)) => {
                if !status.success() {
                    success = false;
                    err_message.push_str("\n\n[codex exit] ");
                    err_message.push_str(&format!("{status:?}"));
                }
            }
            Ok(Err(e)) => {
                success = false;
                err_message.push_str("\n\n[codex wait error] ");
                err_message.push_str(&e.to_string());
            }
            Err(_) => {
                success = false;
                err_message.push_str("\n\n[codex wait timeout] ");
                err_message.push_str(&format!("{wait_timeout:?}"));
                let _ = child.kill().await;
                let _ = child.wait().await;
            }
        }

        // Validate results
        if thread_id.is_none() {
            success = false;
            err_message = format!(
                "Failed to get `SESSION_ID` from the codex session.\n\n{}",
                err_message
            );
        }

        if agent_messages.is_empty() {
            success = false;
            err_message = format!(
                "Failed to get `agent_messages` from the codex session.\n\nYou can try to set `return_all_messages` to `True` to get the full reasoning information. {}",
                err_message
            );
        }

        // Build result
        let result = if success {
            CodexResult {
                success: true,
                session_id: thread_id,
                agent_messages: Some(agent_messages),
                error: None,
                all_messages,
            }
        } else {
            CodexResult {
                success: false,
                session_id: thread_id,
                agent_messages: if agent_messages.is_empty() {
                    None
                } else {
                    Some(agent_messages)
                },
                error: Some(err_message),
                all_messages,
            }
        };

        Ok(result)
    }
}

#[tool_handler]
impl rmcp::ServerHandler for CodexServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: Default::default(),
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: rmcp::model::Implementation {
                name: "Codex MCP Server".into(),
                version: env!("CARGO_PKG_VERSION").into(),
                ..Default::default()
            },
            instructions: Some(
                "Codex MCP Server - AI-assisted coding tasks via the Codex CLI. \
                 Use the 'codex' tool to execute prompts in a secure sandbox environment."
                    .into(),
            ),
        }
    }
}

/// Escape special characters for Windows command line.
fn windows_escape(prompt: &str) -> String {
    prompt
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
        .replace('\x08', "\\b") // backspace
        .replace('\x0c', "\\f") // form feed
        .replace('\'', "\\'")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_windows_escape() {
        assert_eq!(windows_escape("hello"), "hello");
        assert_eq!(windows_escape("hello\nworld"), "hello\\nworld");
        assert_eq!(windows_escape("path\\to\\file"), "path\\\\to\\\\file");
        assert_eq!(windows_escape("say \"hello\""), "say \\\"hello\\\"");
    }

    #[test]
    fn test_sandbox_policy_as_str() {
        assert_eq!(SandboxPolicy::ReadOnly.as_str(), "read-only");
        assert_eq!(SandboxPolicy::WorkspaceWrite.as_str(), "workspace-write");
        assert_eq!(
            SandboxPolicy::DangerFullAccess.as_str(),
            "danger-full-access"
        );
    }
}
