# tg-ai-agent-skill

An [Agent Skills](https://agentskills.io)-style skill that lets a local AI agent
(Codex CLI, Claude Code, OpenCode) work with Telegram accounts through a
[tg-ai-agent](https://github.com/kuznetsovgm/tg-ai-agent) service: read dialogs
and history, send messages, download media, log in to your own account.

The skill is one directory, `tg-ai-agent/`: `SKILL.md`, `scripts/tgai.mjs`
(Node.js 18+, no dependencies) and `references/`. You need the HTTPS address of a
running service and a user token (`tga_…`) from its administrator.

## Install

**With an agent:** give it the link to this repository and write "install the
skill". The agent follows [INSTALL.md](INSTALL.md): it builds and installs the skill
for Claude Code, Codex CLI and OpenCode, then tells you how to put the service
address and your token in place. The token never goes through the conversation:
you create the token file yourself.

**By hand:** build the release archive and installers, then install:

```
node tools/pack.mjs            # writes build/skill/
sh build/skill/install.sh build/skill/tg-ai-agent-<version>.tar.gz
```

On Windows use `build/skill/install.ps1 -Archive <archive>`. The installer
verifies the archive, puts the skill in `~/.agents/skills/tg-ai-agent/` and links
it from `~/.claude/skills/tg-ai-agent/`. It does not read or ask for the token;
setup per client is in `tg-ai-agent/references/setup-*.md`.

Check the install: `node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs self-check`.

## Layout

- `INSTALL.md` — installation steps for an AI agent
- `tg-ai-agent/` — the skill itself (what gets installed)
- `tg-ai-agent/install/` — `install.sh`, `install.ps1`
- `tools/pack.mjs` — reproducible packer (tar.gz + `SHA256SUMS`), no dependencies

## License

Apache-2.0, see [LICENSE](LICENSE).
