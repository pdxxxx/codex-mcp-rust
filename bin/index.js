#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const { spawnSync } = require('child_process');
const readline = require('readline');

const REPO = 'pdxxxx/codex-mcp-rust';
const BINARY_NAME = 'codex-mcp';
const VERSION_FILE = '.codex-mcp.version';
const USER_AGENT = 'codex-mcp-rust-npx-installer';

/**
 * 规范化版本号（去除 v 前缀）
 */
function normalizeVersion(version) {
  if (version == null) return '';
  return String(version).trim().replace(/^[vV]/, '');
}

/**
 * 解析语义化版本
 */
function semverParts(version) {
  const m = normalizeVersion(version).match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

/**
 * 比较两个版本号
 * @returns -1 if a < b, 0 if a == b, 1 if a > b, null if invalid
 */
function compareSemver(a, b) {
  const ap = semverParts(a);
  const bp = semverParts(b);
  if (!ap || !bp) return null;
  for (let i = 0; i < 3; i++) {
    if (ap[i] < bp[i]) return -1;
    if (ap[i] > bp[i]) return 1;
  }
  return 0;
}

/**
 * 获取默认安装目录
 */
function defaultInstallDir() {
  if (process.platform === 'win32') {
    const local = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    return path.join(local, 'Programs', BINARY_NAME);
  }
  return path.join(os.homedir(), '.local', 'bin');
}

/**
 * 获取二进制文件名
 */
function binaryFilename() {
  return process.platform === 'win32' ? `${BINARY_NAME}.exe` : BINARY_NAME;
}

/**
 * 分割 PATH 环境变量
 */
function splitPathEnv() {
  const sep = process.platform === 'win32' ? ';' : ':';
  return (process.env.PATH || '')
    .split(sep)
    .map((p) => p.trim())
    .filter(Boolean);
}

/**
 * 查找已安装的二进制文件
 */
function findInstalledBinary() {
  const filename = binaryFilename();
  const candidates = [];

  if (process.platform === 'win32') {
    const local = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    const programFiles = process.env.ProgramFiles || 'C:\\Program Files';
    candidates.push(path.join(local, 'Programs', BINARY_NAME, filename));
    candidates.push(path.join(local, 'Programs', filename));
    candidates.push(path.join(programFiles, BINARY_NAME, filename));
    candidates.push(path.join(os.homedir(), 'bin', filename));
  } else {
    candidates.push(path.join(os.homedir(), '.local', 'bin', filename));
    candidates.push(path.join('/usr/local/bin', filename));
    candidates.push(path.join('/usr/bin', filename));
  }

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }

  for (const dir of splitPathEnv()) {
    const p = path.join(dir, filename);
    if (fs.existsSync(p)) return p;
  }

  return null;
}

/**
 * 检测当前平台对应的资源名称
 */
function detectAssetName() {
  const platform = process.platform;
  const arch = process.arch;

  if (platform === 'linux') {
    if (arch === 'x64') return `${BINARY_NAME}-linux-amd64`;
    if (arch === 'arm64') return `${BINARY_NAME}-linux-arm64`;
  }

  if (platform === 'darwin') {
    if (arch === 'x64') return `${BINARY_NAME}-macos-amd64`;
    if (arch === 'arm64') return `${BINARY_NAME}-macos-arm64`;
  }

  if (platform === 'win32') {
    if (arch === 'ia32') throw new Error('仅支持 64 位 Windows');
    if (arch === 'arm64') {
      console.warn('==> 检测到 Windows ARM64，将安装 windows-amd64 版本（需系统支持 x64 仿真）');
    }
    return `${BINARY_NAME}-windows-amd64.exe`;
  }

  throw new Error(`不支持的平台/架构: ${platform}/${arch}`);
}

/**
 * 读取流数据
 */
function readStream(res) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve(Buffer.concat(chunks)));
    res.on('error', reject);
  });
}

