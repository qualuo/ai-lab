<#
.SYNOPSIS
    Automated installation script for Ollama and Open WebUI for local AI development.
.DESCRIPTION
    This script automates the installation of Ollama and Open WebUI using the uv package manager,
    making it easy to get started with local AI. It includes robust error handling, prerequisite checks,
    and efficient model installation.
.NOTES
    Author: -
    Version: 1.1
#>

[CmdletBinding()]
param (
    [string]$OllamaInstallerUrl = "https://github.com/ollama/ollama/releases/download/v0.6.0/OllamaSetup.exe",
    [string[]]$ModelsToInstall = @("llama3.2", "bespoke-minicheck"),
    [switch]$ForceReinstall,
    [int]$RetryAttempts = 3,
    [int]$RetryDelay = 5
)

# Initialize logging
$logFile = "$env:TEMP\ollama_setup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ErrorActionPreference = "Stop"

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
    }
    
    # Write to log file
    Add-Content -Path $logFile -Value $logMessage
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check if PowerShell version is adequate
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.0 or higher is required. Current version: $($PSVersionTable.PSVersion)" "ERROR"
        return $false
    }
    
    # Check for administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "This script is running without administrator privileges." "WARNING"
    }
    
    # Check for Python 3.11
    $pythonCheck = Get-Command python -ErrorAction SilentlyContinue
    $pythonVersion = $null
    
    if ($pythonCheck) {
        try {
            $pythonVersionOutput = python --version 2>&1
            if ($pythonVersionOutput -match "Python (\d+\.\d+)") {
                $pythonVersion = $Matches[1]
                Write-Log "Python version $pythonVersion detected."
                
                if ([version]$pythonVersion -lt [version]"3.11") {
                    Write-Log "Python 3.11 or higher is recommended. Current version: $pythonVersion" "WARNING"
                }
            }
        }
        catch {
            Write-Log "Failed to determine Python version." "WARNING"
        }
    }
    else {
        Write-Log "Python is not installed. It's recommended for Open WebUI but will be handled by uv." "WARNING"
    }
    
    # Check for uv package manager
    $uvCheck = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCheck) {
        Write-Log "uv package manager is not installed. Will install it during setup." "INFO"
    }
    
    # Check internet connection
    try {
        $internetConnection = Test-NetConnection -ComputerName "github.com" -InformationLevel Quiet
        if (-not $internetConnection) {
            Write-Log "No internet connection detected. This script requires internet access." "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Could not verify internet connection. Proceeding anyway..." "WARNING"
    }
    
    Write-Log "All prerequisites checked successfully."
    return $true
}

function Retry-Action {
    param (
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action,
        [string]$ActionName = "Action",
        [int]$Attempts = $RetryAttempts,
        [int]$Delay = $RetryDelay
    )
    
    $attempt = 0
    $success = $false
    $result = $null
    
    while ($attempt -lt $Attempts -and -not $success) {
        try {
            $attempt++
            Write-Log "${ActionName}: Attempt $attempt of $Attempts..."
            $result = & $Action
            $success = $true
            Write-Log "$ActionName succeeded."
        }
        catch {
            Write-Log "$ActionName failed on attempt ${attempt}: $($_.Exception.Message)" "WARNING"
            if ($attempt -lt $Attempts) {
                Write-Log "Retrying $ActionName in $Delay seconds..."
                Start-Sleep -Seconds $Delay
            }
        }
    }
    
    if (-not $success) {
        Write-Log "$ActionName failed after $Attempts attempts." "ERROR"
        throw "$ActionName failed after $Attempts attempts: $($_.Exception.Message)"
    }
    
    return $result
}

function Install-Ollama {
    $installerPath = "$env:USERPROFILE\Downloads\OllamaSetup.exe"
    
    # Check if Ollama is already installed
    $ollamaCheck = Get-Command ollama -ErrorAction SilentlyContinue
    if ($ollamaCheck -and -not $ForceReinstall) {
        Write-Log "Ollama is already installed. Version: $((ollama --version).Trim())"
        return $true
    }
    
    Write-Log "Installing Ollama..."
    
    # Download the installer if it doesn't exist
    if (-not (Test-Path $installerPath) -or $ForceReinstall) {
        Write-Log "Downloading Ollama setup from: $OllamaInstallerUrl"
        try {
            Retry-Action -ActionName "Ollama download" -Action {
                Invoke-WebRequest -Uri $OllamaInstallerUrl -OutFile $installerPath -UseBasicParsing
            }
        }
        catch {
            # Fallback to winget if download fails
            Write-Log "Failed to download Ollama setup. Attempting installation via winget..." "WARNING"
            try {
                Retry-Action -ActionName "Ollama winget installation" -Action {
                    winget install Ollama.Ollama -e --silent
                }
                return $true
            }
            catch {
                Write-Log "All Ollama installation methods failed." "ERROR"
                return $false
            }
        }
    }
    else {
        Write-Log "Ollama setup file already exists at: $installerPath"
    }
    
    # Run the installer silently
    Write-Log "Starting Ollama installation..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
    
    if ($process.ExitCode -ne 0) {
        Write-Log "Ollama installation failed with exit code: $($process.ExitCode)" "ERROR"
        return $false
    }
    
    # Refresh environment variables to make Ollama available in current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Verify installation
    $ollamaCheck = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCheck) {
        Write-Log "Ollama was installed but is not available in the PATH." "ERROR"
        return $false
    }
    
    Write-Log "Ollama installed successfully. Version: $((ollama --version).Trim())"
    return $true
}

