# Installer of the tg-ai-agent skill (Windows 10/11, PowerShell 5.1+).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Archive path\to\tg-ai-agent-<version>.tar.gz]
#
# Without -Archive it takes the single tg-ai-agent-*.tar.gz next to this
# script. It installs:
#   %USERPROFILE%\.agents\skills\tg-ai-agent   the skill (Codex CLI, OpenCode)
#   %USERPROFILE%\.claude\skills\tg-ai-agent   a COPY of it (Claude Code; no symlink rights needed)
#
# It does not run anything from the archive, does not ask for or read the
# token, does not touch %USERPROFILE%\.config\tg-ai-agent\, does not touch other
# skills and does not use the network. The old tg-ai-agent directory is
# replaced as a whole. The archive is checked completely in a temporary
# directory before anything under the user profile is changed.
#
# The same contract as install.sh: the STEP lines are mirrored one to one
# (a test compares them). NOT run by the automated tests (no PowerShell in CI):
# the installation on Windows is a manual step of the live client run (L4-09).

[CmdletBinding()]
param([string]$Archive = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Name = 'tg-ai-agent'
$Component = '[A-Za-z0-9_][A-Za-z0-9._-]*'
$Work = $null
# Holder directories next to the targets: the new copy and the replaced old
# one live there until the whole installation is done.
$HoldAgents = $null
$HoldClaude = $null
$OldAgents = $null
$OldClaude = $null
$AgentsPlaced = $false

function Get-Entry([string]$Path) {
  # Also finds a broken link (Test-Path does not); $null if there is nothing.
  return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-Link($Item) {
  return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Remove-Entry([string]$Path) {
  # A junction or a symlink is removed itself, never through its target, at the
  # top and inside (Directory.Delete does not follow reparse points).
  $item = Get-Entry $Path
  if ($null -eq $item) { return }
  if (Test-Link $item) {
    $item.Delete()
  } elseif ($item.PSIsContainer) {
    [System.IO.Directory]::Delete($Path, $true)
  } else {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Test-SkillName([string]$Md) {
  # `name: tg-ai-agent` in the frontmatter (between the first two --- lines), case-sensitive.
  if (-not (Test-Path -LiteralPath $Md -PathType Leaf)) { return $false }
  $text = [System.IO.File]::ReadAllText($Md)
  if ($text -cmatch '(?s)\A---\r?\n(.*?)\r?\n---') {
    return ($Matches[1] -cmatch ('(?m)^name:[ \t]*' + [regex]::Escape($Name) + '[ \t]*\r?$'))
  }
  return $false
}

function Test-Ours([string]$Path) {
  # Replaced only if absent, a link (the link itself) or a directory of this skill
  # without links inside (nothing can be followed out of it).
  $item = Get-Entry $Path
  if ($null -eq $item) { return $true }
  if (Test-Link $item) { return $true }
  if (-not $item.PSIsContainer) { return $false }
  if (-not (Test-SkillName (Join-Path $Path 'SKILL.md'))) { return $false }
  foreach ($child in @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
    if (Test-Link $child) { return $false }
  }
  return $true
}

function Test-Parent([string]$Path) {
  # The nearest existing ancestor of a directory to create must be a directory.
  $p = $Path
  while ($null -eq (Get-Entry $p)) { $p = Split-Path -Parent $p }
  if (-not (Get-Entry $p).PSIsContainer) {
    throw "$p is not a directory (needed for $Path); nothing was changed"
  }
}

function New-Holder([string]$Parent) {
  $path = Join-Path $Parent ".$Name.$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $path | Out-Null
  return $path
}

function Put-InPlace([string]$New, [string]$Dest, [string]$Hold) {
  # Puts $New at $Dest; the old $Dest goes to $Hold\old. Returns the place of the old one or $null.
  $old = $null
  if ($null -ne (Get-Entry $Dest)) {
    $old = Join-Path $Hold 'old'
    Move-Item -LiteralPath $Dest -Destination $old
  }
  try {
    Move-Item -LiteralPath $New -Destination $Dest
  } catch {
    if ($old) { Move-Item -LiteralPath $old -Destination $Dest }
    throw
  }
  return $old
}

function Undo-Install {
  # Puts back what step 6 and step 7 replaced (best effort).
  try {
    if ($OldClaude -and $null -eq (Get-Entry $ClaudeDest)) {
      Move-Item -LiteralPath $OldClaude -Destination $ClaudeDest
    }
    if ($AgentsPlaced) {
      Remove-Entry $AgentsDest
      if ($OldAgents -and $null -ne (Get-Entry $OldAgents)) {
        Move-Item -LiteralPath $OldAgents -Destination $AgentsDest
      }
    }
  } catch {
    [Console]::Error.WriteLine("install.ps1: could not fully restore the previous installation: $($_.Exception.Message)")
  }
}

try {
  # STEP 1 locate-archive
  $UserHome = $env:USERPROFILE
  if (-not $UserHome) { $UserHome = [Environment]::GetFolderPath('UserProfile') }
  if (-not $UserHome -or -not (Test-Path -LiteralPath $UserHome -PathType Container)) {
    throw 'the user profile directory is not found'
  }
  if (-not $Archive) {
    $found = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "$Name-*.tar.gz" -File)
    if ($found.Count -ne 1) {
      throw "expected exactly one $Name-*.tar.gz next to the script (found $($found.Count)); pass -Archive"
    }
    $Archive = $found[0].FullName
  }
  if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw "archive not found: $Archive" }
  $Work = Join-Path ([System.IO.Path]::GetTempPath()) "$Name-install.$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $Work | Out-Null

  # STEP 2 list-archive
  # The tar of Windows itself: another tar.exe in PATH (GNU tar) takes `C:` for a remote host.
  $Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
  if (-not (Test-Path -LiteralPath $Tar -PathType Leaf)) { throw 'tar.exe of Windows is not found' }
  $names = @(& $Tar -tzf $Archive)
  if ($LASTEXITCODE -ne 0 -or $names.Count -eq 0) { throw "not a readable .tar.gz archive: $Archive" }
  $long = @(& $Tar -tvzf $Archive)
  if ($LASTEXITCODE -ne 0 -or $long.Count -ne $names.Count) { throw "not a readable .tar.gz archive: $Archive" }
  $nameRe = '^' + $Name + '/?$|^' + $Name + '(/' + $Component + ')+/?$'
  $seenNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($n in $names) {
    if (-not $seenNames.Add($n)) { throw 'the archive has the same entry twice' }
    if ($n -cnotmatch $nameRe) {
      throw "the archive has a name outside $Name/ or an unsafe name (absolute, '..', hidden, unusual characters)"
    }
  }
  foreach ($l in $long) {
    if ($l -cnotmatch '^[-d]') {
      throw 'the archive has an entry that is not a regular file or a directory (link, device)'
    }
  }

  # STEP 3 extract
  $Stage = Join-Path $Work 'stage'
  New-Item -ItemType Directory -Path $Stage | Out-Null
  & $Tar -xzf $Archive -C $Stage
  if ($LASTEXITCODE -ne 0) { throw 'cannot extract the archive' }
  $Skill = Join-Path $Stage $Name
  if (-not (Test-Path -LiteralPath $Skill -PathType Container)) { throw "the archive has no $Name/ directory" }
  $top = @(Get-ChildItem -LiteralPath $Stage -Force)
  if ($top.Count -ne 1 -or $top[0].Name -cne $Name) { throw "the archive has entries outside $Name/" }
  $all = @(Get-ChildItem -LiteralPath $Skill -Recurse -Force)
  foreach ($item in $all) {
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw 'the extracted tree has something that is not a regular file or a directory'
    }
    if ($item.Name -cnotmatch ('^' + $Component + '$')) {
      throw 'the extracted tree has a file name with unusual characters'
    }
    if ($item.PSIsContainer -and @(Get-ChildItem -LiteralPath $item.FullName -Force).Count -eq 0) {
      throw 'the extracted tree has an empty directory'
    }
  }

  # STEP 4 verify-sums
  $Sums = Join-Path $Skill 'SHA256SUMS'
  if (-not (Test-Path -LiteralPath $Sums -PathType Leaf)) { throw 'SHA256SUMS is missing in the archive' }
  # ReadAllText would swallow a BOM, which `tgai self-check` does not accept.
  $text = (New-Object System.Text.UTF8Encoding($false)).GetString([System.IO.File]::ReadAllBytes($Sums))
  if ($text.Length -eq 0 -or $text -match "`r" -or -not $text.EndsWith("`n")) {
    throw 'SHA256SUMS is empty or has a malformed line'
  }
  $lines = $text.Substring(0, $text.Length - 1).Split("`n")
  $lineRe = '^([0-9a-f]{64})  (' + $Component + '(/' + $Component + ')*)$'
  $listed = New-Object System.Collections.Generic.List[string]
  $want = @{}
  foreach ($line in $lines) {
    if ($line -cmatch $lineRe) {
      $want[$Matches[2]] = $Matches[1]
      $listed.Add($Matches[2])
    } else {
      throw 'SHA256SUMS has a malformed line'
    }
  }
  for ($i = 1; $i -lt $listed.Count; $i++) {
    if ([string]::CompareOrdinal($listed[$i - 1], $listed[$i]) -ge 0) {
      throw 'SHA256SUMS paths are not in byte order or are repeated'
    }
  }
  foreach ($p in $listed) {
    if ($p -ceq 'SHA256SUMS' -or $p.StartsWith('install/', [System.StringComparison]::Ordinal)) {
      throw 'SHA256SUMS lists SHA256SUMS or install/'
    }
  }
  $present = New-Object System.Collections.Generic.List[string]
  $prefix = $Skill.TrimEnd('\') + '\'
  foreach ($f in (Get-ChildItem -LiteralPath $Skill -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($prefix.Length).Replace('\', '/')
    if ($rel -cne 'SHA256SUMS') { $present.Add($rel) }
  }
  $presentArray = $present.ToArray()
  [Array]::Sort($presentArray, [System.StringComparer]::Ordinal)
  if (($presentArray -join "`n") -cne ($listed -join "`n")) {
    throw 'the files of the archive differ from the list in SHA256SUMS'
  }
  foreach ($p in $listed) {
    $file = Join-Path $Skill ($p.Replace('/', '\'))
    $got = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -cne $want[$p]) { throw "checksum mismatch: $p" }
  }
  $md = Join-Path $Skill 'SKILL.md'
  if (-not (Test-Path -LiteralPath $md -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $Skill 'scripts\tgai.mjs') -PathType Leaf)) {
    throw 'SKILL.md or scripts/tgai.mjs is missing'
  }
  if (-not (Test-SkillName $md)) {
    throw "SKILL.md is not the $Name skill"
  }

  # STEP 5 check-targets
  $AgentsDir = Join-Path $UserHome '.agents\skills'
  $ClaudeDir = Join-Path $UserHome '.claude\skills'
  $AgentsDest = Join-Path $AgentsDir $Name
  $ClaudeDest = Join-Path $ClaudeDir $Name
  foreach ($t in @($AgentsDest, $ClaudeDest)) {
    if (-not (Test-Ours $t)) {
      throw "$t exists and is not an installation of $Name; move it away and run again (nothing was changed)"
    }
  }
  Test-Parent $AgentsDir
  Test-Parent $ClaudeDir

  # STEP 6 install-agents
  New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null
  $HoldAgents = New-Holder $AgentsDir
  Copy-Item -LiteralPath $Skill -Destination (Join-Path $HoldAgents 'new') -Recurse
  $OldAgents = Put-InPlace (Join-Path $HoldAgents 'new') $AgentsDest $HoldAgents
  $AgentsPlaced = $true

  # STEP 7 install-claude
  try {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    $HoldClaude = New-Holder $ClaudeDir
    Copy-Item -LiteralPath $AgentsDest -Destination (Join-Path $HoldClaude 'new') -Recurse
    $OldClaude = Put-InPlace (Join-Path $HoldClaude 'new') $ClaudeDest $HoldClaude
  } catch {
    Undo-Install
    throw
  }
  # Done: the holders (with the old directories inside) are removed in `finally`.

  # STEP 8 report
  Write-Output "Installed ${Name}:"
  Write-Output "  $AgentsDest"
  Write-Output "  $ClaudeDest (copy)"
  Write-Output 'Nothing was run. Check the installation with:'
  Write-Output "  node `"$AgentsDest\scripts\tgai.mjs`" self-check"
  Write-Output "  node `"$AgentsDest\scripts\tgai.mjs`" doctor"
  Write-Output 'The token and the address are set as described in references/setup-*.md (outside the dialog with the agent).'
} catch {
  [Console]::Error.WriteLine("install.ps1: $($_.Exception.Message)")
  exit 1
} finally {
  foreach ($p in @($HoldAgents, $HoldClaude, $Work)) {
    if ($p) { Remove-Entry $p }
  }
}
