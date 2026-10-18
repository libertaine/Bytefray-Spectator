<#
.SYNOPSIS
Builds standalone Bytefray Spectator executables with Godot 4.7.2.

.DESCRIPTION
Copies packaging/export_presets.cfg into place for the export (the project-root
copy is git-ignored and is restored or removed afterwards), imports the project,
exports the chosen presets into build/<platform>/, and runs each Windows build's
--check against the bundled presentations. A Linux build is exported here but
must be checked on Linux (see packaging/build.sh).

Requires Godot 4.7.2 and its export templates (Editor > Manage Export Templates).

.EXAMPLE
./packaging/build.ps1
./packaging/build.ps1 -Platform Windows -Godot 'C:/path/to/Godot_v4.7.2-stable_win64_console.exe'
#>
param(
    [ValidateSet("All", "Windows", "Linux")][string]$Platform = "All",
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe" })
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot 4.7.2 not found at '$Godot'. Pass -Godot <path> or set GODOT."
}
$presets = Join-Path $project "export_presets.cfg"
$backup = $null
if (Test-Path -LiteralPath $presets) {
    $backup = "$presets.user-backup"
    Move-Item -LiteralPath $presets -Destination $backup -Force
}
$targets = @()
if ($Platform -in "All", "Windows") { $targets += @{ Preset = "Windows Desktop"; Out = "build/windows/bytefray-spectator.exe" } }
if ($Platform -in "All", "Linux") { $targets += @{ Preset = "Linux"; Out = "build/linux/bytefray-spectator.x86_64" } }
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "export_presets.cfg") -Destination $presets
    & $Godot --headless --path $project --import | Out-Null
    foreach ($target in $targets) {
        $out = Join-Path $project $target.Out
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
        & $Godot --headless --path $project --export-release $target.Preset $out
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out -PathType Leaf)) {
            throw "Export of '$($target.Preset)' failed (exit $LASTEXITCODE)."
        }
        $hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLower()
        Write-Host "$($target.Preset): $out ($((Get-Item -LiteralPath $out).Length) bytes, sha256 $hash)"
    }
}
finally {
    Remove-Item -LiteralPath $presets -Force -ErrorAction SilentlyContinue
    if ($backup) { Move-Item -LiteralPath $backup -Destination $presets -Force }
}
foreach ($target in $targets | Where-Object { $_.Preset -eq "Windows Desktop" }) {
    $exe = Join-Path $project $target.Out
    foreach ($fixture in "showcase", "dev", "sample") {
        # A GUI-subsystem executable: Start-Process -Wait is what waits for it
        # and reports its exit code (the call operator returns immediately).
        $out = New-TemporaryFile
        $err = New-TemporaryFile
        try {
            $process = Start-Process -FilePath $exe -ArgumentList @("--headless", "--", "--fixture=$fixture", "--check") `
                -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
            Get-Content -LiteralPath $out, $err | Select-String "PRESENTATION|CUE BANK" | ForEach-Object { Write-Host $_.Line }
            if ($process.ExitCode -ne 0) {
                throw "The exported Windows build failed its --check on '$fixture' (exit $($process.ExitCode))."
            }
        }
        finally {
            Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
        }
    }
}
