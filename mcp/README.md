# Kaska MCP server

An [MCP](https://modelcontextprotocol.io) server that lets an agent read and
update a Kaska board over the REST API: list tasks, edit them, move them between
columns, and read/write comments.

It is a thin wrapper over `https://app.kaska.space/api/v1` (see the live docs at
`/api/docs`). The agent authenticates with a personal access token.

## Setup

```bash
cd mcp
pnpm install
pnpm build
```

Create a personal access token (until the settings UI ships, from an `iex`
session on the server):

```elixir
{:ok, plaintext, _token} = Kaska.ApiTokens.create_token(user, "my agent")
plaintext
```

## Configure your agent

Point your MCP client at the built server with the token in the environment.

Claude Code:

```bash
claude mcp add kaska \
  --env KASKA_TOKEN=kaska_pat_xxx \
  -- node /absolute/path/to/hardhat/mcp/dist/index.js
```

Claude Desktop / any client (`mcp.json`):

```json
{
  "mcpServers": {
    "kaska": {
      "command": "node",
      "args": ["/absolute/path/to/hardhat/mcp/dist/index.js"],
      "env": {
        "KASKA_TOKEN": "kaska_pat_xxx",
        "KASKA_API_URL": "https://app.kaska.space/api/v1"
      }
    }
  }
}
```

`KASKA_API_URL` is optional and defaults to `https://app.kaska.space/api/v1`.

## Tools

| Tool | What it does |
| --- | --- |
| `list_projects` | Discover accessible projects and their slugs. |
| `get_project` | Overview: `agent_instructions` + columns with descriptions. |
| `list_tasks` | All tasks (body, type, assignee, comments, attachments). |
| `get_task` | One task by id. |
| `update_task` | Change title, body (Markdown), assignee, type, dates. |
| `move_task` | Move a task into a column (workflow stage). |
| `list_comments` / `create_comment` | Read and post comments on a task. |
| `list_task_types` / `list_members` | Reference data for types and assignees. |

## Workflow conventions

Where a task should move next is a per-project convention, not hardcoded here.
Read `agent_instructions` (project) and each column's `description` via
`get_project` to learn the rules — e.g. "when you start a task in Todo, move it
to In Progress".
