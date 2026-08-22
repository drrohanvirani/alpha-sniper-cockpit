# Alpha Local Scout v1

Purpose: prepare a local research sidecar for Alpha OS without giving it broker/banking access.

Pipeline:

1. Browser Scout: Playwright MCP / Crawl4AI for research-only browsing.
2. Ingestion: Microsoft MarkItDown for PDFs, Office files, audio and YouTube transcripts.
3. Local model: Ollama + Gemma for cheap/private extraction and summarisation.
4. Memory: Supabase semantic memory is already live in Alpha OS.
5. CIO: Alpha/ChatGPT verifies primary evidence and makes portfolio recommendations.

## Safety

- Use a dedicated browser profile only for research sites.
- Do not log Zerodha, banking, Gmail or other sensitive accounts into the Scout profile.
- Local Gemma may extract/summarise evidence but must not place orders or make autonomous capital decisions.
- Primary evidence remains NSE/BSE/company IR before investment action.

## Windows quick setup

Open PowerShell in this repository and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\local-scout\install-windows.ps1
```

Then follow the on-screen checks.

## What gets installed

- Python packages: `markitdown[all]`, `crawl4ai`
- Playwright browser dependencies
- Node/npm check for Playwright MCP
- Ollama check/install guidance

## After install

1. Create a dedicated Chrome/Chromium research profile.
2. Configure your MCP-capable client with Playwright using the example in `playwright-mcp.example.json`.
3. Test MarkItDown with a public YouTube URL.
4. Pull a Gemma model in Ollama only after checking PC RAM/GPU.

This branch is setup-only. Nothing runs on the PC until the user executes the installer.