/**
 * HTTP GET 请求
 */
function httpGet(url, headers) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { headers }, (res) => resolve(res));
    req.on('error', reject);
    req.end();
  });
}

/**
 * 获取 JSON 数据
 */
async function getJson(url) {
  const headers = {
    'User-Agent': USER_AGENT,
    Accept: 'application/vnd.github+json',
  };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const res = await httpGet(url, headers);
  if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
    res.resume();
    return getJson(res.headers.location);
  }

  const body = await readStream(res);
  if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
    throw new Error(`请求失败 (${res.statusCode}): ${body.toString('utf8')}`);
  }

  try {
    return JSON.parse(body.toString('utf8'));
  } catch (e) {
    throw new Error(`解析 JSON 失败: ${e.message}`);
  }
}

/**
 * 获取最新 Release 信息
 */
async function getLatestRelease() {
  return getJson(`https://api.github.com/repos/${REPO}/releases/latest`);
}

/**
 * 从 Release 中找到指定资源
 */
function pickAsset(release, assetName) {
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const asset = assets.find((a) => a && a.name === assetName);
  if (!asset || !asset.browser_download_url) {
    throw new Error(`在 Release ${release.tag_name} 中未找到资源: ${assetName}`);
  }
  return asset;
}

/**
 * 下载文件到指定路径
 */
async function downloadToFile(url, destPath) {
  const headers = { 'User-Agent': USER_AGENT };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  await new Promise((resolve, reject) => {
    https
      .get(url, { headers }, (res) => {
        if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          downloadToFile(res.headers.location, destPath).then(resolve, reject);
          return;
        }

        if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
          readStream(res)
            .then((body) => reject(new Error(`下载失败 (${res.statusCode}): ${body.toString('utf8')}`)))
            .catch(reject);
          return;
        }

        const file = fs.createWriteStream(destPath, { mode: 0o600 });
        res.pipe(file);
        file.on('finish', () => file.close(resolve));
        file.on('error', reject);
      })
      .on('error', reject);
  });
}

/**
 * 确保目录存在
 */
function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

/**
 * 设置文件可执行权限
 */
function makeExecutable(filePath) {
  if (process.platform === 'win32') return;
  fs.chmodSync(filePath, 0o755);
}

/**
 * 获取已安装版本（从版本文件读取）
 * 注意：不能调用 `codex-mcp --version`，因为该程序没有实现 --version 参数
 * 会启动 MCP server 等待 stdio 导致卡死
 */
function getCurrentVersion(binaryPath) {
  if (!binaryPath || !fs.existsSync(binaryPath)) return null;
  const installDir = path.dirname(binaryPath);
  const versionFile = path.join(installDir, VERSION_FILE);
  try {
    if (fs.existsSync(versionFile)) {
      return normalizeVersion(fs.readFileSync(versionFile, 'utf8').trim());
    }
  } catch {}
  // 如果版本文件不存在，返回 'unknown'（可能是旧版本安装或手动安装）
  return 'unknown';
}

/**
 * 保存已安装版本到版本文件
 */
function saveCurrentVersion(installDir, version) {
  const versionFile = path.join(installDir, VERSION_FILE);
  try {
    fs.writeFileSync(versionFile, normalizeVersion(version), 'utf8');
  } catch {}
}

/**
 * 从 Release 安装二进制文件
 */
async function installFromRelease(installDir, release, assetName) {
  ensureDir(installDir);

  const asset = pickAsset(release, assetName);
  const tmpPath = path.join(os.tmpdir(), `${assetName}.${Date.now()}.download`);

  console.log(`==> 下载 ${asset.name}...`);
  await downloadToFile(asset.browser_download_url, tmpPath);

  const targetPath = path.join(installDir, binaryFilename());
  const backupPath = `${targetPath}.bak`;

  if (fs.existsSync(targetPath)) {
    fs.copyFileSync(targetPath, backupPath);
  }

  try {
    console.log(`==> 安装到 ${targetPath}`);
    fs.copyFileSync(tmpPath, targetPath);
    makeExecutable(targetPath);
    fs.unlinkSync(tmpPath);
    if (fs.existsSync(backupPath)) fs.unlinkSync(backupPath);
    // 保存版本号到版本文件
    saveCurrentVersion(installDir, release.tag_name);
  } catch (err) {
    try {
      if (fs.existsSync(backupPath)) fs.copyFileSync(backupPath, targetPath);
    } catch {}
    throw err;
  }

  return targetPath;
}

