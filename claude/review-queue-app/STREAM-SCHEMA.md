# review-pr stream-json event schema

Derived from a real `claude -p --output-format stream-json --verbose` capture of
`/review-pr` (141 events, one full Approve-with-nits review). Every line is one
complete JSON object (NDJSON). Common envelope fields: `type`, `uuid`,
`session_id`.

## `type` values seen

| type | count | meaning |
|------|-------|---------|
| `system` | 72 | lifecycle/telemetry. `subtype:"init"` (once, first line) + `subtype:"thinking_tokens"` (running token estimate) |
| `assistant` | 45 | a model turn; payload in `.message.content[]` |
| `user` | 22 | tool results fed back to the model; `.message.content[]` of `tool_result` blocks |
| `rate_limit_event` | 1 | `.rate_limit_info` (status/resets); ignorable for render |
| `result` | 1 | terminal completion event (always last) |

`system/init` carries session metadata: `model`, `permissionMode`, `cwd`,
`tools`, `slash_commands`, `mcp_servers`, `memory_paths`, `claude_code_version`.

## Assistant text

`type:"assistant"` → `.message.content` is an array of blocks, each with its own
`type`:
- `text` → `{ "type":"text", "text":"..." }` — the renderable prose.
- `thinking` → `{ "type":"thinking", "thinking":"...", "signature":"..." }` — internal; not rendered.
- `tool_use` → see below.

One assistant message can mix several blocks (e.g. a `text` preamble + a
`tool_use`). In the sample: 11 `text`, 12 `thinking`, 22 `tool_use` blocks.

## Tool-use events

`tool_use` block: `{ "type":"tool_use", "id":"toolu_…", "name":"Bash", "input":{…} }`.
Tools used here: `Bash` (17), `Read` (2), `Write` (3).

**The GitHub call surfaces as a `Bash` tool_use** whose `input.command` contains
`gh`/`git` — there is no dedicated GitHub tool in this stream. Examples:
`gh pr view 55 …`, `gh pr diff 55`, `gh pr checks 55`, and the review post
`gh api repos/<owner>/<repo>/pulls/55/reviews --method POST …`. So a "made a
GitHub call" indicator = a `Bash` tool_use whose command matches `\bgh\b`.

The matching result arrives later as a `user` event containing a `tool_result`
block: `{ "type":"tool_result", "tool_use_id":"toolu_…", "is_error":false|true|null, "content": <string | array> }`.
`is_error` may be `null`. `content` is usually a string but can be an array of
blocks; large outputs are replaced with a `<persisted-output>` placeholder.

## Terminal result

Exactly one `type:"result"`, last line:
```
{ "type":"result", "subtype":"success", "is_error":false, "num_turns":23,
  "duration_ms":200991, "total_cost_usd":1.59, "result":"Review posted as **Approve** …",
  "stop_reason":…, "terminal_reason":…, "modelUsage":…, "permission_denials":… }
```
**Detect success via `is_error`, not `subtype`** — `subtype` can read `"success"`
even on a failed run (observed separately: a 401 produced `subtype:"success"`,
`is_error:true`). `result` holds the human-readable final summary.
