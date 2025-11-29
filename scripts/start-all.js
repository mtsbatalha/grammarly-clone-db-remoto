#!/usr/bin/env node

/**
 * Grammarly Clone - Cross-platform Start Script
 * Works on Windows, Linux, and macOS
 *
 * Options:
 *   --clean, -c     Clean Docker cache before starting
 *   --rebuild, -r   Force rebuild containers
 *   --help, -h      Show help
 */

const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// Parse command line arguments
const args = process.argv.slice(2);
const options = {
  clean: args.includes('--clean') || args.includes('-c'),
  rebuild: args.includes('--rebuild') || args.includes('-r'),
  help: args.includes('--help') || args.includes('-h'),
};

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

const log = {
  info: (msg) => console.log(`${colors.green}[*]${colors.reset} ${msg}`),
  error: (msg) => console.log(`${colors.red}[ERROR]${colors.reset} ${msg}`),
  success: (msg) => console.log(`${colors.green}[OK]${colors.reset} ${msg}`),
  warn: (msg) => console.log(`${colors.yellow}[WARN]${colors.reset} ${msg}`),
};

const projectRoot = path.resolve(__dirname, '..');

function printHelp() {
  console.log(`
${colors.blue}Grammarly Clone - Start Script${colors.reset}

Usage: node start-all.js [options]

Options:
  ${colors.cyan}--clean, -c${colors.reset}     Stop containers, remove volumes, and clean Docker cache
  ${colors.cyan}--rebuild, -r${colors.reset}   Force rebuild containers (no cache)
  ${colors.cyan}--help, -h${colors.reset}      Show this help message

Examples:
  node start-all.js              # Normal start
  node start-all.js --clean      # Clean everything and start fresh
  node start-all.js --rebuild    # Rebuild containers without cache
`);
}

function printBanner() {
  console.log(`${colors.blue}`);
  console.log('===========================================');
  console.log('     Grammarly Clone - Starting...');
  console.log('===========================================');
  console.log(`${colors.reset}`);

  if (options.clean) {
    console.log(`${colors.yellow}  Mode: CLEAN (removing cache)${colors.reset}`);
  } else if (options.rebuild) {
    console.log(`${colors.yellow}  Mode: REBUILD (no cache)${colors.reset}`);
  }
  console.log('');
}

function checkDocker() {
  log.info('Checking Docker...');

  try {
    execSync('docker info', { stdio: 'pipe' });
    log.success('Docker is running');
    return true;
  } catch (error) {
    log.error('Docker is not running. Please start Docker first.');
    return false;
  }
}

function getDockerComposeCommand() {
  try {
    execSync('docker compose version', { stdio: 'pipe' });
    return 'docker compose';
  } catch (error) {
    try {
      execSync('docker-compose version', { stdio: 'pipe' });
      return 'docker-compose';
    } catch (error2) {
      log.error('Docker Compose not found.');
      return null;
    }
  }
}

function cleanDockerCache() {
  const dockerCompose = getDockerComposeCommand();
  if (!dockerCompose) {
    return false;
  }

  log.info('Stopping existing containers...');
  try {
    execSync(`${dockerCompose} -f docker-compose.dev.yml down -v --remove-orphans`, {
      cwd: projectRoot,
      stdio: 'inherit',
    });
  } catch (e) {
    // Ignore errors if containers don't exist
  }

  log.info('Removing Docker build cache...');
  try {
    execSync('docker builder prune -f', { cwd: projectRoot, stdio: 'inherit' });
  } catch (e) {
    log.warn('Could not prune builder cache');
  }

  log.info('Removing unused Docker images...');
  try {
    execSync('docker image prune -f', { cwd: projectRoot, stdio: 'inherit' });
  } catch (e) {
    log.warn('Could not prune images');
  }

  log.success('Docker cache cleaned');
  return true;
}

function startDockerServices() {
  log.info('Starting Docker services (PostgreSQL, Redis)...');

  const dockerCompose = getDockerComposeCommand();
  if (!dockerCompose) {
    return false;
  }
  log.info(`Using: ${dockerCompose}`);

  try {
    let cmd = `${dockerCompose} -f docker-compose.dev.yml up -d --remove-orphans`;

    if (options.rebuild || options.clean) {
      cmd += ' --build --force-recreate';
      if (options.clean) {
        cmd += ' --pull always';
      }
    }

    execSync(cmd, {
      cwd: projectRoot,
      stdio: 'inherit',
    });
    log.success('Docker services started');
    return true;
  } catch (error) {
    log.error('Failed to start Docker services');
    return false;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForServices() {
  log.info('Waiting for services to be ready...');

  // Wait for PostgreSQL
  let pgReady = false;
  for (let i = 0; i < 30; i++) {
    try {
      execSync('docker exec grammarly_postgres pg_isready -U postgres', {
        stdio: 'pipe',
      });
      pgReady = true;
      break;
    } catch (e) {
      await sleep(1000);
    }
  }

  if (pgReady) {
    log.success('PostgreSQL is ready');
  } else {
    log.error('PostgreSQL failed to start');
    return false;
  }

  // Wait for Redis
  let redisReady = false;
  for (let i = 0; i < 30; i++) {
    try {
      const result = execSync('docker exec grammarly_redis redis-cli ping', {
        stdio: 'pipe',
      }).toString();
      if (result.includes('PONG')) {
        redisReady = true;
        break;
      }
    } catch (e) {
      await sleep(1000);
    }
  }

  if (redisReady) {
    log.success('Redis is ready');
  } else {
    log.error('Redis failed to start');
    return false;
  }

  return true;
}

function checkEnv() {
  log.info('Checking environment configuration...');

  const envPath = path.join(projectRoot, 'apps', 'api', '.env');

  if (!fs.existsSync(envPath)) {
    log.error('.env file not found at apps/api/.env');
    console.log('Copy from .env.example and configure your settings');
    return false;
  }

  log.success('Environment configured');
  return true;
}

function startApplication() {
  log.info('Starting application...');

  console.log('');
  console.log(`${colors.green}===========================================`);
  console.log('  Application Starting!');
  console.log(`===========================================${colors.reset}`);
  console.log('');
  console.log(`  Web:  ${colors.cyan}http://localhost:5173${colors.reset}`);
  console.log(`  API:  ${colors.cyan}http://localhost:3003${colors.reset}`);
  console.log('');
  console.log(`  Press ${colors.yellow}Ctrl+C${colors.reset} to stop`);
  console.log('');

  // Start npm run dev
  const isWindows = process.platform === 'win32';
  const npmCmd = isWindows ? 'npm.cmd' : 'npm';

  const child = spawn(npmCmd, ['run', 'dev'], {
    cwd: projectRoot,
    stdio: 'inherit',
    shell: true,
  });

  child.on('error', (error) => {
    log.error(`Failed to start: ${error.message}`);
  });

  // Handle Ctrl+C
  process.on('SIGINT', () => {
    console.log('\n');
    log.info('Shutting down...');
    child.kill('SIGINT');
    process.exit(0);
  });
}

async function main() {
  // Show help and exit
  if (options.help) {
    printHelp();
    process.exit(0);
  }

  printBanner();

  if (!checkDocker()) {
    process.exit(1);
  }

  // Clean cache if requested
  if (options.clean) {
    if (!cleanDockerCache()) {
      process.exit(1);
    }
  }

  if (!startDockerServices()) {
    process.exit(1);
  }

  if (!(await waitForServices())) {
    process.exit(1);
  }

  if (!checkEnv()) {
    process.exit(1);
  }

  startApplication();
}

main();
