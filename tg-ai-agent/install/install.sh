#!/bin/sh
# Installer of the tg-ai-agent skill (macOS, Linux, WSL). POSIX sh.
#
#   sh install.sh [--copy] [path/to/tg-ai-agent-<version>.tar.gz]
#
# Without an argument it takes the single tg-ai-agent-*.tar.gz next to this
# script. It installs:
#   ~/.agents/skills/tg-ai-agent   the skill (Codex CLI, OpenCode)
#   ~/.claude/skills/tg-ai-agent   a symlink to it (Claude Code); --copy makes a copy
#
# What it does NOT do: it does not run anything from the archive, does not ask
# for or read the token, does not touch ~/.config/tg-ai-agent/ (the token and
# the address stay where the user put them), does not touch other skills, does
# not use the network. The old tg-ai-agent directory is replaced as a whole,
# so no file of the previous version stays behind.
#
# The archive is checked completely (names, file types, SHA256SUMS) in a
# temporary directory BEFORE anything under $HOME is changed. Any failure
# leaves $HOME as it was and exits with a non-zero status.
#
# The steps below are mirrored one to one in install.ps1 (a test compares the
# STEP lines).

set -eu
# Byte-wise ranges and sorting, whatever the locale of the user.
LC_ALL=C
export LC_ALL

NAME=tg-ai-agent
WORK=
# Holder directories (mktemp, next to the targets, so renames stay on one
# file system): the new copy and the replaced old one live there until the end.
HOLD_AGENTS=
HOLD_CLAUDE=
OLD_AGENTS=
OLD_CLAUDE=
AGENTS_PLACED=0

die() {
  echo "install.sh: $*" >&2
  exit 1
}

cleanup() {
  for d in "$HOLD_AGENTS" "$HOLD_CLAUDE" "$WORK"; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      rm -rf "$d"
    fi
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

COPY=0
ARCHIVE=
while [ $# -gt 0 ]; do
  case $1 in
    --copy) COPY=1 ;;
    -h | --help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) die "unknown option: $1 (usage: install.sh [--copy] [archive])" ;;
    *)
      [ -z "$ARCHIVE" ] || die "only one archive can be given"
      ARCHIVE=$1
      ;;
  esac
  shift
done

# Is `name: tg-ai-agent` in the frontmatter (between the first two `---` lines) of $1?
skill_name_ok() {
  awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { exit }
    /^name: tg-ai-agent[ \t]*$/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$1" 2>/dev/null
}

