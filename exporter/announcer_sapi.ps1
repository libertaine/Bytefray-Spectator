<#
.SYNOPSIS
Renders one word with a Windows SAPI voice to a 22050 Hz 16-bit mono WAV file.
Used by make_announcer_voice.py; the same voice and text give the same bytes.
#>
param(
    [Parameter(Mandatory)][string]$Voice,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Out,
    [string]$Rate = "-10%",
    [string]$Pitch = "x-low"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $synth.SelectVoice($Voice)
    $synth.SetOutputToWaveFile($Out, $format)
    $escaped = [System.Security.SecurityElement]::Escape($Text)
    $synth.SpeakSsml("<speak version=`"1.0`" xmlns=`"http://www.w3.org/2001/10/synthesis`" xml:lang=`"en-US`"><prosody rate=`"$Rate`" pitch=`"$Pitch`">$escaped</prosody></speak>")
} finally {
    $synth.Dispose()
}
