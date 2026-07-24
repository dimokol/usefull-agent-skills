#!/usr/bin/env node
// install.mjs: wire agent-chat into a project so Claude Code and Codex can use it.
//
// Run it from your project root (or pass --project):
//   node /path/to/mcp/agent-chat/install.mjs            # wire the current folder for Claude Code
//   node /path/to/mcp/agent-chat/install.mjs --project /path/to/app
//   node /path/to/mcp/agent-chat/install.mjs --codex    # also append the Codex block to ~/.codex/config.toml
//   node /path/to/mcp/agent-chat/install.mjs --print    # print what it would do, change nothing
//
// It is idempotent: safe to re-run. It MERGES into existing files, never clobbers
// other MCP servers or permissions. The Codex block is printed by default; pass
// --codex to actually append it to your global ~/.codex/config.toml.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SERVER = path.join(HERE, 'server.mjs')

const args = process.argv.slice(2)
const flag = (name) => args.includes(name)
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null }
const DRY = flag('--print')
const DO_CODEX = flag('--codex')
const PROJECT = path.resolve(opt('--project') || process.cwd())
const CHAT_DIR = path.resolve(opt('--room-dir') || path.join(PROJECT, '.agent-chat'))
const TOOLS = ['create_room', 'list_rooms', 'post', 'wait', 'history']

const changes = []
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')) } catch { return null } }
function writeJson(p, obj) {
  if (DRY) { changes.push(`would write ${p}`); return }
  fs.mkdirSync(path.dirname(p), { recursive: true })
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n')
  changes.push(`wrote ${p}`)
}

if (!fs.existsSync(SERVER)) { console.error(`server.mjs not found at ${SERVER}`); process.exit(1) }
if (!fs.existsSync(PROJECT)) { console.error(`project dir not found: ${PROJECT}`); process.exit(1) }

// --- Claude Code: .mcp.json ---
const mcpPath = path.join(PROJECT, '.mcp.json')
const mcp = readJson(mcpPath) || {}
mcp.mcpServers = mcp.mcpServers || {}
mcp.mcpServers['agent-chat'] = { command: 'node', args: [SERVER], env: { AGENT_CHAT_DIR: CHAT_DIR } }
writeJson(mcpPath, mcp)

// --- Claude Code: .claude/settings.local.json (enable + allow-list, no prompts) ---
const setPath = path.join(PROJECT, '.claude', 'settings.local.json')
const set = readJson(setPath) || {}
set.permissions = set.permissions || {}
const allow = new Set(set.permissions.allow || [])
for (const t of TOOLS) allow.add(`mcp__agent-chat__${t}`)
set.permissions.allow = [...allow]
const enabled = new Set(set.enabledMcpjsonServers || [])
enabled.add('agent-chat')
set.enabledMcpjsonServers = [...enabled]
writeJson(setPath, set)

// --- .gitignore: ignore the chat data dir ---
const giPath = path.join(PROJECT, '.gitignore')
const relChat = (path.relative(PROJECT, CHAT_DIR) || '.agent-chat').replace(/\\/g, '/')
const ignoreLine = relChat.startsWith('..') ? null : relChat.replace(/\/?$/, '/')
if (ignoreLine) {
  let gi = ''
  try { gi = fs.readFileSync(giPath, 'utf8') } catch {}
  if (!gi.split('\n').map((l) => l.trim()).includes(ignoreLine)) {
    if (DRY) changes.push(`would add "${ignoreLine}" to ${giPath}`)
    else { fs.writeFileSync(giPath, (gi && !gi.endsWith('\n') ? gi + '\n' : gi) + ignoreLine + '\n'); changes.push(`added "${ignoreLine}" to .gitignore`) }
  }
}

// --- Codex: ~/.codex/config.toml block ---
const codexBlock = `
# agent-chat: shared cross-agent MCP chat (Claude Code <-> Codex). tool_timeout_sec
# is raised so wait() can block for long idle periods (Codex's default is 60s);
# default_tools_approval_mode covers every tool this server exposes.
[mcp_servers.agent_chat]
command = "node"
args = ["${SERVER}"]
startup_timeout_sec = 10
tool_timeout_sec = 3600
default_tools_approval_mode = "approve"
enabled = true

[mcp_servers.agent_chat.env]
AGENT_CHAT_DIR = "${CHAT_DIR}"
`
const codexPath = path.join(os.homedir(), '.codex', 'config.toml')
if (DO_CODEX) {
  let toml = ''
  try { toml = fs.readFileSync(codexPath, 'utf8') } catch {}
  if (toml.includes('[mcp_servers.agent_chat]')) {
    changes.push(`~/.codex/config.toml already has [mcp_servers.agent_chat] — left as-is`)
  } else if (DRY) {
    changes.push(`would append [mcp_servers.agent_chat] to ${codexPath}`)
  } else {
    fs.mkdirSync(path.dirname(codexPath), { recursive: true })
    fs.writeFileSync(codexPath, (toml && !toml.endsWith('\n') ? toml + '\n' : toml) + codexBlock)
    changes.push(`appended [mcp_servers.agent_chat] to ${codexPath}`)
  }
}

// --- report ---
console.log(`agent-chat install ${DRY ? '(dry run)' : ''}`)
console.log(`  server:     ${SERVER}`)
console.log(`  project:    ${PROJECT}`)
console.log(`  chat data:  ${CHAT_DIR}`)
console.log('')
for (const c of changes) console.log(`  - ${c}`)
if (!DO_CODEX) {
  console.log('\nCodex: add this to ~/.codex/config.toml (or re-run with --codex to append it automatically):')
  console.log(codexBlock)
}
console.log('\nDone. RESTART / reconnect the MCP server in each terminal (Claude Code and Codex) to load the tools.')
