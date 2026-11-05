# QA56: exported Windows build, opt-in live GPU/CPU resource and frame pacing capture.
# Run on a PHYSICAL Windows GTX1650-class device. Never claim headless CI is GPU evidence.
[CmdletBinding()]
param(
    [string]$Executable = "build\windows\LightsBackOn.exe",
    [string]$OutputDirectory = "build\qa56",
    [ValidateRange(120, 3600)][int]$MaxSeconds = 900,
    [ValidateRange(1, 10)][int]$SampleSeconds = 2,
    [switch]$PreflightOnly
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ($env:OS -ne "Windows_NT") { throw "QA56_REQUIRES_PHYSICAL_WINDOWS" }
$repo = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($Executable)) { $Executable = Join-Path $repo $Executable }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $repo $OutputDirectory }
$Executable = [IO.Path]::GetFullPath($Executable)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
# QA57: source pin + exported package preflight. This validates local package
# provenance; the running PCK boot line is checked separately after exit.
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "QA57_EXPORTED_EXE_NOT_FOUND: $Executable"
}
$packPath = [IO.Path]::ChangeExtension($Executable, ".pck")
$manifestPath = Join-Path (Split-Path -Parent $Executable) "build_manifest.json"
if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    throw "QA57_EXPORTED_PCK_NOT_FOUND: $packPath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "QA57_EXPORTED_MANIFEST_NOT_FOUND: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.engine_version -notmatch '^4[.]7[.]2[.]') {
    throw "QA57_WRONG_GODOT_VERSION"
}
if ([string]$manifest.git_commit -notmatch '^[0-9a-f]{40}$') {
    throw "QA57_UNPINNED_BUILD_COMMIT"
}
if ($manifest.git_dirty -ne $false) {
    throw "QA57_DIRTY_BUILD_REJECTED"
}
$gitExe = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitExe) { throw "QA57_GIT_REQUIRED_FOR_SOURCE_PIN" }
$checkoutCommit = (& $gitExe.Source -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $checkoutCommit -ne [string]$manifest.git_commit) {
    throw "QA57_SOURCE_BUILD_COMMIT_MISMATCH"
}
$hash = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
$packHash = (Get-FileHash -LiteralPath $packPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace([string]$manifest.build_id)) {
    throw "QA57_MISSING_BUILD_ID"
}
if ($PreflightOnly) {
    Write-Output "QA57_EXPORT_PREFLIGHT=PASS build=$($manifest.build_id) commit=$checkoutCommit"
    exit 0
}
$session = [Guid]::NewGuid().ToString("N")
$out = Join-Path $OutputDirectory $session
New-Item -ItemType Directory -Path $out -Force | Out-Null
$startUtc = [DateTime]::UtcNow
$controllers = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$videoControllers = @($controllers | Select-Object -ExpandProperty Name)
$rows = New-Object "System.Collections.Generic.List[object]"
$counterAvailable = $false
$timedOut = $false
$engineLog = Join-Path $out "godot.log"
# The quoted log path is a single Godot argument even under a directory with spaces.
$quotedEngineLog = '"' + $engineLog + '"'
$game = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) `
    -ArgumentList @("--log-file", $quotedEngineLog, "--", "--qa56-capture", "--qa56-id=$session") -PassThru
Write-Output "QA56_SESSION=$session PID=$($game.Id)"
Write-Output "QA56_ACTION=Use F9 to mark successive scenarios; navigate menu, mission, tablet, settings, pause, return, then QUIT."
try {
    while ($true) {
        $game.Refresh()
        if ($game.HasExited) { break }
        $elapsed = ([DateTime]::UtcNow - $startUtc).TotalSeconds
        if ($elapsed -ge $MaxSeconds) {
            $timedOut = $true
            Write-Warning "QA56: capture timed out; game process is left running (not killed)"
            break
        }
        $process = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
        if ($null -eq $process) { break }
        # Windows' per-PID dedicated usage counters differ by driver, locale and WDDM.
        # Absence is UNKNOWN, not zero; the analyzer will not qualify it.
        $gpuBytes = ""
        try {
            $samples = (Get-Counter -Counter "\GPU Process Memory(*)\Dedicated Usage" -ErrorAction Stop).CounterSamples
            $matched = @($samples | Where-Object { $_.Path -match ("(?i)pid_" + $game.Id + "_") })
            if ($matched.Count -gt 0) {
                $gpuBytes = [long][Math]::Round(
                    ($matched | Measure-Object -Property CookedValue -Sum).Sum)
                $counterAvailable = $true
            }
        } catch {
            # Explicitly record missing GPU data; do not fabricate VRAM values.
        }
        $rows.Add([pscustomobject]@{
            elapsed_s = $elapsed.ToString("F3", [Globalization.CultureInfo]::InvariantCulture)
            working_set_bytes = [long]$process.WorkingSet64
            private_bytes = [long]$process.PrivateMemorySize64
            gpu_dedicated_bytes = $gpuBytes
        })
        Start-Sleep -Seconds $SampleSeconds
    }
} finally {
    if ($rows.Count -gt 0) {
        $rows | Export-Csv -LiteralPath (Join-Path $out "resources.csv") `
            -NoTypeInformation -Encoding UTF8
    }
}
$videoControllers = @($videoControllers | Where-Object { $_ })
# Check the actual exported build's boot line, not just its adjacent manifest.
$runtimeBootVerified = $false
$engineLogHash = ""
if (Test-Path -LiteralPath $engineLog -PathType Leaf) {
    $logText = Get-Content -LiteralPath $engineLog -Raw
    $expectedBoot = 'Lights Back On boot \| engine 4[.]7[.]2[^\r\n]* \| build ' +
        [regex]::Escape([string]$manifest.build_id)
    $runtimeBootVerified = [regex]::IsMatch($logText, $expectedBoot)
    $engineLogHash = (Get-FileHash -LiteralPath $engineLog -Algorithm SHA256).Hash.ToLowerInvariant()
}
$metadata = [ordered]@{
    schema_version = 1
    session_id = $session
    capture_started_utc = $startUtc.ToString("o")
    executable_sha256 = $hash
    pack_sha256 = $packHash
    build_manifest_sha256 = $manifestHash
    executable_file_name = [IO.Path]::GetFileName($Executable)
    build_id = [string]$manifest.build_id
    git_commit = $checkoutCommit
    git_dirty = [bool]$manifest.git_dirty
    engine_version = [string]$manifest.engine_version
    sample_seconds = $SampleSeconds
    runtime_boot_manifest_verified = $runtimeBootVerified
    runtime_log_sha256 = $engineLogHash
    frame_csv_sha256 = ""
    resource_csv_sha256 = ""
    godot_expected_version = "4.7.2"
    windows_version = [Environment]::OSVersion.Version.ToString()
    video_controller_names = $videoControllers
    video_controller_driver_versions = @($controllers | ForEach-Object { [string]$_.DriverVersion })
    process_id = $game.Id
    exited_naturally = (-not $timedOut -and $game.HasExited -and $game.ExitCode -eq 0)
    process_exit_code = $(if ($game.HasExited) { $game.ExitCode } else { $null })
    process_samples = $rows.Count
    gpu_counter_seen = $counterAvailable
    capture_timed_out = $timedOut
    note = "Frame pacing is engine main-loop timing; GPU dedicated usage is OS counter data, not a display Present timestamp."
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out "metadata.json") -Encoding UTF8
# Godot keeps user:// isolated from the executable and existing save schema.
$appData = Join-Path $env:APPDATA "Godot\app_userdata"
$matches = @()
if (Test-Path -LiteralPath $appData -PathType Container) {
    $matches = @(Get-ChildItem -LiteralPath $appData -Filter "$session.csv" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq "qa56" })
}
if ($matches.Count -ne 1) {
    Write-Warning "QA56_FRAME_LOG_MISSING: expected one user://qa56/$session.csv"
    Write-Output "QA56_OUTPUT=$out STATUS=INCOMPLETE"
    exit 2
}
Copy-Item -LiteralPath $matches[0].FullName -Destination (Join-Path $out "frames.csv")
# Bind both samples to this local receipt; modification invalidates review.
$metadata["frame_csv_sha256"] = (
    Get-FileHash -LiteralPath (Join-Path $out "frames.csv") -Algorithm SHA256
).Hash.ToLowerInvariant()
$metadata["resource_csv_sha256"] = (
    Get-FileHash -LiteralPath (Join-Path $out "resources.csv") -Algorithm SHA256
).Hash.ToLowerInvariant()
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out "metadata.json") -Encoding UTF8
$py = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $py) {
    & python (Join-Path $repo "tools\qa56_analyze.py") `
        --frames (Join-Path $out "frames.csv") `
        --resources (Join-Path $out "resources.csv") `
        --output (Join-Path $out "report.json")
} else {
    & py -3 (Join-Path $repo "tools\qa56_analyze.py") `
        --frames (Join-Path $out "frames.csv") `
        --resources (Join-Path $out "resources.csv") `
        --output (Join-Path $out "report.json")
}
$result = $LASTEXITCODE
$qa57Args = @(
    (Join-Path $repo "tools\qa57_integrity.py"),
    "--metadata", (Join-Path $out "metadata.json"),
    "--frames", (Join-Path $out "frames.csv"),
    "--resources", (Join-Path $out "resources.csv"),
    "--report", (Join-Path $out "report.json"),
    "--boot-log", $engineLog,
    "--output", (Join-Path $out "integrity.json")
)
if ($null -ne $py) {
    & python @qa57Args
} else {
    & py -3 @qa57Args
}
$integrityResult = $LASTEXITCODE
Write-Output "QA56_OUTPUT=$out"
if ($timedOut -or -not $game.HasExited -or $game.ExitCode -ne 0) {
    Write-Warning "QA56_NOT_COMPLETE: process did not exit normally; capture cannot qualify"
    exit 2
}
if ($result -ne 0 -or $integrityResult -ne 0) { exit 2 }
Write-Output "QA57_CAPTURE_COMPLETE_FOR_PHYSICAL_REVIEW; physical UX and GPU acceptance remain pending."
