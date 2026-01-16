#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Check,
    [string]$Dir,
    [switch]$Yes,
    [switch]$Help
)

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

function Get-CurrentVersion {
    param([string]$BinaryPath)

    if (Test-Path $BinaryPath) {
        try {
            $output = & $BinaryPath --version 2>&1
            if ($output -match 'v?(\d+\.\d+\.\d+)') {
                return $Matches[1]
            }
        } catch {}
        return "unknown"
    }
    return "未安装"
}

function Find-InstalledBinary {
    $searchPaths = @($DefaultInstallDir, "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles\codex-mcp", "$env:USERPROFILE\bin")

    foreach ($path in $searchPaths) {
        $binaryPath = Join-Path $path "$BinaryName.exe"
        if (Test-Path $binaryPath) {
            return $binaryPath
        }
    }

    # 检查 PATH
    $cmd = Get-Command $BinaryName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
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

function Show-Help {
    Write-Host "Codex MCP Server 安装/更新脚本"
    Write-Host ""
    Write-Host "用法: install.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Help           显示帮助信息"
    Write-Host "  -Update         更新到最新版本"
    Write-Host "  -Check          检查更新"
    Write-Host "  -Dir <路径>     指定安装目录"
    Write-Host "  -Yes            跳过确认提示"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\install.ps1              交互式安装"
    Write-Host "  .\install.ps1 -Update      更新到最新版本"
    Write-Host "  .\install.ps1 -Check       检查是否有新版本"
    Write-Host "  .\install.ps1 -Dir C:\bin -Yes  静默安装到指定目录"
}

function Invoke-Download {
    param(
        [string]$InstallDir,
        [string]$Version,
        [bool]$IsUpdate
    )

    $assetName = "$BinaryName-windows-amd64.exe"
    $downloadUrl = "https://github.com/$Repo/releases/download/$Version/$assetName"

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

    Write-Info "安装到 $InstallDir..."
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $binaryPath = Join-Path $InstallDir "$BinaryName.exe"

    # 如果是更新，先备份
    if ($IsUpdate -and (Test-Path $binaryPath)) {
        $backupPath = "$binaryPath.bak"
        Move-Item -Path $binaryPath -Destination $backupPath -Force
    }

    Move-Item -Path $tmpFile -Destination $binaryPath -Force

    # 删除备份
    Remove-Item -Path "$binaryPath.bak" -ErrorAction SilentlyContinue

    if ($IsUpdate) {
        Write-Success "更新完成: $binaryPath"
    } else {
        Write-Success "安装完成: $binaryPath"
    }

    return $binaryPath
}

function Invoke-CheckUpdate {
    Write-Info "检查更新..."

    try {
        $latestVersion = Get-LatestVersion
    } catch {
        Write-Err "无法获取最新版本"
        exit 1
    }

    $binaryPath = Find-InstalledBinary

    if (-not $binaryPath) {
        Write-Host "当前状态: 未安装"
        Write-Host "最新版本: $latestVersion"
        Write-Host ""
        Write-Host "运行 '.\install.ps1' 进行安装"
        return
    }

    $currentVersion = Get-CurrentVersion -BinaryPath $binaryPath
    Write-Host "安装路径: $binaryPath"
    Write-Host "当前版本: $currentVersion"
    Write-Host "最新版本: $latestVersion"
    Write-Host ""

    if ($currentVersion -eq $latestVersion) {
        Write-Success "已是最新版本"
    } else {
        Write-Warn "有新版本可用"
        Write-Host "运行 '.\install.ps1 -Update' 进行更新"
    }
}

function Invoke-Update {
    param(
        [string]$InstallDir,
        [bool]$SkipConfirm
    )

    Write-Info "检测系统平台..."
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "x86" }
    Write-Host "    平台: windows-$arch"

    if ($arch -ne "amd64") {
        Write-Err "仅支持 64 位 Windows"
        exit 1
    }

    Write-Info "获取最新版本..."
    try {
        $latestVersion = Get-LatestVersion
    } catch {
        Write-Err "无法获取最新版本"
        exit 1
    }
    Write-Host "    最新版本: $latestVersion"

    # 查找已安装的二进制
    $binaryPath = $null
    if ($InstallDir -and (Test-Path (Join-Path $InstallDir "$BinaryName.exe"))) {
        $binaryPath = Join-Path $InstallDir "$BinaryName.exe"
    } else {
        $binaryPath = Find-InstalledBinary
        if ($binaryPath) {
            $InstallDir = Split-Path $binaryPath -Parent
        }
    }

    if (-not $binaryPath) {
        Write-Warn "未找到已安装的 $BinaryName"
        if (-not $SkipConfirm) {
            if (Read-Confirm -Prompt "是否进行全新安装?" -Default $true) {
                Invoke-Install -InstallDir $InstallDir -SkipConfirm $SkipConfirm
            }
        }
        return
    }

    $currentVersion = Get-CurrentVersion -BinaryPath $binaryPath
    Write-Host "    当前版本: $currentVersion"
    Write-Host "    安装路径: $binaryPath"
    Write-Host ""

    if ($currentVersion -eq $latestVersion) {
        Write-Success "已是最新版本，无需更新"
        return
    }

    if (-not $SkipConfirm) {
        if (-not (Read-Confirm -Prompt "是否更新到 $latestVersion ?" -Default $true)) {
            Write-Host "已取消"
            return
        }
    }

    Invoke-Download -InstallDir $InstallDir -Version $latestVersion -IsUpdate $true
}

function Invoke-Install {
    param(
        [string]$InstallDir,
        [bool]$SkipConfirm
    )

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
    if (-not $InstallDir) {
        Write-Info "选择安装路径"
        $InstallDir = Read-UserInput -Prompt "安装目录" -Default $DefaultInstallDir
    }
    Write-Host ""

    # 检查是否已安装
    $binaryPath = Join-Path $InstallDir "$BinaryName.exe"
    $isUpdate = $false
    if (Test-Path $binaryPath) {
        $currentVersion = Get-CurrentVersion -BinaryPath $binaryPath
        Write-Warn "检测到已安装版本: $currentVersion"
        if (-not $SkipConfirm) {
            if (-not (Read-Confirm -Prompt "是否覆盖安装?" -Default $true)) {
                Write-Host "已取消"
                exit 0
            }
        }
        $isUpdate = $true
        Write-Host ""
    }

    # 下载安装
    $binaryPath = Invoke-Download -InstallDir $InstallDir -Version $version -IsUpdate $isUpdate
    Write-Host ""

    # 检查并添加 PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$InstallDir*") {
        if ($SkipConfirm -or (Read-Confirm -Prompt "是否将安装目录添加到 PATH 环境变量?" -Default $true)) {
            $newPath = "$userPath;$InstallDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            $env:Path = "$env:Path;$InstallDir"
            Write-Success "已添加到 PATH"
        } else {
            Write-Warn "$InstallDir 未添加到 PATH"
        }
        Write-Host ""
    }

    # 询问是否配置 Claude Code
    if (-not $SkipConfirm) {
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

# 主入口
if ($Help) {
    Show-Help
    exit 0
}

if ($Check) {
    Invoke-CheckUpdate
    exit 0
}

if ($Update) {
    Invoke-Update -InstallDir $Dir -SkipConfirm $Yes
    exit 0
}

Invoke-Install -InstallDir $Dir -SkipConfirm $Yes