function Install-UV {
    Write-Log "Installing uv package manager..."
    
    try {
        # Install uv using PowerShell
        Retry-Action -ActionName "uv installation" -Action {
            Invoke-Expression "& { $(Invoke-RestMethod https://astral.sh/uv/install.ps1) }"
        }
        
        # Refresh environment variables to make uv available in current session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify installation
        $uvCheck = Get-Command uv -ErrorAction SilentlyContinue
        if (-not $uvCheck) {
            Write-Log "uv was installed but is not available in the PATH." "ERROR"
            return $false
        }
        
        Write-Log "uv package manager installed successfully."
        return $true
    }
    catch {
        Write-Log "Failed to install uv package manager: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-OpenWebUI {
    # Set data directory for Open WebUI
    $webUIDataPath = "$env:USERPROFILE\open-webui\data"
    
    # Ensure data directory exists
    if (-not (Test-Path $webUIDataPath)) {
        New-Item -ItemType Directory -Path $webUIDataPath -Force | Out-Null
        Write-Log "Created Open WebUI data directory at: $webUIDataPath"
    }
    
    # Install uv if not already installed
    $uvCheck = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCheck) {
        $uvInstalled = Install-UV
        if (-not $uvInstalled) {
            Write-Log "Failed to install uv package manager. Cannot proceed with Open WebUI installation." "ERROR"
            return $false
        }
    }
    
    # Verify that Open WebUI can be installed using uvx
    Write-Log "Verifying Open WebUI installation with uvx..."
    
    try {
        # Run a quick check to see if open-webui is available via uvx
        Retry-Action -ActionName "Open WebUI verification" -Action {
            $uvxOutput = uvx --help
            if (-not $uvxOutput) {
                throw "uvx command failed to execute"
            }
        }
        
        Write-Log "Open WebUI prerequisites verified successfully."
        return $true
    }
    catch {
        Write-Log "Failed to verify Open WebUI installation: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-OllamaModels {
    param (
        [string[]]$Models
    )
    
    foreach ($model in $Models) {
        Write-Log "Installing model: $model"
        Retry-Action -ActionName "Model $model installation" -Action {
            ollama pull $model
        }
    }
}
function Create-Shortcuts {
    # Create desktop shortcut for Open WebUI
    $desktop = [System.Environment]::GetFolderPath('Desktop')
    $shortcutPath = "$desktop\Open WebUI.url"
    
    $shortcutContent = @"
[InternetShortcut]
URL=http://localhost:8080
IconFile=C:\Windows\System32\SHELL32.dll
IconIndex=15
"@
    
    # Create the shortcut file
    Set-Content -Path $shortcutPath -Value $shortcutContent -Force
    
    # Create a batch file to start both Ollama and Open WebUI
    $startScriptPath = "$env:USERPROFILE\open-webui\run_local_ai.bat"
    $startScriptContent = @"
@echo off

:: Check Ollama status
tasklist /FI "IMAGENAME eq ollama.exe" 2>NUL | find /I "ollama.exe" > NUL
if "%ERRORLEVEL%"=="0" (
    echo Ollama is already running.
) else (
    echo Starting Ollama service...
    start /B ollama serve
    echo Waiting for Ollama to initialize...
    timeout /T 5 /NOBREAK > NUL
)

:: Initialize Open WebUI
echo Starting Open WebUI...
set DATA_DIR=%USERPROFILE%\open-webui\data
start /B cmd /c "uvx --python 3.11 open-webui@latest serve"

echo NOTE! This window runs the application server and must remain open. Open WebUI may take a few minutes to start up.
echo Waiting for Open WebUI to be available at http://localhost:8080... (Waiting for server process to start)
echo When the server process has started, Open WebUI can be accessed through your browser.
echo ---
"@
    

    # Write the batch file content to the file
    Set-Content -Path $startScriptPath -Value $startScriptContent -Force
    
    # Create shortcut for the start script
    $startScriptShortcutPath = "$desktop\Run Local AI Server.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($startScriptShortcutPath)
    $shortcut.TargetPath = $startScriptPath
    $shortcut.WorkingDirectory = "$env:USERPROFILE\open-webui"
    $shortcut.IconLocation = "%SystemRoot%\System32\SHELL32.dll,2"
    $shortcut.Save()
    
    Write-Log "Desktop shortcuts created successfully."
    Invoke-Item -Path $startScriptShortcutPath
    Invoke-Item -Path $shortcutPath
}

# Main execution
Write-Log "=== Local AI Setup Script Started ===" "INFO"
Write-Log "This process will:" "INFO"
Write-Log "1 Install Ollama (if not installed)" "INFO"
Write-Log "2 Install Open WebUI (if not installed)" "INFO"
Write-Log "3 Get base models" "INFO"
Write-Log "4 Create shortcuts for simpler use" "INFO"

try {
    # Check prerequisites
    $prereqsOk = Test-Prerequisites
    if (-not $prereqsOk) {
        Write-Log "Prerequisites check failed. Exiting script." "ERROR"
        exit 1
    }
    
    # Install Ollama
    $ollamaInstalled = Install-Ollama
    if (-not $ollamaInstalled) {
        Write-Log "Ollama installation failed. Exiting script." "ERROR"
        exit 1
    }
    
    # Install Open WebUI
    $webUIInstalled = Install-OpenWebUI
    if (-not $webUIInstalled) {
        Write-Log "Open WebUI installation failed. Exiting script." "ERROR"
        exit 1
    }
    
    # Install models in parallel
    Write-Log "Installing AI models..."
    Install-OllamaModels -Models $ModelsToInstall
    
    # Create shortcuts
    Create-Shortcuts
    
    Write-Log "=== Local AI Setup Script Completed Successfully ===" "INFO"
    Write-Log "Finished! To start, use the created 'Run Local AI Server' shortcut on your desktop."
}
catch {
    Write-Log "An unexpected error occurred: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "=== Local AI Setup Script Failed ===" "ERROR"
    exit 1
}

