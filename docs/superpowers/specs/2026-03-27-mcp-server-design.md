# MCP Server Design

Add a hosted MCP (Model Context Protocol) server to the CompletionKit engine so that any Rails app mounting the engine automatically gets an MCP endpoint alongside the web UI and REST API. Targets IDE agents (Claude Code, Cursor, etc.) as primary clients.

## Transport — Streamable HTTP

The MCP spec's Streamable HTTP transport: clients send JSON-RPC 2.0 requests via HTTP POST, server responds with either `application/json` or `text/event-stream` (SSE).

Two routes added to the engine:

- `POST /mcp` — handles all MCP requests (initialize, tools/list, tools/call)
- `DELETE /mcp` — clears the session (spec requirement)

The actual URL prefix depends on where the host app mounts the engine (e.g., `/completion_kit/mcp` if mounted at `/completion_kit`).

Response format:
- Simple operations return `application/json` with a single JSON-RPC response.
- Long-running operations (`runs_generate`, `runs_judge`) return `text/event-stream` with progress events.

Auth: bearer token in the `Authorization` header, reusing `CompletionKit.config.api_token` — same token as the REST API.

## Architecture — Three layers

```
McpController (transport)
  -> McpDispatcher (JSON-RPC routing)
    -> McpTools::* (business logic)
```

### McpController

Lives at `app/controllers/completion_kit/mcp_controller.rb`. Inherits from `Api::V1::BaseController` to get bearer token auth via `authenticate_api!`. Has two actions:

- `handle` — parses the JSON-RPC request body, passes it to `McpDispatcher`, returns the response as JSON or SSE depending on the tool.
- `destroy` — clears the session from cache.

### McpDispatcher

Pure Ruby service at `app/services/completion_kit/mcp_dispatcher.rb`. No HTTP awareness. Takes a parsed JSON-RPC request hash, routes by `method`:

- `initialize` — returns server info, capabilities, and protocol version. Creates session.
- `notifications/initialized` — client acknowledgment, no-op.
- `tools/list` — returns all tool definitions with JSON Schema input schemas.
- `tools/call` — looks up tool by name, validates params, executes, returns result.

Returns JSON-RPC response hashes. Handles errors per the JSON-RPC 2.0 spec: method not found (-32601), invalid params (-32602), internal error (-32603).

### McpTools modules

One module per resource area under `app/services/completion_kit/mcp_tools/`. Each module defines tool metadata (name, description, input schema) and execution logic. Tools call existing ActiveRecord models and services directly — they do not go through the REST API.

## Tools — Full resource coverage

36 tools mirroring the full REST API surface. Naming convention: `resource_action`.

### Prompts
| Tool | Params | Description |
|------|--------|-------------|
| `prompts_list` | none | List all prompts |
| `prompts_get` | `id` | Get a prompt by ID |
| `prompts_create` | `name`, `description`, `template`, `llm_model` | Create a prompt |
| `prompts_update` | `id`, optional fields | Update a prompt |
| `prompts_delete` | `id` | Delete a prompt |
| `prompts_publish` | `id` | Publish a prompt version |
| `prompts_new_version` | `id` | Create a new version of a prompt |

### Runs
| Tool | Params | Description |
|------|--------|-------------|
| `runs_list` | none | List all runs |
| `runs_get` | `id` | Get a run by ID |
| `runs_create` | `name`, `prompt_id`, optional fields | Create a run |
| `runs_update` | `id`, optional fields | Update a run |
| `runs_delete` | `id` | Delete a run |
| `runs_generate` | `id` | Generate responses for a run (SSE progress) |
| `runs_judge` | `id` | Judge responses for a run (SSE progress) |

### Responses
| Tool | Params | Description |
|------|--------|-------------|
| `responses_list` | `run_id` | List responses for a run |
| `responses_get` | `run_id`, `id` | Get a specific response |

### Datasets
| Tool | Params | Description |
|------|--------|-------------|
| `datasets_list` | none | List all datasets |
| `datasets_get` | `id` | Get a dataset by ID |
| `datasets_create` | `name`, `csv_content` | Create a dataset |
| `datasets_update` | `id`, optional fields | Update a dataset |
| `datasets_delete` | `id` | Delete a dataset |

### Metrics
| Tool | Params | Description |
|------|--------|-------------|
| `metrics_list` | none | List all metrics |
| `metrics_get` | `id` | Get a metric by ID |
| `metrics_create` | `name`, `instruction` | Create a metric |
| `metrics_update` | `id`, optional fields | Update a metric |
| `metrics_delete` | `id` | Delete a metric |

### Criteria
| Tool | Params | Description |
|------|--------|-------------|
| `criteria_list` | none | List all criteria |
| `criteria_get` | `id` | Get a criteria by ID |
| `criteria_create` | `name`, `metric_ids` | Create a criteria |
| `criteria_update` | `id`, optional fields | Update a criteria |
| `criteria_delete` | `id` | Delete a criteria |

### Provider Credentials
| Tool | Params | Description |
|------|--------|-------------|
| `provider_credentials_list` | none | List all provider credentials |
| `provider_credentials_get` | `id` | Get a provider credential by ID |
| `provider_credentials_create` | `provider`, `api_key`, optional `api_endpoint` | Create a provider credential |
| `provider_credentials_update` | `id`, optional fields | Update a provider credential |
| `provider_credentials_delete` | `id` | Delete a provider credential |

Each tool defines a JSON Schema `inputSchema` describing required and optional parameters. Schemas mirror the strong params from the REST controllers.

## Session management

Minimal session handling to satisfy the MCP spec's initialize handshake requirement.

- On `initialize`: generate a UUID session ID, store in Rails cache with 1-hour TTL. Return session ID in `Mcp-Session-Id` response header along with server capabilities and protocol version (`2025-03-26`).
- On subsequent requests: validate `Mcp-Session-Id` header exists and is present in cache. Return JSON-RPC error if not.
- On `DELETE /mcp` with session header: remove session from cache.
- No user-specific state in the session. Auth is stateless via bearer token on every request. Session only gates the handshake requirement.

## Configuration

No new configuration. MCP reuses:

- `CompletionKit.config.api_token` for auth
- Existing model and service layer for all operations
- Rails cache for session storage

Host apps get MCP automatically when they mount the engine. Zero additional setup beyond having an API token configured.

## Testing

- **Request specs** for `McpController` — full HTTP flow: auth, initialize handshake, tools/list, tools/call for representative tools, session validation, SSE streaming for generate/judge.
- **Unit specs** for `McpDispatcher` — JSON-RPC routing, error codes (method not found, invalid params, missing session), initialize handshake.
- **Unit specs** for each `McpTools::*` module — tools call correct models/services, return properly formatted results, handle missing records.
- **SSE specs** for `runs_generate` and `runs_judge` — verify progress events are emitted.

Maintains 100% line and branch coverage.
