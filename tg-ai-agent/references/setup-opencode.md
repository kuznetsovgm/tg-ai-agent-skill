# Setup for OpenCode

The user performs all the steps themselves, outside the conversation with the agent.

1. **Skill directory.** OpenCode discovers `.agents/skills` and `.claude/skills`. This is enough:
   ```
   mkdir -p ~/.agents/skills
   cp -r tg-ai-agent ~/.agents/skills/tg-ai-agent
   ```
   (if the skill is already installed for Claude Code in `~/.claude/skills/tg-ai-agent/`, OpenCode will find that one too).
2. **Service address.** `~/.config/tg-ai-agent/config.json`:
   ```json
   {"api_url": "https://tg-ai-agent.example.com"}
   ```
   `https://` only (except `http://127.0.0.1` and `http://localhost`). Override with `TGAI_API_URL`.
3. **Token.** A file `~/.config/tg-ai-agent/token` with permissions `0600`; create it yourself, do not paste the token into the conversation and do not put it in `opencode.json`:
   ```
   install -d -m 700 ~/.config/tg-ai-agent
   umask 077 && read -rs TOKEN && printf '%s' "$TOKEN" > ~/.config/tg-ai-agent/token && unset TOKEN
   ```

   Permissions are checked on every run (on POSIX): the `~/.config/tg-ai-agent` directory no wider than `0700`, `config.json` and `token` no wider than `0600`, you as the owner; otherwise `CONFIG_ERROR` with a `chmod` hint. **On Windows permissions are not checked**: the path is `%USERPROFILE%\.config\tg-ai-agent\token`; restrict access to the directory and files to your own account manually (ACL).
4. **Permissions and network.** No extra network setup is required. The `bash` permission defaults to `allow`: if you wish, narrow it with a rule for `node */tg-ai-agent/scripts/tgai.mjs *`. The skill is invoked with the `skill` tool by the name `tg-ai-agent`.
5. **Check.** In a new session: "show my Telegram accounts" — the agent should run `tgai status`. If something does not work, ask the agent to run `tgai doctor` (or run `node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs doctor` yourself): it names the failed step. `tgai self-check` verifies that the skill files are intact.

Updating the skill: replace the directory with a new copy.
