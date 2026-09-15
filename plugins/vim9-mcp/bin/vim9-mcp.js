#!/usr/bin/env node
import { startBroker } from '../src/broker.js';
import { ensureBroker } from '../src/transport.js';

try {
  const mode = process.argv[2] || 'stdio';
  if (mode === 'broker') await startBroker();
  else if (mode === 'ensure') await ensureBroker();
  else if (mode === 'stdio') { const { startMcp } = await import('../src/mcp.js'); await startMcp(); }
  else { console.error('Usage: vim9-mcp [stdio|broker|ensure]'); process.exitCode = 1; }
} catch (error) { console.error(error.message); process.exitCode = 1; }
