import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { TOOLS, handleToolCall } from './lib/tools.js';

function getProjectRoot() {
  return process.env.TASK_SYSTEM_PROJECT_ROOT ?? process.cwd();
}

async function startMcpServer() {
  // --- Process-level error handling ---
  // Ignore SIGPIPE — standard for stdio servers (client may disconnect)
  process.on('SIGPIPE', () => { /* intentionally ignored */ });

  // Catch unhandled errors to prevent process crashes
  process.on('uncaughtException', (err) => {
    process.stderr.write(`task-system: uncaught exception: ${err}\n`);
  });
  process.on('unhandledRejection', (reason) => {
    process.stderr.write(`task-system: unhandled rejection: ${reason}\n`);
  });

  // Handle stdout write errors (EPIPE when client disconnects)
  process.stdout.on('error', (err) => {
    if (err.code === 'EPIPE') {
      process.exit(0);
    }
    process.stderr.write(`task-system: stdout error: ${err}\n`);
  });

  // Graceful shutdown on signals
  const shutdown = () => {
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // --- Server setup ---
  const server = new Server(
    { name: 'task-system', version: '1.0.0' },
    { capabilities: { tools: {} } }
  );

  // Transport lifecycle handlers
  server.onerror = (err) => {
    process.stderr.write(`task-system: server error: ${err}\n`);
  };
  server.onclose = () => {
    process.exit(0);
  };

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    const projectRoot = getProjectRoot();

    try {
      const result = await handleToolCall(name, args, projectRoot);
      return {
        content: [{ type: 'text', text: typeof result === 'string' ? result : JSON.stringify(result, null, 2) }],
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        content: [{ type: 'text', text: `Error: ${message}` }],
        isError: true,
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Detect client disconnect via stdin EOF
  process.stdin.on('end', () => {
    process.exit(0);
  });
}

startMcpServer().catch((err) => {
  process.stderr.write(`task-system: fatal: ${err}\n`);
  process.exit(1);
});
