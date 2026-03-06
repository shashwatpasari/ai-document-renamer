#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$OllamaStartedByScript = $false
$OllamaProcess = $null

function Ensure-Ollama {
    # Check if server is running AND version matches CLI
    try {
        $output = & ollama list 2>&1 | Out-String
        if ($output -match "client version is") {
            # Version mismatch — kill stale server, restart from CLI
            Write-Host "Detected Ollama version mismatch. Restarting server..."
            Get-Process -Name "ollama" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } elseif ($LASTEXITCODE -eq 0) {
            return
        }
    } catch {}

    # Start server
    $ollamaPath = (Get-Command ollama -ErrorAction Stop).Source
    $script:OllamaProcess = Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden -PassThru
    $script:OllamaStartedByScript = $true

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try {
            $null = & ollama list 2>$null
            if ($LASTEXITCODE -eq 0) { return }
        } catch {}
    }

    Write-Host "Could not start Ollama server."
    exit 1
}

function Stop-OllamaIfStarted {
    if ($script:OllamaStartedByScript -and $script:OllamaProcess -and (-not $script:OllamaProcess.HasExited)) {
        Stop-Process -Id $script:OllamaProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

# Cleanup on exit
$null = Register-EngineEvent PowerShell.Exiting -Action { Stop-OllamaIfStarted }
trap { Stop-OllamaIfStarted }

# Activate venv
$pythonBin = Join-Path $ScriptDir "venv\Scripts\python.exe"
if (-not (Test-Path $pythonBin)) {
    Write-Host "Virtual environment not found. Run install_windows.ps1 first."
    exit 1
}

# Ensure Ollama is running
Ensure-Ollama

# Run the processor
& $pythonBin (Join-Path $ScriptDir "run.py") @args

# Cleanup
Stop-OllamaIfStarted
