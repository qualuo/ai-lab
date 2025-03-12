# Check if Docker is installed
$dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCheck) {
    Write-Host "🚀 Installing Docker..."
    Start-Process "https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe"
    Write-Host "⚠️ Please install Docker manually and restart this script."
    exit
}

# Pull & Run Ollama + Open WebUI
Write-Host "📥 Pulling and running Ollama + Open WebUI..."
docker run -d -p 3000:8080 -v ollama:/root/.ollama -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:ollama

# Open browser
Start-Process "http://localhost:3000"

Write-Host "✅ Installation complete! Open WebUI at: http://localhost:3000"

# Create a shortcut
$desktop = [System.Environment]::GetFolderPath('Desktop')
$shortcut = "$desktop\Open WebUI.url"
New-Item -ItemType File -Path $shortcut -Value "[InternetShortcut]`nURL=http://localhost:3000"
Write-Host "🖥️ Shortcut created on Desktop!"