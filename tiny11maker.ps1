<#
.SYNOPSIS
    tiny11maker - noninteractive production version
.DESCRIPTION
    Headless-safe wrapper for the tiny11maker Windows image process.
    Supports:
      -ISO <drive-letter-or-iso-path>
      -SCRATCH <drive-letter>
      -OutputPath <path>
      -NonInteractive
      -SkipAdminPrompt
#>

[CmdletBinding()]
param(
    [string]$ISO,
    [string]$SCRATCH,
    [string]$OutputPath,
    [switch]$NonInteractive,
    [switch]$SkipAdminPrompt
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-DriveLetter {
    param([string]$InputValue)

    if (-not $InputValue) { return $null }

    if ($InputValue -match '^[A-Za-z]$') {
        return ($InputValue.TrimEnd(':') + ':')
    }

    if ($InputValue -match '^[A-Za-z]:\\') {
        return $InputValue.TrimEnd('\')
    }

    if ($InputValue -match '\.iso$') {
        $mounted = Mount-DiskImage -ImagePath $InputValue -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 2
        $volume = $mounted | Get-DiskImage | Get-Volume -ErrorAction SilentlyContinue
        if (-not $volume) {
            throw "Failed to mount ISO: $InputValue"
        }
        return ($volume.DriveLetter + ':')
    }

    return $InputValue
}

function Ensure-Autounattend {
    $autounattend = Join-Path $PSScriptRoot 'autounattend.xml'
    if (-not (Test-Path $autounattend)) {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml' -OutFile $autounattend -UseBasicParsing
    }
}

function Invoke-AdminOrExit {
    if ($SkipAdminPrompt) { return }
    if (-not (Test-IsAdmin)) {
        if ($NonInteractive) {
            throw 'tiny11maker requires Administrator privileges in non-interactive mode.'
        }
        $scriptPath = $MyInvocation.MyCommand.Path
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" @args"
        $psi.Verb = 'runas'
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
}

# ---- startup ----
Invoke-AdminOrExit

if (-not $SCRATCH) {
    $ScratchDisk = Join-Path $env:TEMP 'tiny11-maker'
} else {
    $ScratchDisk = $SCRATCH.TrimEnd('\')
    if ($ScratchDisk.Length -eq 1) { $ScratchDisk = "$ScratchDisk:" }
}

$ScratchDisk = ($ScratchDisk.TrimEnd('\') + '')
$ScratchDisk = $ScratchDisk.TrimEnd(':')

if ($ScratchDisk -match '^[A-Za-z]$') {
    $ScratchDisk = "$ScratchDisk:"
}

New-Item -ItemType Directory -Path $ScratchDisk -Force | Out-Null

Ensure-Autounattend

if (-not $ISO) {
    if (-not $NonInteractive) {
        $ISO = Read-Host 'Please enter the drive letter or ISO path for the Windows 11 image'
    } else {
        throw 'ISO is required when running in non-interactive mode.'
    }
}

$ResolvedISO = Resolve-DriveLetter -InputValue $ISO
if (-not $ResolvedISO) { throw 'Unable to resolve ISO drive/path.' }

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot 'tiny11.iso'
}

# Keep the original script behavior below this point.
# The rest of the existing script can remain as-is.
# The key fix is that the script no longer blocks on Read-Host in CI.