# Hash of a file on stdin; the first tool that exists.
if command -v sha256sum >/dev/null 2>&1; then
  hash_stdin() { sha256sum | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  hash_stdin() { shasum -a 256 | cut -d ' ' -f 1; }
elif command -v openssl >/dev/null 2>&1; then
  hash_stdin() { openssl dgst -sha256 -r | cut -d ' ' -f 1; }
else
  die "no SHA-256 tool found (sha256sum, shasum or openssl)"
fi

# STEP 1 locate-archive
case ${HOME:-} in
  /*) ;;
  *) die "HOME is not set to an absolute path" ;;
esac
[ -d "$HOME" ] || die "HOME is not a directory"
if [ -z "$ARCHIVE" ]; then
  here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  count=0
  for f in "$here"/$NAME-*.tar.gz; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    ARCHIVE=$f
  done
  [ "$count" -eq 1 ] || die "expected exactly one $NAME-*.tar.gz next to the script (found $count); pass the archive explicitly"
fi
[ -f "$ARCHIVE" ] || die "archive not found: $ARCHIVE"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/$NAME-install.XXXXXX") || die "cannot create a temporary directory"

# STEP 2 list-archive
tar -tzf "$ARCHIVE" >"$WORK/names" 2>/dev/null || die "not a readable .tar.gz archive: $ARCHIVE"
tar -tvzf "$ARCHIVE" >"$WORK/long" 2>/dev/null || die "not a readable .tar.gz archive: $ARCHIVE"
[ -s "$WORK/names" ] || die "the archive is empty"
COMPONENT='[A-Za-z0-9_][A-Za-z0-9._-]*'
if grep -Ev "^$NAME/?\$|^$NAME(/$COMPONENT)+/?\$" "$WORK/names" >/dev/null; then
  die "the archive has a name outside $NAME/ or an unsafe name (absolute, '..', hidden, unusual characters)"
fi
if grep -v '^[-d]' "$WORK/long" >/dev/null; then
  die "the archive has an entry that is not a regular file or a directory (link, device)"
fi
[ "$(wc -l <"$WORK/names")" -eq "$(wc -l <"$WORK/long")" ] || die "the archive listing is inconsistent"
if [ -n "$(sort "$WORK/names" | uniq -d)" ]; then
  die "the archive has the same entry twice"
fi

# STEP 3 extract
mkdir "$WORK/stage"
tar -xzf "$ARCHIVE" -C "$WORK/stage" || die "cannot extract the archive"
SKILL=$WORK/stage/$NAME
[ -d "$SKILL" ] && [ ! -L "$SKILL" ] || die "the archive has no $NAME/ directory"
[ "$(ls -A "$WORK/stage")" = "$NAME" ] || die "the archive has entries outside $NAME/"
if [ -n "$(find "$SKILL" ! -type f ! -type d -print)" ]; then
  die "the extracted tree has something that is not a regular file or a directory"
fi
if [ -n "$(find "$SKILL" -name '*[!A-Za-z0-9._-]*' -print)" ]; then
  die "the extracted tree has a file name with unusual characters"
fi
if [ -n "$(find "$SKILL" -type d -empty -print)" ]; then
  die "the extracted tree has an empty directory"
fi

# Modes do not depend on the archive (setuid bits, group write) or on the umask.
find "$SKILL" -type d -exec chmod 755 {} +
find "$SKILL" -type f -exec chmod 644 {} +

# STEP 4 verify-sums
SUMS=$SKILL/SHA256SUMS
[ -f "$SUMS" ] && [ ! -L "$SUMS" ] || die "SHA256SUMS is missing in the archive"
[ -s "$SUMS" ] || die "SHA256SUMS is empty"
if grep -Ev "^[0-9a-f]{64}  $COMPONENT(/$COMPONENT)*\$" "$SUMS" >/dev/null; then
  die "SHA256SUMS has a malformed line"
fi
sed 's/^[0-9a-f]\{64\}  //' "$SUMS" >"$WORK/listed"
sort -c -u "$WORK/listed" 2>/dev/null || die "SHA256SUMS paths are not in byte order or are repeated"
if grep -E '^(SHA256SUMS|install/)' "$WORK/listed" >/dev/null; then
  die "SHA256SUMS lists SHA256SUMS or install/"
fi
(cd "$SKILL" && find . -type f ! -path ./SHA256SUMS -print | sed 's|^\./||' | sort) >"$WORK/present"
cmp -s "$WORK/listed" "$WORK/present" || die "the files of the archive differ from the list in SHA256SUMS"
while IFS= read -r line; do
  want=${line%%  *}
  path=${line#*  }
  got=$(hash_stdin <"$SKILL/$path")
  [ "$got" = "$want" ] || die "checksum mismatch: $path"
done <"$SUMS"
[ -f "$SKILL/SKILL.md" ] && [ -f "$SKILL/scripts/tgai.mjs" ] || die "SKILL.md or scripts/tgai.mjs is missing"
skill_name_ok "$SKILL/SKILL.md" || die "SKILL.md is not the $NAME skill"

# STEP 5 check-targets
AGENTS_DIR=$HOME/.agents/skills
CLAUDE_DIR=$HOME/.claude/skills
AGENTS_DEST=$AGENTS_DIR/$NAME
CLAUDE_DEST=$CLAUDE_DIR/$NAME
# A target is replaced only if it is absent, is a symlink (only the link is
# replaced, never what it points to) or is a directory of this very skill.
check_target() {
  if [ -L "$1" ] || [ ! -e "$1" ]; then
    return 0
  fi
  if [ -d "$1" ] && skill_name_ok "$1/SKILL.md"; then
    return 0
  fi
  die "$1 exists and is not an installation of $NAME; move it away and run again (nothing was changed)"
}
# The nearest existing ancestor of a directory to create must be a writable
# directory: a failure is found here, before anything is replaced.
check_parent() {
  p=$1
  while [ ! -e "$p" ] && [ ! -L "$p" ]; do
    p=$(dirname "$p")
  done
  if [ ! -d "$p" ] || [ ! -w "$p" ] || [ ! -x "$p" ]; then
    die "$p is not a writable directory (needed for $1); nothing was changed"
  fi
}
check_target "$AGENTS_DEST"
check_target "$CLAUDE_DEST"
check_parent "$AGENTS_DIR"
check_parent "$CLAUDE_DIR"

# Puts $1 at $2; the old $2 goes to $3/old (kept until the whole install is done).
# Sets PLACED_OLD to the place of the old one (empty if there was none).
PLACED_OLD=
put_in_place() {
  PLACED_OLD=
  if [ -L "$2" ] || [ -e "$2" ]; then
    mv "$2" "$3/old" || return 1
    PLACED_OLD=$3/old
  fi
  if mv "$1" "$2"; then
    return 0
  fi
  if [ -n "$PLACED_OLD" ]; then
    mv "$PLACED_OLD" "$2" || true
  fi
  PLACED_OLD=
  return 1
}

# Puts back what step 6 and step 7 replaced.
rollback() {
  if [ -n "$OLD_CLAUDE" ] && [ ! -e "$CLAUDE_DEST" ] && [ ! -L "$CLAUDE_DEST" ]; then
    mv "$OLD_CLAUDE" "$CLAUDE_DEST" || true
  fi
  if [ "$AGENTS_PLACED" -eq 1 ]; then
    rm -rf "$AGENTS_DEST"
    AGENTS_PLACED=0
    if [ -n "$OLD_AGENTS" ] && { [ -e "$OLD_AGENTS" ] || [ -L "$OLD_AGENTS" ]; }; then
      mv "$OLD_AGENTS" "$AGENTS_DEST" || true
    fi
  fi
}
fail_rollback() {
  rollback
  die "$@"
}

# STEP 6 install-agents
mkdir -p "$AGENTS_DIR" || die "cannot create $AGENTS_DIR"
HOLD_AGENTS=$(mktemp -d "$AGENTS_DIR/.$NAME.XXXXXX") || die "cannot create a directory in $AGENTS_DIR"
cp -R "$SKILL" "$HOLD_AGENTS/new" || die "cannot copy the skill to $AGENTS_DIR"
chmod 755 "$HOLD_AGENTS/new/scripts/tgai.mjs"
put_in_place "$HOLD_AGENTS/new" "$AGENTS_DEST" "$HOLD_AGENTS" || die "cannot put $AGENTS_DEST in place"
OLD_AGENTS=$PLACED_OLD
AGENTS_PLACED=1

# STEP 7 install-claude
mkdir -p "$CLAUDE_DIR" || fail_rollback "cannot create $CLAUDE_DIR"
HOLD_CLAUDE=$(mktemp -d "$CLAUDE_DIR/.$NAME.XXXXXX") || fail_rollback "cannot create a directory in $CLAUDE_DIR"
if [ "$COPY" -eq 1 ]; then
  cp -R "$AGENTS_DEST" "$HOLD_CLAUDE/new" || fail_rollback "cannot copy the skill to $CLAUDE_DIR"
else
  ln -s "$AGENTS_DEST" "$HOLD_CLAUDE/new" || fail_rollback "cannot create a symlink in $CLAUDE_DIR"
fi
put_in_place "$HOLD_CLAUDE/new" "$CLAUDE_DEST" "$HOLD_CLAUDE" || fail_rollback "cannot put $CLAUDE_DEST in place"
OLD_CLAUDE=$PLACED_OLD
# Done: the holders (with the old directories inside) are removed on exit.

# STEP 8 report
echo "Installed $NAME:"
echo "  $AGENTS_DEST"
if [ "$COPY" -eq 1 ]; then
  echo "  $CLAUDE_DEST (copy)"
else
  echo "  $CLAUDE_DEST (symlink)"
fi
echo "Nothing was run. Check the installation with:"
echo "  node \"$AGENTS_DEST/scripts/tgai.mjs\" self-check"
echo "  node \"$AGENTS_DEST/scripts/tgai.mjs\" doctor"
echo "The token and the address are set as described in references/setup-*.md (outside the dialog with the agent)."
