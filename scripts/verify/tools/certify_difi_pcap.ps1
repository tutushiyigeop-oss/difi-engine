#requires -Version 5.1
<# Validate PCAPs with the DIFI checker. OutputDir is optional; ReportDir is the old name. Requires an installed Python environment and certify_source.py. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PcapDir,

    [Parameter(Position = 1)]
    [Alias('ReportDir')]
    [string]$OutputDir = '',

    [string]$ToolDir = 'D:\Study\tools\DIFI-Certification-main'
)

$ErrorActionPreference = 'Stop'

function Read-Counter {
    param([string]$Text, [string]$Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + ':\s*(\d+)\s*$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups[1].Value
}

function Invoke-DifiValidation {
    param(
        [string]$Label,
        [string]$InputPcap,
        [string]$OutDirectory,
        [string]$PythonExe,
        [string]$Validator,
        [string]$FlowKind
    )

    [void](New-Item -ItemType Directory -Force -Path $OutDirectory)

    $consoleFile = Join-Path $OutDirectory 'console.txt'
    $errorLog = Join-Path $OutDirectory 'error_log.txt'
    $stdoutTemp = Join-Path $OutDirectory '_stdout.tmp'
    $stderrTemp = Join-Path $OutDirectory '_stderr.tmp'

    # Quote paths to support spaces.
    $arguments = '"{0}" --pcap "{1}" --difi-version 1.1 --error-log "{2}"' -f $Validator, $InputPcap, $errorLog

    Write-Host ""
    Write-Host ('[RUN] ' + $Label) -ForegroundColor Cyan
    Write-Host ('[PCAP] ' + $InputPcap)

    $process = Start-Process -FilePath $PythonExe -ArgumentList $arguments `
        -WorkingDirectory $OutDirectory -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutTemp -RedirectStandardError $stderrTemp
    $exitCode = $process.ExitCode

    # An empty file may return null; convert it to a string first.
    $stdout = if (Test-Path -LiteralPath $stdoutTemp) { [string](Get-Content -LiteralPath $stdoutTemp -Raw) } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrTemp) { [string](Get-Content -LiteralPath $stderrTemp -Raw) } else { '' }

    $consoleSections = @(
        'DIFI Consortium original certify_source.py / DIFI 1.1',
        ('PCAP: ' + $InputPcap),
        ('Validator: ' + $Validator),
        ('Validator SHA256: ' + (Get-FileHash -LiteralPath $Validator -Algorithm SHA256).Hash),
        ('PCAP SHA256: ' + (Get-FileHash -LiteralPath $InputPcap -Algorithm SHA256).Hash),
        ('Run at: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        '----- STDOUT -----',
        $stdout,
        '----- STDERR (diagnostics/warnings) -----',
        $stderr,
        ('Process exit code: ' + $exitCode)
    )
    $consoleSections | Set-Content -LiteralPath $consoleFile -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-Host '[STDERR] See console.txt for diagnostics (Git-ZIP warning is normally harmless).' -ForegroundColor Yellow
    }

    Remove-Item -LiteralPath $stdoutTemp, $stderrTemp -Force -ErrorAction SilentlyContinue

    $cv = Read-Counter $stdout 'compliant_version_count'
    $nv = Read-Counter $stdout 'noncompliant_version_count'
    $cc = Read-Counter $stdout 'compliant_context_count'
    $nc = Read-Counter $stdout 'noncompliant_context_count'
    $cd = Read-Counter $stdout 'compliant_data_count'
    $nd = Read-Counter $stdout 'noncompliant_data_count'

    $allCounts = @($cv, $nv, $cc, $nc, $cd, $nd)
    $haveCounts = $true
    foreach ($value in $allCounts) {
        if ($null -eq $value) { $haveCounts = $false; break }
    }

    $actualPackets = -1
    if (Test-Path -LiteralPath $errorLog) {
        $errorText = [string](Get-Content -LiteralPath $errorLog -Raw)
        $match = [regex]::Match($errorText, 'Total packets processed:\s*(\d+)')
        if ($match.Success) { $actualPackets = [int]$match.Groups[1].Value }
    }

    $valid = (($exitCode -eq 0) -and ($stdout -match '(?m)^Overall Result:\s*PASS\s*$') -and $haveCounts -and ($actualPackets -gt 0))

    $packetTotal = -1
    if ($haveCounts) {
        $packetTotal = $cv + $nv + $cc + $nc + $cd + $nd
        $valid = $valid -and ($actualPackets -eq $packetTotal) -and
                 ($nv -eq 0) -and ($nc -eq 0) -and ($nd -eq 0)
        if ($FlowKind -eq 'version') {
            $valid = $valid -and ($cv -ge 1) -and ($cc -eq 0) -and ($cd -eq 0)
        } else {
            $valid = $valid -and ($cv -eq 0) -and ($cc -ge 1) -and ($cd -ge 1)
        }
    }

    $decision = if ($valid) { 'PASS' } else { 'FAIL' }
    $reportLines = @(
        'Test: ' + $Label,
        'Result: ' + $decision,
        'DIFI version: 1.1',
        'PCAP: ' + $InputPcap,
        'PCAP SHA256: ' + (Get-FileHash -LiteralPath $InputPcap -Algorithm SHA256).Hash,
        'Validator: ' + $Validator,
        'Validator SHA256: ' + (Get-FileHash -LiteralPath $Validator -Algorithm SHA256).Hash,
        'Exit code: ' + $exitCode,
        'Packets processed: ' + $actualPackets,
        'Packets counted in DIFI categories: ' + $packetTotal,
        'Version compliant/noncompliant: ' + $cv + '/' + $nv,
        'Context compliant/noncompliant: ' + $cc + '/' + $nc,
        'Data compliant/noncompliant: ' + $cd + '/' + $nd,
        'NOTE: Original validator; split-flow testing, not a formal DIFI certification.'
    )
    $reportLines | Set-Content -LiteralPath (Join-Path $OutDirectory 'result.txt') -Encoding UTF8

    Write-Host ('[RESULT] ' + $Label + ': ' + $decision + ' (' + $actualPackets + ' packet(s))') -ForegroundColor $(if ($valid) { 'Green' } else { 'Red' })
    Write-Host ('[SAVED] ' + $OutDirectory)
    return [bool]$valid
}

try {
    if (-not (Test-Path -LiteralPath $PcapDir -PathType Container)) {
        throw ('PCAP directory does not exist: ' + $PcapDir)
    }
    $PcapDir = (Resolve-Path -LiteralPath $PcapDir).ProviderPath
    $ToolDir = [System.IO.Path]::GetFullPath($ToolDir)

    $pythonExe = Join-Path $ToolDir '.venv\Scripts\python.exe'
    $validator = Join-Path $ToolDir 'certify_source.py'
    if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) { throw ('Python venv not found: ' + $pythonExe) }
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw ('Official validator not found: ' + $validator) }

    $verCandidates = @(Get-ChildItem -LiteralPath $PcapDir -File -Filter '*version_flow.pcap')
    $dataCandidates = @(Get-ChildItem -LiteralPath $PcapDir -File -Filter '*data_context_flow.pcap')
    if ($verCandidates.Count -ne 1) {
        throw ('Expected exactly one *version_flow.pcap; found ' + $verCandidates.Count + ' in ' + $PcapDir)
    }
    if ($dataCandidates.Count -ne 1) {
        throw ('Expected exactly one *data_context_flow.pcap; found ' + $dataCandidates.Count + ' in ' + $PcapDir)
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $parentDir = Split-Path -Parent $PcapDir
        if ((Split-Path -Leaf $parentDir) -ieq 'pcap') {
            $verificationDir = Split-Path -Parent $parentDir
            $OutputDir = Join-Path (Join-Path $verificationDir 'reports') (Split-Path -Leaf $PcapDir)
        } else {
            $OutputDir = Join-Path $PcapDir 'reports'
        }
    }
    $OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

    Write-Host ('[INPUT] ' + $PcapDir)
    Write-Host ('[OUTPUT] ' + $OutputDir)

    $verOK = Invoke-DifiValidation -Label 'Version Flow' -InputPcap $verCandidates[0].FullName `
        -OutDirectory (Join-Path $OutputDir 'version') -PythonExe $pythonExe `
        -Validator $validator -FlowKind 'version'

    $dataOK = Invoke-DifiValidation -Label 'Data + Context Flow' -InputPcap $dataCandidates[0].FullName `
        -OutDirectory (Join-Path $OutputDir 'data_context') -PythonExe $pythonExe `
        -Validator $validator -FlowKind 'data_context'

    $overall = if ($verOK -and $dataOK) { 'PASS' } else { 'FAIL' }
    @(
        'DIFI 1.1 split-flow offline verification',
        ('Result: ' + $overall),
        ('PCAP directory: ' + $PcapDir),
        ('Version Flow: ' + $(if ($verOK) { 'PASS' } else { 'FAIL' })),
        ('Data + Context Flow: ' + $(if ($dataOK) { 'PASS' } else { 'FAIL' })),
        ('Report directory: ' + $OutputDir),
        'Original combined-stream PCAP was NOT tested for cross-stream consistency.',
        'No Ethernet/UDP physical transfer or official consortium certification is claimed.'
    ) | Set-Content -LiteralPath (Join-Path $OutputDir 'summary.txt') -Encoding UTF8

    Write-Host ''
    Write-Host ('[OVERALL] ' + $overall) -ForegroundColor $(if ($verOK -and $dataOK) { 'Green' } else { 'Red' })
    Write-Host ('[REPORTS] ' + $OutputDir)
    if (-not ($verOK -and $dataOK)) { exit 1 }
    exit 0
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    exit 2
}
