# Setup for Claude Code

The user performs all the steps themselves, outside the conversation with the agent.

1. **Skill directory.** Claude Code reads `~/.claude/skills/` (or `.claude/skills/` in a project); it does not discover the `.agents/skills` directory. Put the directory there: either as a copy or as a link to a shared copy.
   ```
   mkdir -p ~/.agents/skills ~/.claude/skills
   cp -r tg-ai-agent ~/.agents/skills/tg-ai-agent
   ln -s ../../.agents/skills/tg-ai-agent ~/.claude/skills/tg-ai-agent   # on Windows — a copy
   ```
2. **Service address.** `~/.config/tg-ai-agent/config.json`:
   ```json
   {"api_url": "https://tg-ai-agent.example.com"}
   ```
   `https://` only (except `http://127.0.0.1` and `http://localhost`). Override with `TGAI_API_URL`.
3. **Token.** A file `~/.config/tg-ai-agent/token` with permissions `0600`; create it yourself, and do not paste the token into the conversation:
   ```
   install -d -m 700 ~/.config/tg-ai-agent
   umask 077 && read -rs TOKEN && printf '%s' "$TOKEN" > ~/.config/tg-ai-agent/token && unset TOKEN
   ```

   Permissions are checked on every run (on POSIX): the `~/.config/tg-ai-agent` directory no wider than `0700`, `config.json` and `token` no wider than `0600`, you as the owner; otherwise `CONFIG_ERROR` with a `chmod` hint. **On Windows permissions are not checked**: the path is `%USERPROFILE%\.config\tg-ai-agent\token`; restrict access to the directory and files to your own account manually (ACL).
4. **Sandbox.** By default the Claude Code sandbox is off and the network is open — nothing to do. If you enabled the sandbox (`/sandbox`), its list of allowed domains is initially empty: add the service domain to `~/.claude/settings.json` (the `network.allowedDomains` key in the sandbox section; check the exact name in the documentation for your version):
   ```json
   {"sandbox": {"network": {"allowedDomains": ["tg-ai-agent.example.com"]}}}
   ```
   The sandbox on Linux/WSL2 needs `bwrap` and `socat`; without `socat` the sandbox may fail to start (behavior depends on `sandbox.failIfUnavailable`).
5. **Permission prompts.** So that Claude Code does not ask on every run, you can add the rule `Bash(node */.claude/skills/tg-ai-agent/scripts/tgai.mjs *)` to the allowed commands. Optional.
6. **Check.** In a new session: "show my Telegram accounts" — the agent should run `tgai status`. If something does not work, ask the agent to run `tgai doctor` (or run `node ~/.claude/skills/tg-ai-agent/scripts/tgai.mjs doctor` yourself): it names the failed step, for example a domain missing from `allowedDomains` (step 4). `tgai self-check` verifies that the skill files are intact.

Updating the skill: replace the directory with a new copy (if it is a link, replacing the shared copy is enough).
