# cc-statusline

A self-contained [Claude Code](https://code.claude.com) status line, written in
plain bash. It shows model, context-window usage, subscription usage windows,
cost, reasoning effort, thinking state, and workspace/git context — no runtime
dependencies beyond the standard CLI tools.

## What it shows

```
Opus 4.8 | 139k / 1.0m | 14% used 139,000 | 86% remain 861,000 | thinking: On | effort: high
current: ▰ ▰ ▰ ▱ ▱ ▱ ▱  47% | weekly: ▰ ▰ ▱ ▱ ▱ ▱ ▱  32% | cost: $3.47
resets 15:49 | resets 20th Jul, 06:59 | ⏱ 1h 23m
statswales-backend | ⎇ owner/repo (feature-branch)
```

1. **Model** · tokens used / context size · % used · % remaining · thinking on/off · reasoning effort
2. **Usage bars** — current 5-hour window, 7-day window, extra usage (when enabled) · session cost
3. **Resets** — when each usage window resets · session duration
4. **Workspace** — project directory · `owner/repo` · git worktree (when inside one)

Each segment hides itself when its data is unavailable, so nothing renders
broken outside a git repo or on models without a reasoning-effort setting.

## Requirements

- `bash`, `jq`, `curl`, `awk`
- macOS or Linux
- A recent Claude Code (uses pre-calculated context fields added in v2.1.132)

## Install

Copy `statusline.sh` somewhere on your machine and point your Claude Code
settings at it. In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/statusline.sh"
  }
}
```

Claude Code pipes session JSON to the script on stdin on each render; the script
prints the four lines above to stdout.

## Usage windows

Lines 2 and 3 show your subscription usage (the 5-hour, 7-day, and extra-usage
windows). This data comes from `https://api.anthropic.com/api/oauth/usage`, an
**undocumented** endpoint, authenticated with your Claude Code OAuth token. It
works today but is not a supported API and may change or break without notice.
If it stops responding, lines 1 and 4 still render fine — only the bars and
reset times drop out.

The OAuth token is read at runtime, never stored in the script. It is resolved
in this order:

1. `CLAUDE_CODE_OAUTH_TOKEN` environment variable
2. macOS Keychain (`Claude Code-credentials`)
3. `~/.claude/.credentials.json` (Linux)
4. GNOME Keyring via `secret-tool`

Responses are cached for 60 seconds in `$TMPDIR/claude-statusline/` to avoid
hammering the endpoint on every render.

## License

MIT — see [LICENSE](LICENSE).
