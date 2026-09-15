import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema, ListResourcesRequestSchema, ReadResourceRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { RpcClient } from './transport.js';
import { tools } from './schema.js';
import { Service } from './service.js';

export async function startMcp() {
  const rpc = await RpcClient.open();
  const service = new Service(rpc);
  const server = new Server({ name: 'vim9-mcp', version: '0.1.0' }, { capabilities: { tools: {}, resources: {} }, instructions: 'Use explicit session IDs. Read live buffers before editing. Search returns revisioned locations. Prepare changes before apply; saves are explicit. On stale_revision reread and replan. On timeout inspect request_status; never blindly replay a mutation. Providers are user configured. Arbitrary Ex and macros have weaker guarantees.' });
  server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: tools.map(({ name, description, inputSchema, mutation }) => ({ name, description, inputSchema, annotations: { readOnlyHint: !mutation, destructiveHint: mutation, idempotentHint: !mutation, openWorldHint: ['execute_ex', 'execute_macro', 'invoke_provider', 'start_job', 'run_workflow'].includes(name) } })) }));
  server.setRequestHandler(CallToolRequestSchema, async (request, extra) => {
    try {
      const result = await service.execute(request.params.name, request.params.arguments || {}, { signal: extra.signal });
      return { content: [{ type: 'text', text: JSON.stringify(result) }], structuredContent: result, isError: !result.ok };
    } catch (error) {
      const result = { ok: false, code: 'invalid_request', message: error.message };
      return { content: [{ type: 'text', text: JSON.stringify(result) }], structuredContent: result, isError: true };
    }
  });
  server.setRequestHandler(ListResourcesRequestSchema, async () => {
    const result = await rpc.call('list_sessions');
    return { resources: [{ uri: 'vim9://sessions', name: 'Live Vim sessions', mimeType: 'application/json' }, ...result.sessions.map(s => ({ uri: `vim9://session/${s.id}/context`, name: `Vim ${s.pid}: ${s.cwd}`, mimeType: 'application/json' }))] };
  });
  server.setRequestHandler(ReadResourceRequestSchema, async request => {
    const uri = request.params.uri;
    const match = /^vim9:\/\/session\/([a-f0-9-]+)\/context$/.exec(uri);
    const result = uri === 'vim9://sessions' ? await rpc.call('list_sessions') : match ? await service.execute('get_context', { session: match[1] }) : { ok: false, code: 'unknown_resource' };
    return { contents: [{ uri, mimeType: 'application/json', text: JSON.stringify(result) }] };
  });
  server.onclose = () => rpc.close();
  process.stdin.once('end', () => { void server.close(); });
  process.once('SIGTERM', () => { void server.close(); });
  await server.connect(new StdioServerTransport());
  return server;
}