/**
 * 打印 PATH 配置提示
 */
function printPathHint(installDir) {
  if (process.platform === 'win32') {
    console.log('');
    console.log(`提示: 如需在命令行直接运行 ${BINARY_NAME}，请将安装目录加入 PATH:`);
    console.log(`    ${installDir}`);
    return;
  }
  console.log('');
  console.log(`提示: 如需在命令行直接运行 ${BINARY_NAME}，请确保 ${installDir} 在 PATH 中。`);
  console.log(`    例如在 shell 配置中添加: export PATH="$PATH:${installDir}"`);
}

/**
 * 创建 readline 接口
 */
function createRl() {
  return readline.createInterface({ input: process.stdin, output: process.stdout });
}

/**
 * 询问用户
 */
function ask(rl, q) {
  return new Promise((resolve) => rl.question(q, resolve));
}

/**
 * 询问文本输入
 */
async function askText(rl, promptText, defaultValue) {
  const suffix = defaultValue ? ` [${defaultValue}]` : '';
  const ans = (await ask(rl, `${promptText}${suffix}: `)).trim();
  return ans || defaultValue || '';
}

/**
 * 询问确认
 */
async function askConfirm(rl, promptText, defaultYes = true) {
  const suffix = defaultYes ? '[Y/n]' : '[y/N]';
  const ans = (await ask(rl, `${promptText} ${suffix}: `)).trim().toLowerCase();
  if (!ans) return defaultYes;
  return ans === 'y' || ans === 'yes';
}

/**
 * 安装操作
 */
async function doInstall(rl) {
  const assetName = detectAssetName();
  const release = await getLatestRelease();
  const latestVersion = normalizeVersion(release.tag_name);

  const installDir = await askText(rl, '安装目录', defaultInstallDir());
  const targetPath = path.join(installDir, binaryFilename());

  if (fs.existsSync(targetPath)) {
    const ok = await askConfirm(rl, `检测到已存在 ${targetPath}，是否覆盖安装?`, true);
    if (!ok) return;
  }

  const binaryPath = await installFromRelease(installDir, release, assetName);
  console.log(`==> 安装完成: ${binaryPath} (v${latestVersion})`);
  printPathHint(installDir);
}

/**
 * 更新操作
 */
async function doUpdate(rl) {
  const installed = findInstalledBinary();
  if (!installed) {
    console.log(`==> 未找到已安装的 ${BINARY_NAME}，请先执行安装。`);
    return;
  }

  const current = getCurrentVersion(installed) || 'unknown';
  const assetName = detectAssetName();
  const release = await getLatestRelease();
  const latest = normalizeVersion(release.tag_name);

  console.log(`==> 当前版本: ${current}`);
  console.log(`==> 最新版本: ${latest}`);

  const cmp = compareSemver(current, latest);
  if (cmp === 0) {
    console.log('==> 已是最新版本，无需更新');
    return;
  }

  const ok = await askConfirm(rl, `是否更新到 v${latest}?`, true);
  if (!ok) return;

  const installDir = path.dirname(installed);
  const binaryPath = await installFromRelease(installDir, release, assetName);
  console.log(`==> 更新完成: ${binaryPath} (v${latest})`);
}

/**
 * 检查更新操作
 */
