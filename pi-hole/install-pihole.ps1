<#
.SYNOPSIS
  Installs Pi-hole (Docker) on a remote Ubuntu/Debian VM over SSH.

.DESCRIPTION
  Copies install-pihole-ubuntu.sh to the VM and runs it there. Installs Docker
  if needed and starts Pi-hole. You'll be prompted for your sudo password and a
  Pi-hole admin password. Needs the OpenSSH client (ssh, scp), which is built
  into Windows 10/11. Also works with PowerShell 7 (pwsh) on macOS/Linux.

.PARAMETER Target
  user@host or an SSH config alias (for example: hud).

.PARAMETER Timezone
  IANA timezone for the container. Default: America/New_York.

.EXAMPLE
  .\install-pihole.ps1 hud
  .\install-pihole.ps1 atedesco@192.168.7.226 -Timezone America/Chicago
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Target,

  [string]$Timezone = 'America/New_York',

  [string]$RemoteScript = (Join-Path $PSScriptRoot 'install-pihole-ubuntu.sh')
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in 'ssh', 'scp') {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "'$cmd' not found. Install the OpenSSH Client (Settings > Apps > Optional features)."
  }
}
if ($Timezone -notmatch '^[A-Za-z0-9_+/-]+$') { throw "Invalid timezone: $Timezone" }
if (-not (Test-Path -LiteralPath $RemoteScript)) {
  throw "Missing $RemoteScript (keep install-pihole-ubuntu.sh next to this script)."
}

# Bash can't run a script with Windows (CRLF) line endings or a UTF-8 BOM,
# so write a clean LF/no-BOM copy to a temp file before uploading.
$text  = (Get-Content -LiteralPath $RemoteScript -Raw) -replace "`r`n", "`n" -replace "`r", "`n"
$clean = Join-Path ([IO.Path]::GetTempPath()) ("pihole-install-{0}.sh" -f [guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($clean, $text, (New-Object System.Text.UTF8Encoding($false)))

$remoteTmp = "/tmp/pihole-install.{0}.sh" -f [guid]::NewGuid().ToString('N').Substring(0, 8)

try {
  Write-Host "Copying installer to $Target ..."
  & scp -q $clean "${Target}:$remoteTmp"
  if ($LASTEXITCODE -ne 0) { throw "scp failed (exit $LASTEXITCODE)." }

  Write-Host "Running installer on $Target ..."
  $remoteCmd = "bash '$remoteTmp' --tz '$Timezone'; rc=`$?; rm -f '$remoteTmp'; exit `$rc"
  & ssh -t $Target $remoteCmd
  if ($LASTEXITCODE -ne 0) { throw "Installer failed on $Target (exit $LASTEXITCODE)." }
}
finally {
  Remove-Item -LiteralPath $clean -Force -ErrorAction SilentlyContinue
}

Write-Host "Done."
