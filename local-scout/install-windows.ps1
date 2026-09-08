$ErrorActionPreference = 'Stop'

Write-Host '=== Alpha Local Scout v1 ==='
Write-Host 'Research-only setup. No broker or banking access.'

function Test-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'python')) {
  Write-Host 'Python not found. Install Python 3.11+ from python.org, then rerun this script.'
  exit 1
}

if (-not (Test-Command 'node')) {
  Write-Host 'Node.js not found. Install Node.js 18+ from nodejs.org, then rerun this script.'
  exit 1
}

python -m venv .alpha-scout-venv
& .\.alpha-scout-venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install 'markitdown[all]' crawl4ai
crawl4ai-setup

Write-Host ''
Write-Host 'Checking Playwright MCP package...'
npx -y @playwright/mcp@latest --help | Out-Null

Write-Host ''
if (Test-Command 'ollama') {
  Write-Host 'Ollama detected.'
  ollama --version
} else {
  Write-Host 'Ollama is not installed yet.'
  Write-Host 'Install Ollama from ollama.com when you are at the PC, then pull a Gemma model appropriate for your RAM/GPU.'
}

Write-Host ''
Write-Host 'Testing MarkItDown import...'
python -c "from markitdown import MarkItDown; print('MarkItDown OK')"

Write-Host ''
Write-Host 'Testing Crawl4AI import...'
python -c "import crawl4ai; print('Crawl4AI OK')"

Write-Host ''
Write-Host 'SETUP COMPLETE.'
Write-Host 'Next: create a dedicated research-only browser profile and configure Playwright MCP using local-scout/playwright-mcp.example.json.'
Write-Host 'DO NOT log Zerodha, banking, Gmail, or other sensitive accounts into the Scout profile.'