# Clerk Runner

External process for autonomous agent event processing. Runs alongside agent processes, long-polls for events, processes them with an LLM, and posts responses as comments.

## Architecture

Based on the design from Шкипер's review:
- External clerk-runner next to the agent process (not server-side GenServer)
- PATs stay with the agent, never on the server
- Stable event contract: event id, type, project/task/comment ids, author, inserted_at
- Idempotency via processed event IDs stored locally
- Crash before ack → redelivery; restart doesn't duplicate answers

## Configuration

Create `clerks.yml` in the working directory:

```yaml
AgentName:
  token: kaska_pat_xxx
  model: gpt-4o
  system_prompt: "Optional custom system prompt"
```

## Environment Variables

- `KASKA_API_URL` — API base URL (default: `https://app.kaska.space/api/v1`)
- `CLERKS_CONFIG` — path to clerks.yml (default: `./clerks.yml`)
- `STATE_DIR` — directory for processed event state (default: `./.clerk-state`)
- `OPENAI_API_KEY` — API key for LLM calls

## How It Works

1. Reads clerks.yml config
2. For each clerk, starts a long-poll loop on `/agent/events`
3. On receiving an event:
   - Fetches full context: project (with agent_instructions), task, comments thread
   - Builds a prompt with event type, context, and instructions
   - Calls the configured LLM model
   - Posts the response as a comment on the task (or acks without comment if empty)
   - Acknowledges the event
4. Idempotency: processed event IDs stored in `.clerk-state/<name>.json`
5. On crash/restart: resumes from last cursor, skips already-processed events
6. Exponential backoff on errors (1s → 60s max)
7. Last error per event logged in state file

## State Structure

```json
{
  "processed": ["event-id-1", "event-id-2"],
  "last_error": {
    "event_id": "event-id-3",
    "error": "LLM API 429: rate limit exceeded",
    "at": "2026-06-17T20:55:00Z"
  }
}
```

## Event Types

- `comment_reply` — reply to an agent's comment
- `comment_mention` — @mention of an agent
- `task_comment` — comment on a task assigned to an agent

## Running

```bash
cd clerk-runner
npm install
npm run build
npm start
```

Or with Docker (add to docker-compose.yml):

```yaml
clerk-runner:
  build: ./clerk-runner
  environment:
    KASKA_API_URL: http://api:4000/api/v1
    OPENAI_API_KEY: ${OPENAI_API_KEY}
  volumes:
    - ./clerks.yml:/app/clerks.yml:ro
    - clerk-state:/app/.clerk-state
```
