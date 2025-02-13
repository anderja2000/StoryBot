# Harry Potter Fanfic Model Creator
# Version 5.1 - Enhanced Validation

# Enhanced model check function
function Test-OllamaModel {
    param([string]$modelName)
    try {
        $models = ollama list | ForEach-Object { $_.Split()[0].Trim() }
        return $models -contains $modelName
    }
    catch {
        Write-Host "[ERROR] Ollama command failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Corrected model list
$models = @(
    [PSCustomObject]@{
        Name = "qwen2.5:0.5b-base-q2_k"
        RAM  = 1.2
    },
    [PSCustomObject]@{
        Name = "orca-mini:3b-q4_0"
        RAM  = 1.5
    },
    [PSCustomObject]@{
        Name = "Meta-Llama-3-7B-Instruct-Q3_K_S"
        RAM  = 1.8
    },
    [PSCustomObject]@{
        Name = "llama2:7b-chat-q5_K_M"
        RAM  = 5.5
    }
)

function Get-SystemMetrics {
    $os = Get-CimInstance Win32_OperatingSystem
    return [PSCustomObject]@{
        AvailableRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        HasGPU       = [bool](Get-WmiObject Win32_VideoController | 
            Where-Object { $_.VideoProcessor -match 'Intel|NVIDIA|AMD' })
    }
}

try {
    # System checks
    $system = Get-SystemMetrics
    Write-Host "[SYSTEM] Available RAM: $($system.AvailableRAM) GB"
    Write-Host "[SYSTEM] GPU Detected: $($system.HasGPU)"

    # Model selection
    $selectedModel = $models | 
        Where-Object { $_.RAM -le $system.AvailableRAM } |
        Sort-Object RAM -Descending |
        Select-Object -First 1

    if (-not $selectedModel) {
        throw "No compatible models for $($system.AvailableRAM)GB RAM"
    }
    Write-Host "[SELECTED] Base Model: $($selectedModel.Name)"

    # Enhanced model verification
    if (-not (Test-OllamaModel -modelName $selectedModel.Name)) {
        Write-Host "[ACTION] Pulling base model: $($selectedModel.Name)..."
        ollama pull $selectedModel.Name
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to pull model: $($selectedModel.Name)"
        }
    }

    # Create Modelfile with proper formatting
    $modelfileContent = @"
FROM $($selectedModel.Name)
PARAMETER num_ctx 2048
PARAMETER temperature 1.2
PARAMETER top_p 0.9

SYSTEM """
You are a creative AI specializing in Harry Potter fanfiction.
Focus on vivid descriptions and magical world-building.
Stay true to the original series' tone and themes.
"""
"@

    # File creation with proper encoding
    $modelfilePath = "$PWD\Modelfile"
    $modelfileContent = $modelfileContent -replace "`r`n","`n"  # Normalize line endings
    Set-Content -Path $modelfilePath -Value $modelfileContent -Encoding utf8

    # Model creation
    Write-Host "[ACTION] Creating hp-fanfic model..."
    $creation = ollama create hp-fanfic -f $modelfilePath 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Creation failed: $creation"
    }

    # Verification with retries
    $maxRetries = 5
    $retryCount = 0
    do {
        Start-Sleep -Seconds 3
        $modelsList = ollama list
        $retryCount++
    } while (-not ($modelsList -match "hp-fanfic") -and $retryCount -le $maxRetries)

    if ($modelsList -match "hp-fanfic") {
        Write-Host "[SUCCESS] Model created!"
        ollama list | Select-String "hp-fanfic"
        
        # Start server
        Write-Host "[ACTION] Starting Ollama server..."
        Start-Process powershell -ArgumentList "-NoExit ollama serve"
    }
    else {
        throw "Model not found after creation attempts"
    }
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    exit 1
}

Read-Host "Press Enter to exit"
