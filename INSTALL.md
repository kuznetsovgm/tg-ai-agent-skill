# Installing the skill (instructions for the AI agent)

**If you are an AI agent and the user gave you the link to this repository and asked you to install the skill, follow this file.** It works the same in Claude Code, Codex CLI and OpenCode: the installer puts the skill where all three look for it.

## Rules

- **Never ask for, read, print or store the user's token** (`tga_…`), and never ask them to paste it into this conversation. The user creates the token file themselves, in their own terminal, with a command you give them (step 6).
- The service address is not secret: ask the user for it in the conversation and write it with `tgai configure` (step 6).
- Do not run anything from the repository except the two commands below (`tools/pack.mjs` and the installer). The installer makes no network requests and does not touch the token or the config.
- Do not change the client's sandbox, network or permission settings yourself; tell the user what to change (step 7).

## 1. Ask: for this project or globally?

Ask the user before installing:

> Install the skill **globally** (for every project of your user account) or **only for this project** (`<project directory>`)?

Recommend global. Set `BASE` for the rest of the steps:

| Answer | `BASE` | The skill ends up in |
| --- | --- | --- |
| Globally | the user's home directory (`$HOME`, on Windows `%USERPROFILE%`) | `BASE/.agents/skills/tg-ai-agent` (Codex CLI, OpenCode) and `BASE/.claude/skills/tg-ai-agent` (Claude Code) |
| This project | the project root (the directory the client was started in, usually the git root; confirm it with the user) | the same two paths, under the project |

The service address and the token are always per user (`~/.config/tg-ai-agent/`), also for a project install. For a project install tell the user that the two new directories are inside their project: they can commit them to share the skill with the team, or add them to `.gitignore`. Do not commit anything yourself.

## 2. Check the requirements

- Node.js 18 or newer: `node --version` (22 or 24 recommended). If it is missing, stop and tell the user.
- `git` (or any way to download this repository as an archive).

## 3. Get the repository into a temporary directory

Not into the user's project:

```
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/kuznetsovgm/tg-ai-agent-skill.git "$tmp/src"
```

If the user gave a different URL (a fork, a tag), clone that one. Without `git`, download the repository archive from GitHub and unpack it into `$tmp/src`.

## 4. Build the archive

```
node "$tmp/src/tools/pack.mjs" --out "$tmp/out"
```

It prints JSON with the version and the SHA-256 of `tg-ai-agent-<version>.tar.gz` and writes the archive plus `install.sh` and `install.ps1` to `$tmp/out`.

## 5. Install

The installer installs under the home directory it is given, so `BASE` is passed as `HOME` (Windows: `USERPROFILE`).

macOS, Linux, WSL, globally:

```
sh "$tmp/out/install.sh" "$tmp/out"/tg-ai-agent-*.tar.gz
```

macOS, Linux, WSL, for this project (`--copy` makes the Claude Code directory a real copy instead of a link with an absolute path, so the project stays portable):

```
HOME="<project root>" sh "$tmp/out/install.sh" --copy "$tmp/out"/tg-ai-agent-*.tar.gz
```

Windows (PowerShell 5.1 or newer), globally:

```
powershell -ExecutionPolicy Bypass -File "$tmp\out\install.ps1" -Archive "$tmp\out\tg-ai-agent-<version>.tar.gz"
```

Windows, for this project:

```
$env:USERPROFILE = '<project root>'
powershell -ExecutionPolicy Bypass -File "$tmp\out\install.ps1" -Archive "$tmp\out\tg-ai-agent-<version>.tar.gz"
```

(set `USERPROFILE` back afterwards, or do this in a separate PowerShell process).

The installer checks the archive first and changes nothing if the check fails. It replaces `BASE/.agents/skills/tg-ai-agent/` and makes `BASE/.claude/skills/tg-ai-agent/` a link to it (a copy on Windows, with `--copy`, or if links are not available). A previous version is replaced as a whole.

Write access to the target may need the user's approval in your client; ask for it, do not work around it. Remove the temporary directory afterwards: `rm -rf "$tmp"`.

From here on, `SKILL_DIR` is `BASE/.agents/skills/tg-ai-agent`.

## 6. First session: the address, then the token

Ask the user for the address of their tg-ai-agent service (for example `https://tga.example.com`). It is not a secret and may be typed in the conversation. Write it with the skill itself:

```
node "<SKILL_DIR>/scripts/tgai.mjs" configure --api-url <address>
```

The script checks the address (`https://`, no credentials) and writes `~/.config/tg-ai-agent/config.json` with private permissions. Its answer says whether a token is already in place. If it is not, the answer carries `data.token_command`: **show the user that exact command** and ask them to run it **in their own terminal, not in this conversation and not by you**. On Linux/macOS it looks like this:

```
install -d -m 700 '~/.config/tg-ai-agent' && (umask 077; printf 'Token: ' && read -rs TOKEN && printf '%s' "$TOKEN" > '~/.config/tg-ai-agent/token'); unset TOKEN; echo
```

(with the real absolute path). It asks for the token at a hidden prompt, so the token appears neither in the conversation nor on screen; the administrator of the service gave the user their token. Wait until the user confirms. The Windows variant in `token_command` is PowerShell; permissions are not checked there, so the user should restrict access to the directory to their own account. If the user prefers, the `TGAI_TOKEN` environment variable works too.

## 7. Client-specific notes

Read the file for the client you run in and pass the relevant part to the user:

- Claude Code: [`tg-ai-agent/references/setup-claude-code.md`](tg-ai-agent/references/setup-claude-code.md). Nothing to do unless the sandbox is on; then the service domain must be added to the allowed domains.
- Codex CLI: [`tg-ai-agent/references/setup-codex.md`](tg-ai-agent/references/setup-codex.md). **Network access must be enabled** (`[sandbox_workspace_write] network_access = true` in `~/.codex/config.toml`), otherwise the skill cannot reach the service.
- OpenCode: [`tg-ai-agent/references/setup-opencode.md`](tg-ai-agent/references/setup-opencode.md). Nothing extra.

## 8. Verify and finish

1. `node "<SKILL_DIR>/scripts/tgai.mjs" self-check` must report the files intact.
2. Once the user has confirmed the token file, `node "<SKILL_DIR>/scripts/tgai.mjs" doctor` names any step that does not work (address, token, permissions, network, TLS). It does not print the token.
3. Tell the user that **a new session of the client may be needed** before the skill appears (for a project install: a session started in that project), and that they can then ask, for example, "show my Telegram accounts".

Updating later: repeat steps 3–5 with the same scope; the old version is replaced.
