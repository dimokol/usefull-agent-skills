# agent-chat 🟢

A tiny zero-dependency MCP server that lets several CLI agents in **separate
terminals** (Claude Code, Codex, Gemini, anything that speaks MCP) hold shared,
titled chats and deliberate without a human relaying messages between them.

Built for running multiple coding agents at once and having them review each
other's ideas and converge on a conclusion, cheaply and reliably.

- **Rooms:** each conversation is an isolated, titled room with its own files, so
  separate deliberations never collide. `room` is required on every call, there
  is no silent shared default.
- **Blocking `wait`:** an agent parks server-side until a peer posts, no polling
  loop and no model tokens burned while it waits (verified on a live Codex run:
  `codex exec --json` shows no model turns during a blocking `wait`).
- **Cross-vendor:** the transport is MCP + a shared folder, so Claude Code in one
  terminal and Codex in another talk to the same rooms. Each CLI spawns its own
  copy of the server; they coordinate through the files on disk.
- Zero dependencies, plain Node (ESM). ~450 lines. Nothing to `npm install`.

## Install into a project

Clone this repo (or copy the `agent-chat/` folder anywhere), then from your
project folder run the installer:

```bash
node /path/to/mcp/agent-chat/install.mjs          # wire the current folder for Claude Code
node /path/to/mcp/agent-chat/install.mjs --codex   # also append the block to ~/.codex/config.toml
node /path/to/mcp/agent-chat/install.mjs --print    # dry run, change nothing
```

It is idempotent and merges (never clobbers). It writes/updates, in your project:
- `.mcp.json` — the `agent-chat` server for Claude Code (absolute path to
  `server.mjs`, `AGENT_CHAT_DIR` set to `<project>/.agent-chat`).
- `.claude/settings.local.json` — enables the server and allow-lists the five
  tools so they don't prompt each call.
- `.gitignore` — ignores the `.agent-chat/` data dir.

For Codex it prints (or with `--codex`, appends) an `[mcp_servers.agent_chat]`
block. Codex needs its own `~/.codex/config.toml`; `.mcp.json` does not configure
it. See `examples/` for the raw config snippets if you'd rather wire it by hand.

> **After installing, restart / reconnect the MCP server in each terminal.** A
> running CLI keeps its old spawned server process until you reconnect, so the
> tools won't appear until then. Same applies whenever you change `server.mjs`.

## Files it maintains

Base folder = `AGENT_CHAT_DIR` (default `~/.agent-chat/main`; the installer points
it at `<project>/.agent-chat`). Rooms live under it:

```
<base>/rooms/<room-id>/
  room.json    { id, title, created }
  chat.jsonl   canonical append-only log (source of truth)
  chat.md      human-readable transcript with the room title header — open this to read
  .lock        short-lived per-room write lock
```

## Tools

- `create_room({ title, room? }) -> { room, title, created }` — new isolated room.
  Ids are unique: an explicit id that exists errors; a title-derived id
  auto-suffixes so a new chat never lands on an existing transcript.
- `list_rooms() -> [{ room, title, created, messages, last_ts }]` — discover and
  join a conversation by title.
- `post({ room, from, to?, message, channel?, reply_to?, title? }) -> { room, message_id, cursor }`
  — `to` omitted or `"all"`/`"*"` broadcasts.
- `wait({ room, me, channel?, after_cursor?, timeout_seconds? }) -> { reason, room, messages, next_cursor }`
  — `reason` is `"message"` | `"timeout"` | `"cancelled"`. Blocks up to
  `timeout_seconds` (default 55, max 3600). `after_cursor` gives restart-safe
  resume; you can `wait` on a room before it exists and wake when it's created.
- `history({ room, channel?, limit? })` — catch up on a room's transcript.

`channel` is an optional sub-topic within a room (default `"main"`); rooms are the
real isolation boundary.

## How two agents use it

1. Two terminals, e.g. `claude` in one and `codex` in the other, both in a project
   where you ran the installer.
2. Agree a room id. One agent `create_room`s it (or the first `post` auto-creates
   it), or an agent finds it with `list_rooms`.
3. Paste a kickoff prompt into each. Names must match what the peer puts in `to`.

**The one rule that makes it reliable:** an agent can only be reached while it is
inside a `wait`. If it finishes and returns to the terminal prompt, nothing can
wake it. So the kickoff prompt must tell each agent to loop `post` → `wait` until
the exchange ends. To stop, one agent posts a message whose body is `STOP`.

### Kickoff prompt (adapt the names / room / topic)

> You are collaborating with another AI agent named **codex** over the
> `agent-chat` MCP tools, in room **`my-room`** (create it with `create_room` if
> it doesn't exist). You are **claude**. We're deliberating: `<the decision>`.
> Post your opening position with `post({ room: "my-room", from: "claude", to:
> "codex", message: ... })`, then `wait({ room: "my-room", me: "claude" })`. When a
> reply arrives, read it, push back or build on it honestly, `post` your response,
> and `wait` again. Keep looping. If `wait` returns `reason: "timeout"` and you're
> still expecting a reply, call `wait` again. Stop only when you both converge and
> one of you posts `STOP`, then summarize the conclusion for the human.

Give the other terminal the mirror image (you are **codex**, peer is **claude**,
same room; `wait` first).

## Verify

```bash
node test.mjs
```

Spawns two independent server processes (two CLIs) sharing one base dir and checks
19 cases: room creation + titles, `list_rooms`, room-required (no silent default),
cross-process wake while blocked, **room isolation**, **uniqueness** (dup id
errors, dup title auto-suffixes), wake-on-lazy-create, wrong-recipient-does-not-
wake, broadcast, `after_cursor` pagination, cancellation-no-leak, 80 simultaneous
posts with zero loss, restart resume from a cursor, and the `chat.md` title header.

## Notes / limits

- Codex's default per-tool timeout is 60s; the config raises `tool_timeout_sec` and
  the server's own `wait` default (55s) stays under it as a fallback. Native Claude
  Code "Agent Teams" is a first-party alternative but is Claude-only; this is the
  cross-vendor path.
- The server never executes message contents, only touches `AGENT_CHAT_DIR`, takes
  no filesystem paths from tool arguments, validates room/agent/channel ids
  (`[A-Za-z0-9._-]{1,64}`), caps titles at 200 and messages at 200k chars.
- Delivery is at-least-once; `message_id` makes duplicates harmless.
