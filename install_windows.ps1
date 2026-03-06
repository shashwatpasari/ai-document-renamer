#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Project folder
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModelName = "gemma3:4b"
$OllamaStartedByScript = $false
$OllamaProcess = $null

function Wait-ForOllama {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $output = & ollama list 2>&1
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {}
        Start-Sleep -Seconds 1
    }
    return $false
}

function Start-OllamaServer {
    $ollamaPath = (Get-Command ollama -ErrorAction SilentlyContinue).Source
    if (-not $ollamaPath) {
        Write-Host "Ollama not found."
        return $false
    }
    $script:OllamaProcess = Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden -PassThru
    $script:OllamaStartedByScript = $true
    return (Wait-ForOllama)
}

function Stop-OllamaIfStarted {
    if ($script:OllamaStartedByScript -and $script:OllamaProcess -and (-not $script:OllamaProcess.HasExited)) {
        Stop-Process -Id $script:OllamaProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

# Cleanup on exit
$null = Register-EngineEvent PowerShell.Exiting -Action { Stop-OllamaIfStarted }
trap { Stop-OllamaIfStarted }

# ── 1) Install Python if missing ──
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Host "Python not found. Installing via winget..."
    winget install --id Python.Python.3.13 --accept-source-agreements --accept-package-agreements
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        Write-Host "Python installation failed. Please install Python manually from https://www.python.org"
        exit 1
    }
}

$PythonBin = $pythonCmd.Source
Write-Host "Using Python: $PythonBin"

# ── 2) Install Ollama if missing ──
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-Host "Ollama not found. Installing via winget..."
    winget install --id Ollama.Ollama --accept-source-agreements --accept-package-agreements
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCmd) {
        Write-Host "Ollama installation failed. Please install manually from https://ollama.com"
        exit 1
    }
}

# ── 3) Handle version mismatch ──
try {
    $ollamaCheck = & ollama list 2>&1 | Out-String
    if ($ollamaCheck -match "client version is") {
        Write-Host "Detected Ollama version mismatch. Restarting server..."
        Get-Process -Name "ollama" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
} catch {}

# ── 4) Ensure Ollama server is running ──
try {
    $null = & ollama list 2>$null
    if ($LASTEXITCODE -ne 0) { throw "not running" }
} catch {
    Write-Host "Starting Ollama server..."
    if (-not (Start-OllamaServer)) {
        Write-Host "Could not start Ollama automatically. Please start Ollama manually and rerun."
        exit 1
    }
}

# ── 5) Pull model if missing ──
try {
    $null = & ollama show $ModelName 2>$null
    if ($LASTEXITCODE -ne 0) { throw "not found" }
} catch {
    Write-Host "Pulling model $ModelName ..."
    & ollama pull $ModelName
}

# ── 6) Create venv if missing ──
$venvPath = Join-Path $ScriptDir "venv"
if (-not (Test-Path $venvPath)) {
    Write-Host "Creating virtual environment..."
    & $PythonBin -m venv $venvPath
}

# ── 7) Activate venv and install libs ──
$pipBin = Join-Path $venvPath "Scripts\pip.exe"
$packages = @("pymupdf", "pillow", "ollama")
foreach ($pkg in $packages) {
    $installed = & $pipBin show $pkg 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installing $pkg ..."
        & $pipBin install $pkg
    }
}

# ── 8) Ask for input folder ──
Write-Host ""
Write-Host "Where is the folder containing your documents?"
Write-Host "Tip: Copy and paste the folder path, then press Enter."
$InputFolder = Read-Host "Folder path"

# Clean path
$InputFolder = $InputFolder.Trim().Trim('"').Trim("'").TrimEnd('\')

if (-not (Test-Path $InputFolder -PathType Container)) {
    Write-Host "Folder not found. Please run setup again."
    exit 1
}

# ── 9) Create output folder ──
$OutputFolder = Join-Path (Split-Path $InputFolder -Parent) "Renamed Documents"
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# ── 10) Write config.py ──
$configContent = @"
INPUT_FOLDER = r"$InputFolder"
OUTPUT_FOLDER = r"$OutputFolder"
MODEL = "$ModelName"
SUPPORTED_EXTENSIONS = [".pdf", ".jpg", ".jpeg", ".png"]
DRY_RUN = False
"@
$configContent | Set-Content -Path (Join-Path $ScriptDir "config.py") -Encoding UTF8

Write-Host ""
Write-Host "Done!"
Write-Host "Output folder: $OutputFolder"
Write-Host "Run now: .\run_now_windows.ps1"

# Cleanup
Stop-OllamaIfStarted
