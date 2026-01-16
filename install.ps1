#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Repo = "pdxxxx/codex-mcp-rust"
$BinaryName = "codex-mcp"
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { "$env:LOCALAPPDATA\Programs\codex-mcp" }

function Get-LatestVersion {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    return $response.tag_name
}

function Main {
    Write-Host "==> 检测系统平台..."
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "x86" }
    Write-Host "    平台: windows-$arch"

    if ($arch -ne "amd64") {
        Write-Host "错误: 仅支持 64 位 Windows" -ForegroundColor Red
        exit 1
    }

    Write-Host "==> 获取最新版本..."
    try {
        $version = Get-LatestVersion
    } catch {
        Write-Host "错误: 无法获取最新版本" -ForegroundColor Red
        exit 1
    }
    Write-Host "    版本: $version"

    $assetName = "$BinaryName-windows-amd64.exe"
    $downloadUrl = "https://github.com/$Repo/releases/download/$version/$assetName"

    Write-Host "==> 下载 $assetName..."
    $tmpFile = [System.IO.Path]::GetTempFileName() + ".exe"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpFile -UseBasicParsing
    } catch {
        Write-Host "错误: 下载失败" -ForegroundColor Red
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
        exit 1
    }

    Write-Host "==> 安装到 $InstallDir..."
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $targetPath = Join-Path $InstallDir "$BinaryName.exe"
    Move-Item -Path $tmpFile -Destination $targetPath -Force

    Write-Host "==> 安装完成!" -ForegroundColor Green
    Write-Host ""
    Write-Host "二进制文件位置: $targetPath"
    Write-Host ""

    # 检查 PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$InstallDir*") {
        Write-Host "==> 添加到 PATH..."
        $newPath = "$userPath;$InstallDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$InstallDir"
        Write-Host "    已添加 $InstallDir 到用户 PATH"
        Write-Host ""
    }

    Write-Host "使用方法:"
    Write-Host "    $BinaryName"
    Write-Host ""
    Write-Host "集成到 Claude Code:"
    Write-Host "    claude mcp add codex -s user --transport stdio -- $targetPath"
    Write-Host ""
    Write-Host "提示: 请重新打开终端以使 PATH 生效" -ForegroundColor Yellow
}

Main
