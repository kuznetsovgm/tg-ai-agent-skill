# Setup for Codex CLI

The user performs all the steps themselves, outside the conversation with the agent.

1. **Skill directory.** Copy the `tg-ai-agent` directory (containing `SKILL.md`, `scripts/`, `references/`) to `~/.agents/skills/tg-ai-agent/` (or to `.agents/skills/` of a repository).
   ```
   mkdir -p ~/.agents/skills
   cp -r tg-ai-agent ~/.agents/skills/tg-ai-agent
   ```
2. **Service address.** Either tell the agent the address in the first session (it runs `tgai configure --api-url <address>`; the address is not a secret), or create `~/.config/tg-ai-agent/config.json` yourself:
   ```json
   {"api_url": "https://tg-ai-agent.example.com"}
   ```
   The address must be `https://` (`http://127.0.0.1` and `http://localhost` are allowed for development). Override with the `TGAI_API_URL` variable.
3. **Token.** Get the token from the administrator and save it to a file readable by the owner only; do not paste the token into the conversation with the agent and do not put it in `~/.codex/config.toml`:
   ```
   install -d -m 700 ~/.config/tg-ai-agent
   umask 077 && read -rs TOKEN && printf '%s' "$TOKEN" > ~/.config/tg-ai-agent/token && unset TOKEN
   ```
   The script refuses to read a file with permissions wider than `0600` (exit code 2).

   Permissions are checked on every run (on POSIX): the `~/.config/tg-ai-agent` directory no wider than `0700`, `config.json` and `token` no wider than `0600`, you as the owner; otherwise `CONFIG_ERROR` with a `chmod` hint. **On Windows permissions are not checked**: the path is `%USERPROFILE%\.config\tg-ai-agent\token`; restrict access to the directory and files to your own account manually (ACL).
4. **Network (required).** By default Codex runs commands in `workspace-write` mode without network, so the script cannot reach the service. Enable the network in `~/.codex/config.toml`:
   ```toml
   [sandbox_workspace_write]
   network_access = true
   ```
   This widens the agent's network access as a whole. A narrower alternative is to allow only the service domain through the Codex network proxy (`features.network_proxy = true` and a list of domains in `[permissions.<profile>.network.domains]`); check the exact key names in the documentation for your Codex version.
5. **Check.** In a new Codex session ask: "show my Telegram accounts". The agent should run `tgai status`. Note that Codex may filter out environment variables with `TOKEN` in the name — that is why the token is stored in a file. If something does not work, ask the agent to run `tgai doctor` (or run `node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs doctor` yourself): it names the failed step, for example a missing network (`EPERM`) from step 4. `tgai self-check` verifies that the skill files are intact.

Updating the skill: replace the `~/.agents/skills/tg-ai-agent/` directory with a new copy. If the service requires a newer version, `tgai status` answers `SKILL_VERSION_UNSUPPORTED`.
