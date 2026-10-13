<#
.SYNOPSIS
Opens Bytefray Spectator on the verified P0-C showcase fixture
(spectator_harrier vs spectator_bastion, seed 427, Bastion captures at tick 477).

.DESCRIPTION
The viewer verifies every presentation file against manifest.json before it
shows anything. The same options always give the same starting view.

.EXAMPLE
./launch_showcase.ps1
./launch_showcase.ps1 -Perspective agent_a -Tick 440 -Speed 20 -Play
#>
param(
    [ValidateSet("broadcast", "agent_a")][string]$Perspective = "broadcast",
    [ValidateRange(0, 1000)][int]$Tick = 0,
    [ValidateSet(1, 2, 5, 10, 20, 60, 200)][int]$Speed = 5,
    [switch]$Play,
    [ValidateSet("classic", "filled_arcs")][string]$Rendering = "filled_arcs",
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" }),
    # For automated launch checks: quit after this many frames (0 = stay open).
    [int]$QuitAfter = 0
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot 4.7.2 not found at '$Godot'. Pass -Godot <path> or set GODOT."
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".godot"))) {
    & $Godot --headless --path $PSScriptRoot --import | Out-Null
}
$viewerArgs = @("--fixture=showcase", "--perspective=$Perspective", "--tick=$Tick", "--speed=$Speed", "--rendering=$Rendering")
if ($Play) { $viewerArgs += "--play" }
$godotArgs = @("--path", $PSScriptRoot)
if ($QuitAfter -gt 0) { $godotArgs += @("--quit-after", "$QuitAfter") }
& $Godot @godotArgs -- @viewerArgs
