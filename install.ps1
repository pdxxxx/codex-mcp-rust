#Requires -Version 5.1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Repo = "pdxxxx/codex-mcp-rust"
$BinaryName = "codex-mcp"
$DefaultInstallDir = "$env:LOCALAPPDATA\Programs\codex-mcp"

function Write-Info { param($Message) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Message }
function Write-Success { param($Message) Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warn { param($Message) Write-Host "==> " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Err { param($Message) Write-Host "错误: " -ForegroundColor Red -NoNewline; Write-Host $Message }

function Get-LatestVersion {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    return $response.tag_name
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [string]$Default
    )

    if ($Default) {
        $result = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
        return $result
    } else {
        return Read-Host $Prompt
    }
}

function Read-Confirm {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $result = Read-Host "$Prompt $suffix"

    if ([string]::IsNullOrWhiteSpace($result)) {
        return $Default
    }

    return $result -match "^[Yy]"
}

function Main {
    Write-Host ""
    Write-Host "+-----------------------------------------+" -ForegroundColor Cyan
    Write-Host "|     Codex MCP Server 安装程序           |" -ForegroundColor Cyan
    Write-Host "+-----------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    # 检测平台
    Write-Info "检测系统平台..."
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "x86" }
    Write-Host "    平台: windows-$arch"

    if ($arch -ne "amd64") {
        Write-Err "仅支持 64 位 Windows"
        exit 1
    }

    # 获取版本
    Write-Info "获取最新版本..."
    try {
        $version = Get-LatestVersion
    } catch {
        Write-Err "无法获取最新版本"
        exit 1
    }
    Write-Host "    版本: $version"
    Write-Host ""

    # 选择安装路径
    Write-Info "选择安装路径"
    $installDir = Read-UserInput -Prompt "安装目录" -Default $DefaultInstallDir
    Write-Host ""

    # 下载
    $assetName = "$BinaryName-windows-amd64.exe"
    $downloadUrl = "https://github.com/$Repo/releases/download/$version/$assetName"

    Write-Info "下载 $assetName..."
    $tmpFile = [System.IO.Path]::GetTempFileName() + ".exe"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpFile -UseBasicParsing
        $ProgressPreference = 'Continue'
    } catch {
        Write-Err "下载失败: $_"
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
        exit 1
    }

    # 安装
    Write-Info "安装到 $installDir..."
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    $binaryPath = Join-Path $installDir "$BinaryName.exe"
    Move-Item -Path $tmpFile -Destination $binaryPath -Force
    Write-Success "二进制文件已安装到: $binaryPath"
    Write-Host ""

    # 检查并添加 PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$installDir*") {
        if (Read-Confirm -Prompt "是否将安装目录添加到 PATH 环境变量?" -Default $true) {
            $newPath = "$userPath;$installDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            $env:Path = "$env:Path;$installDir"
            Write-Success "已添加到 PATH"
        } else {
            Write-Warn "$installDir 未添加到 PATH"
        }
        Write-Host ""
    }

    # 询问是否配置 Claude Code
    if (Read-Confirm -Prompt "是否将 codex-mcp 添加到 Claude Code 配置中?" -Default $true) {
        Write-Host ""
        Write-Info "配置 Claude Code..."

        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($claudeCmd) {
            try {
                $output = & claude mcp add codex -s user --transport stdio -- $binaryPath 2>&1
                Write-Success "已添加到 Claude Code 配置"
            } catch {
                Write-Warn "添加失败，请手动执行:"
                Write-Host "    claude mcp add codex -s user --transport stdio -- $binaryPath"
            }
        } else {
            Write-Warn "未找到 claude 命令，请手动配置:"
            Write-Host "    claude mcp add codex -s user --transport stdio -- $binaryPath"
        }
    }

    Write-Host ""
    Write-Host "+-----------------------------------------+" -ForegroundColor Green
    Write-Host "|           安装完成!                     |" -ForegroundColor Green
    Write-Host "+-----------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Host "使用方法:"
    Write-Host "    $BinaryName"
    Write-Host ""
    Write-Host "提示: 请重新打开终端以使 PATH 生效" -ForegroundColor Yellow
    Write-Host ""
}

Main
