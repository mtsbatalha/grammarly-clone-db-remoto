#!/usr/bin/env node

/**
 * Grammarly Clone - Cross-platform Start Script
 * Works on Windows, Linux, and macOS
 */

const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

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

function printBanner() {
  console.log(`${colors.blue}`);
  console.log('===========================================');
  console.log('     Grammarly Clone - Starting...');
  console.log('===========================================');
  console.log(`${colors.reset}`);
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

function startDockerServices() {
  log.info('Starting Docker services (PostgreSQL, Redis)...');

  try {
    execSync('docker-compose -f docker-compose.dev.yml up -d', {
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
  printBanner();

  if (!checkDocker()) {
    process.exit(1);
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