async function doCheckUpdate() {
  const installed = findInstalledBinary();
  const current = installed ? getCurrentVersion(installed) || 'unknown' : '未安装';

  const release = await getLatestRelease();
  const latest = normalizeVersion(release.tag_name);

  console.log(`==> 当前版本: ${current}`);
  console.log(`==> 最新版本: ${latest}`);

  const cmp = compareSemver(current, latest);
  if (installed && cmp === 0) {
    console.log('==> 已是最新版本');
    return;
  }
  if (!installed) {
    console.log('==> 未安装，可选择"安装"进行安装');
    return;
  }
  console.log('==> 存在更新，可选择"更新"进行更新');
}

/**
 * 配置 Claude Code 操作
 * 注意：避免使用 shell: true 以防止命令注入风险
 */
async function doConfigureClaude() {
  const installed = findInstalledBinary();
  if (!installed) {
    console.log(`==> 未找到已安装的 ${BINARY_NAME}`);
    return;
  }

  const args = ['mcp', 'add', 'codex', '-s', 'user', '--transport', 'stdio', '--', installed];
  console.log(`==> 执行: claude ${args.join(' ')}`);

  // Windows 上需要查找 claude.cmd，避免使用 shell: true 防止命令注入
  let claudeCmd = 'claude';
  if (process.platform === 'win32') {
    // 尝试使用 where 命令查找 claude
    const whereResult = spawnSync('where', ['claude'], { encoding: 'utf8' });
    if (whereResult.status === 0 && whereResult.stdout) {
      const paths = whereResult.stdout.trim().split('\n');
      if (paths.length > 0) {
        claudeCmd = paths[0].trim();
      }
    }
  }

  const res = spawnSync(claudeCmd, args, {
    stdio: 'inherit',
  });

  if (res.error) {
    console.log('==> 未找到 claude 命令，请手动执行:');
    console.log(`    claude ${args.join(' ')}`);
    return;
  }
  if (res.status !== 0) {
    console.log(`==> 配置失败 (exit code: ${res.status})，请手动执行:`);
    console.log(`    claude ${args.join(' ')}`);
    return;
  }
  console.log('==> 已添加到 Claude Code 配置');
}

/**
 * 卸载操作
 */
async function doUninstall(rl) {
  const installed = findInstalledBinary();
  if (!installed) {
    console.log(`==> 未找到已安装的 ${BINARY_NAME}`);
    return;
  }

  const ok = await askConfirm(rl, `确认卸载并删除 ${installed}?`, false);
  if (!ok) return;

  try {
    fs.unlinkSync(installed);
    console.log('==> 已卸载');
  } catch (err) {
    console.error(`错误: 卸载失败: ${err.message}`);
  }
}

/**
 * 主函数
 */
async function main() {
  const rl = createRl();
  try {
    console.log('');
    console.log('+----------------------------------------+');
    console.log('|     Codex MCP Server 安装器 (npm)      |');
    console.log('+----------------------------------------+');
    console.log('');

    const assetName = detectAssetName();
    console.log(`仓库: ${REPO}`);
    console.log(`目标资源: ${assetName}`);
    console.log(`默认安装目录: ${defaultInstallDir()}`);
    console.log('');

    console.log('1. 安装');
    console.log('2. 更新');
    console.log('3. 检查更新');
    console.log('4. 配置 Claude Code');
    console.log('5. 卸载');
    console.log('');

    const choice = (await ask(rl, '请选择 [1-5]: ')).trim();
    console.log('');

    switch (choice) {
      case '1':
        await doInstall(rl);
        break;
      case '2':
        await doUpdate(rl);
        break;
      case '3':
        await doCheckUpdate();
        break;
      case '4':
        await doConfigureClaude();
        break;
      case '5':
        await doUninstall(rl);
        break;
      default:
        console.log('==> 已取消');
        break;
    }
  } finally {
    rl.close();
  }
}

main().catch((err) => {
  console.error(`错误: ${err && err.message ? err.message : String(err)}`);
  process.exit(1);
});
