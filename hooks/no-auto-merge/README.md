# no-auto-merge guard (PreToolUse hook)

A machine-level safety rail for agent-driven PR workflows: it **physically blocks** an AI agent from merging PRs or pushing to protected branches, no matter what its prompt or skill says. The agent can still do everything else — review, fix, run gates, ask your reviewer, report status — but the merge step always stops at "ready, awaiting your explicit approval".

## Why

Prompt-level rules ("never merge without asking") are soft: a long session, a compacted context, or an over-eager skill can walk right past them. We learned this the hard way — an agent once promoted `dev`→`main` on its own initiative, and another merged a PR to `dev` that wasn't production-ready. A `PreToolUse` hook is hard: the command is denied before it runs, and the denial message tells the agent exactly what to do instead.

## What it blocks

- `gh pr merge` (any repo, any base branch)
- `gh api` calls to PR/branch merge endpoints, and GraphQL `mergePullRequest` / `enablePullRequestAutoMerge`
- `git push` with a refspec targeting `main`/`master` (including `dev:main`, `HEAD:main`, `--force`)
- `git merge` or a bare `git push` while the repo is checked out on `main`/`master`

## What it does NOT block (tested)

Read-only and everyday commands pass through untouched: `gh pr view` / `gh pr checks` / `gh pr create`, `git fetch` / `log` / `status` / `merge-base`, and normal feature-branch pushes (`git push origin feat/main-page` is fine — only full `main`/`master` destination tokens match).

## Override

When you have explicitly approved a specific merge, the agent re-runs the command prefixed with the override:

```bash
ALLOW_MERGE=1 gh pr merge 123 --repo you/repo --merge
```

The agent must never set `ALLOW_MERGE=1` without your explicit per-merge approval — put that rule in your CLAUDE.md (see below).

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   curl -fsSL https://raw.githubusercontent.com/dimokol/usefull-agent-skills/main/hooks/no-auto-merge/hook.sh \
     -o ~/.claude/hooks/no-auto-merge.sh
   chmod +x ~/.claude/hooks/no-auto-merge.sh
   ```

2. Register it in `~/.claude/settings.json` (merge with your existing hooks):

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "sh \"$HOME/.claude/hooks/no-auto-merge.sh\"" }
           ]
         }
       ]
     }
   }
   ```

3. Add the matching policy to your project's CLAUDE.md so the agent knows the rule rather than just hitting the wall:

   ```markdown
   **Never auto-merge.** Nothing merges without the operator's explicit instruction for that
   specific merge AND manual approval. Run reviews/gates, then STOP and report
   "READY — awaiting your explicit merge approval". Only after approval, prefix the merge
   command with ALLOW_MERGE=1 (a PreToolUse hook blocks it otherwise).
   ```

4. Verify: ask the agent to run `gh pr merge --help` — it should be denied with the guard's message, while `gh pr view <pr>` works normally.

Requires `jq`. Protected branches are `main` and `master` by default — edit the two `main|master` patterns in `hook.sh` to add others (e.g. `production`).

Pairs with [`babysit-prs`](../../skills/babysit-prs/SKILL.md): keep its `Auto-merge` config off (the default) and this hook guarantees the policy even for sessions that never read the skill.
