#!/usr/bin/env node
// Cross-process integration test for the agent-chat MCP server. Spawns TWO
// independent server processes (standing in for two separate CLIs) pointed at
// one shared AGENT_CHAT_DIR, driven over stdio JSON-RPC like a real MCP client.
// Covers rooms: creation, titles, uniqueness, and isolation between rooms.

import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SERVER = path.join(HERE, 'server.mjs')
const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-chat-test-'))

const wait = (ms) => new Promise((r) => setTimeout(r, ms))
let failures = 0
function check(cond, label) {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`)
  if (!cond) failures++
}

function client() {
  const proc = spawn('node', [SERVER], { env: { ...process.env, AGENT_CHAT_DIR: DIR }, stdio: ['pipe', 'pipe', 'inherit'] })
  const pending = new Map()
  let buf = ''
  proc.stdout.on('data', (d) => {
    buf += d.toString()
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1)
      if (!line.trim()) continue
      let msg; try { msg = JSON.parse(line) } catch { continue }
      if (msg.id != null && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id) }
    }
  })
  let idc = 0
  const rpc = (method, params) => new Promise((res) => {
    const id = ++idc
    pending.set(id, res)
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n')
  })
  const rpcId = (method, params) => {
    const id = ++idc
    const promise = new Promise((res) => pending.set(id, res))
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n')
    return { id, promise }
  }
  const notify = (method, params) => proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n')
  return { proc, rpc, rpcId, notify, pending }
}

async function raw(c, name, args) {
  const r = await c.rpc('tools/call', { name, arguments: args })
  return r.result
}
function parse(res) { const t = res?.content?.[0]?.text; try { return JSON.parse(t) } catch { return t } }
async function tool(c, name, args) { return parse(await raw(c, name, args)) }

async function init(c) {
  await c.rpc('initialize', { protocolVersion: '2025-06-18' })
  c.notify('notifications/initialized')
}

const A = client() // "claude"
const B = client() // "codex"
await init(A); await init(B)

try {
  // 1. tools exposed
  const list = await A.rpc('tools/list', {})
  const names = (list.result?.tools || []).map((t) => t.name).sort()
  check(JSON.stringify(names) === JSON.stringify(['create_room', 'history', 'list_rooms', 'post', 'wait']), 'tools/list exposes create_room, list_rooms, post, wait, history')

  // 2. create a titled room
  const room = await tool(A, 'create_room', { title: 'Phase 1 Chase Camera' })
  check(room.room === 'phase-1-chase-camera' && room.title === 'Phase 1 Chase Camera', 'create_room derives a slug id and stores the title')

  // 3. list_rooms shows it with the title
  const rooms1 = await tool(A, 'list_rooms', {})
  check(Array.isArray(rooms1) && rooms1.some((r) => r.room === room.room && r.title === 'Phase 1 Chase Camera'), 'list_rooms returns the room with its title')

  // 4. room is required (no silent default)
  const noRoom = await raw(A, 'post', { from: 'claude', message: 'hi' })
  check(noRoom.isError === true, 'post without a room errors (no silent shared default)')

  // 5. blocking delivery within a room
  const bWait = tool(B, 'wait', { room: room.room, me: 'codex', timeout_seconds: 10 })
  await wait(400)
  const posted = await tool(A, 'post', { room: room.room, from: 'claude', to: 'codex', message: 'idea X: raycast springs?' })
  check(posted.room === room.room && posted.cursor === 1, 'post returns room + cursor=1')
  const got = await bWait
  check(got.reason === 'message' && /idea X/.test(got.messages?.[0]?.message), 'codex woke on claude message in the room')

  // 6. ROOM ISOLATION: a waiter on room A is not woken by a post to room B
  const other = await tool(A, 'create_room', { title: 'Unrelated Debate' })
  const isoWait = tool(B, 'wait', { room: room.room, me: 'codex', timeout_seconds: 1 })
  await wait(150)
  await tool(A, 'post', { room: other.room, from: 'claude', to: 'codex', message: 'this belongs to the OTHER room' })
  const iso = await isoWait
  check(iso.reason === 'timeout', 'a post to another room does NOT wake a waiter in this room (isolation)')

  // 7. uniqueness: explicit duplicate id errors; duplicate title auto-suffixes
  const dupErr = await raw(A, 'create_room', { title: 'Whatever', room: room.room })
  check(dupErr.isError === true, 'create_room with an existing explicit id errors')
  const t1 = await tool(A, 'create_room', { title: 'Same Title' })
  const t2 = await tool(A, 'create_room', { title: 'Same Title' })
  check(t1.room !== t2.room && t2.room.startsWith('same-title'), 'create_room with a duplicate title auto-suffixes to a fresh id')

  // 8. a waiter can park on a room that does not exist yet, then wake when created
  const preWait = tool(B, 'wait', { room: 'lazy-room', me: 'codex', timeout_seconds: 10 })
  await wait(400)
  await tool(A, 'post', { room: 'lazy-room', from: 'claude', to: 'codex', title: 'Lazily Made', message: 'created on first post' })
  const pre = await preWait
  check(pre.reason === 'message' && /created on first post/.test(pre.messages[0].message), 'waiter wakes when the room is created by first post')

  // 9. wrong recipient does not wake
  const t0 = Date.now()
  const wrong = await tool(B, 'wait', { room: room.room, me: 'codex', timeout_seconds: 1 })
  await tool(A, 'post', { room: room.room, from: 'claude', to: 'nobody', message: 'not for codex' })
  check(wrong.reason === 'timeout' && Date.now() - t0 >= 900, 'message to another recipient does not wake (clean timeout)')

  // 10. broadcast wakes everyone
  const bcast = tool(B, 'wait', { room: room.room, me: 'codex', timeout_seconds: 10 })
  await wait(300)
  await tool(A, 'post', { room: room.room, from: 'claude', to: '*', message: 'broadcast: standup?' })
  const bc = await bcast
  check(bc.reason === 'message' && /broadcast/.test(bc.messages.at(-1).message), 'broadcast (to "*") wakes codex')

  // 11. after_cursor pagination
  const hist = await tool(A, 'history', { room: room.room })
  const lastCursor = hist.at(-1).cursor
  await tool(B, 'post', { room: room.room, from: 'codex', to: 'claude', message: 'newer-than-cursor' })
  const paged = await tool(A, 'wait', { room: room.room, me: 'claude', after_cursor: lastCursor, timeout_seconds: 5 })
  check(paged.reason === 'message' && paged.messages.length === 1 && /newer-than-cursor/.test(paged.messages[0].message), 'after_cursor returns only messages past the cursor')

  // 12. cancellation leaves no leak, server keeps working
  const c = B.rpcId('tools/call', { name: 'wait', arguments: { room: room.room, me: 'codex', timeout_seconds: 30 } })
  await wait(300)
  B.notify('notifications/cancelled', { requestId: c.id })
  await wait(300)
  check(B.pending.has(c.id), 'cancelled wait sends no result (request stays unresolved)')
  const afterCancel = tool(B, 'wait', { room: room.room, me: 'codex', timeout_seconds: 10 })
  await wait(300)
  await tool(A, 'post', { room: room.room, from: 'claude', to: 'codex', message: 'still alive after cancel' })
  const ac = await afterCancel
  check(ac.reason === 'message' && /still alive/.test(ac.messages.at(-1).message), 'server keeps working after a cancelled wait')

  // 13. concurrency within a room: both processes hammer posts, no loss/corruption
  const N = 40
  const burst = []
  for (let i = 0; i < N; i++) {
    burst.push(tool(A, 'post', { room: room.room, from: 'claude', to: 'all', channel: 'stress', message: `A-${i}` }))
    burst.push(tool(B, 'post', { room: room.room, from: 'codex', to: 'all', channel: 'stress', message: `B-${i}` }))
  }
  await Promise.all(burst)
  const rawLines = fs.readFileSync(path.join(DIR, 'rooms', room.room, 'chat.jsonl'), 'utf8').split('\n').filter((l) => l.trim())
  let parseOk = 0
  const seen = new Set()
  for (const l of rawLines) { try { const m = JSON.parse(l); parseOk++; if (m.channel === 'stress') seen.add(m.message) } catch {} }
  check(parseOk === rawLines.length, `every jsonl line parses (${parseOk}/${rawLines.length}) under concurrent writes`)
  let allPresent = true
  for (let i = 0; i < N; i++) { if (!seen.has(`A-${i}`) || !seen.has(`B-${i}`)) allPresent = false }
  check(allPresent && seen.size === 2 * N, `all ${2 * N} concurrent messages present, none lost`)

  // 14. restart safety: kill B, restart, resume from a saved cursor
  const savedCursor = (await tool(A, 'history', { room: room.room, channel: 'main' })).at(-1).cursor
  B.proc.kill()
  await wait(200)
  await tool(A, 'post', { room: room.room, from: 'claude', to: 'codex', message: 'sent while codex was down' })
  const B2 = client()
  await init(B2)
  const resumed = await tool(B2, 'wait', { room: room.room, me: 'codex', channel: 'main', after_cursor: savedCursor, timeout_seconds: 5 })
  check(resumed.reason === 'message' && resumed.messages.some((m) => /while codex was down/.test(m.message)), 'restarted process resumes from cursor with no missed messages')
  B2.proc.kill()

  // 15. chat.md has the title header and transcript
  const md = fs.readFileSync(path.join(DIR, 'rooms', room.room, 'chat.md'), 'utf8')
  check(/^# Phase 1 Chase Camera/.test(md) && /idea X/.test(md), 'chat.md has the room title header and the transcript')
} finally {
  A.proc.kill(); B.proc.kill()
}

console.log(`\n${failures === 0 ? 'ALL PASS' : failures + ' FAILED'}  (dir: ${DIR})`)
process.exit(failures === 0 ? 0 : 1)
