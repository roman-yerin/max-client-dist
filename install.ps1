# max-client installer for Windows:
#   irm https://max.bythe.net/install.ps1 | iex
# Downloads max.exe from the latest release into %LOCALAPPDATA%\Programs\max
# (or $env:MAX_INSTALL_DIR) and adds that folder to the user PATH.
#
# ASCII only on purpose: Windows PowerShell 5.1 decodes `irm` output without
# a charset as Latin-1, so non-ASCII text would arrive garbled.
# Errors use `throw`, never `exit`: under `iex` exit would close the window.

& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue' # the progress bar slows downloads 10x in PS 5.1
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $Repo = 'roman-yerin/max-client-dist'
  $Dest = if ($env:MAX_INSTALL_DIR) { $env:MAX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\max' }

  # 32-bit PowerShell on a 64-bit OS reports x86 here; the real arch is in W6432.
  $cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  $arch = switch ($cpu) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "install.ps1: unsupported CPU architecture: $cpu" }
  }
  $asset = "max-windows-$arch.exe"

  Write-Host "==> looking up the latest release of $Repo"
  $release = Invoke-RestMethod -UseBasicParsing -Headers @{ Accept = 'application/vnd.github+json' } `
    -Uri "https://api.github.com/repos/$Repo/releases/latest"
  $url = ($release.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1).browser_download_url
  if (-not $url) { throw "install.ps1: release $($release.tag_name) has no $asset" }

  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  $exe = Join-Path $Dest 'max.exe'
  $tmp = "$exe.download"
  Write-Host "==> downloading $asset ($($release.tag_name))"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
  try {
    Move-Item -Force -Path $tmp -Destination $exe
  } catch {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
    throw "install.ps1: cannot replace $exe - close running max and try again"
  }

  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not (($userPath -split ';') -contains $Dest)) {
    $newPath = if ($userPath) { "$userPath;$Dest" } else { $Dest }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "==> added $Dest to your PATH"
  }
  if (-not (($env:Path -split ';') -contains $Dest)) { $env:Path = "$env:Path;$Dest" }

  Write-Host "==> done: $exe"
  Write-Host "==> run: max   (Windows Terminal is recommended)"
}
