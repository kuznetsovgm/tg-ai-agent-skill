# Installing the skill (instructions for the AI agent)

**If you are an AI agent and the user gave you the link to this repository and asked you to install the skill, follow this file.** It works the same in Claude Code, Codex CLI and OpenCode: the installer puts the skill where all three look for it.

## Rules

- **Never ask for, read, print or store the user's token** (`tga_…`), and never ask them to paste it into this conversation. The user creates the token file themselves, in their own terminal (step 5).
- The service address is not secret: ask the user for it in the conversation and write it with `tgai configure` (step 5).
- Do not run anything from the repository except the two commands below (`tools/pack.mjs` and the installer). The installer makes no network requests and does not touch the token or the config.
- Do not change the client's sandbox, network or permission settings yourself; tell the user what to change (step 6).

## 1. Check the requirements

- Node.js 18 or newer: `node --version` (22 or 24 recommended). If it is missing, stop and tell the user.
- `git` (or any way to download this repository as an archive).

## 2. Get the repository into a temporary directory

Not into the user's project:

```
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/kuznetsovgm/tg-ai-agent-skill.git "$tmp/src"
```

If the user gave a different URL (a fork, a tag), clone that one. Without `git`, download the repository archive from GitHub and unpack it into `$tmp/src`.

## 3. Build the archive

```
node "$tmp/src/tools/pack.mjs" --out "$tmp/out"
```

It prints JSON with the version and the SHA-256 of `tg-ai-agent-<version>.tar.gz` and writes the archive plus `install.sh` and `install.ps1` to `$tmp/out`.

## 4. Install

macOS, Linux, WSL:

```
sh "$tmp/out/install.sh" "$tmp/out"/tg-ai-agent-*.tar.gz
```

Windows (PowerShell 5.1 or newer):

```
powershell -ExecutionPolicy Bypass -File "$tmp\out\install.ps1" -Archive "$tmp\out\tg-ai-agent-<version>.tar.gz"
```

The installer checks the archive first and changes nothing if the check fails. It then replaces `~/.agents/skills/tg-ai-agent/` (read by Codex CLI and OpenCode) and makes `~/.claude/skills/tg-ai-agent/` a link to it (read by Claude Code; a copy on Windows, or with `--copy` if links are not available). A previous version is replaced as a whole.

Write access to the home directory may need the user's approval in your client; ask for it, do not work around it.

Remove the temporary directory afterwards: `rm -rf "$tmp"`.

## 5. First session: the address, then the token

Ask the user for the address of their tg-ai-agent service (for example `https://tga.example.com`). It is not a secret and may be typed in the conversation. Write it with the skill itself:

```
node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs configure --api-url <address>
```

The script checks the address (`https://`, no credentials) and writes `~/.config/tg-ai-agent/config.json` with private permissions. It prints whether a token is already in place.

If it is not, tell the user to create it **in their own terminal, not in this conversation** (the token comes from the service administrator), and wait until they confirm:

```
install -d -m 700 ~/.config/tg-ai-agent
umask 077 && read -rs TOKEN && printf '%s' "$TOKEN" > ~/.config/tg-ai-agent/token && unset TOKEN
```

(`read -rs` waits for the token to be typed or pasted and does not echo it.) On Windows the file is `%USERPROFILE%\.config\tg-ai-agent\token`; permissions are not checked there, so the user should restrict access to their own account. The `token` file is always the user's to create; if the user prefers, the `TGAI_TOKEN` environment variable works too.

## 6. Client-specific notes

Read the file for the client you run in and pass the relevant part to the user:

- Claude Code: [`tg-ai-agent/references/setup-claude-code.md`](tg-ai-agent/references/setup-claude-code.md). Nothing to do unless the sandbox is on; then the service domain must be added to the allowed domains.
- Codex CLI: [`tg-ai-agent/references/setup-codex.md`](tg-ai-agent/references/setup-codex.md). **Network access must be enabled** (`[sandbox_workspace_write] network_access = true` in `~/.codex/config.toml`), otherwise the skill cannot reach the service.
- OpenCode: [`tg-ai-agent/references/setup-opencode.md`](tg-ai-agent/references/setup-opencode.md). Nothing extra.

## 7. Verify and finish

1. `node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs self-check` must report the files intact.
2. Once the user has confirmed the token file, `node ~/.agents/skills/tg-ai-agent/scripts/tgai.mjs doctor` names any step that does not work (address, token, permissions, network, TLS). It does not print the token.
3. Tell the user that **a new session of the client may be needed** before the skill appears, and that they can then ask, for example, "show my Telegram accounts".

Updating later: repeat steps 2–4; the old version is replaced.
