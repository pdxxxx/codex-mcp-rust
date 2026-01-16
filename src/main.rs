//! Codex MCP Server - Rust implementation
//!
//! A Model Context Protocol server that wraps the Codex CLI for AI-assisted coding tasks.

mod codex;
mod error;

use anyhow::Result;
use rmcp::{transport::stdio, ServiceExt};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::codex::CodexServer;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing with environment filter
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer().with_writer(std::io::stderr))
        .init();

    tracing::info!("Starting Codex MCP Server");

    let server = CodexServer::new();
    let service = server.serve(stdio()).await?;
    service.waiting().await?;

    Ok(())
}
