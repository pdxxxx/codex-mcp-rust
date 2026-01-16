//! Error types for the Codex MCP server.

use std::path::PathBuf;
use thiserror::Error;

/// Errors that can occur during Codex execution.
#[derive(Debug, Error)]
pub enum CodexError {
    /// Failed to find the codex executable.
    #[error("Codex executable not found. Please ensure 'codex' is installed and in PATH.")]
    ExecutableNotFound,

    /// Working directory does not exist or is not a directory.
    #[error("Working directory does not exist or is not a directory: {0:?}")]
    InvalidWorkingDirectory(PathBuf),

    /// Failed to capture stdout from the codex process.
    #[error("Failed to capture codex stdout (pipe not available).")]
    StdoutCaptureFailed,

    /// I/O error while running the codex process (spawn, read, wait, kill, etc.).
    #[error("I/O error while running codex: {0}")]
    Io(#[from] std::io::Error),

    /// Failed to parse JSON output from codex.
    #[error("Failed to parse JSON: {0}")]
    JsonParseError(#[from] serde_json::Error),
}
