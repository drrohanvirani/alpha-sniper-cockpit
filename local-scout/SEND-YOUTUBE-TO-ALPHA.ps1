$ErrorActionPreference = 'Stop'

$tokenFile = Join-Path $HOME '.alpha-scout-token'
if (-not (Test-Path $tokenFile)) {
  Write-Host ''
  Write-Host 'FIRST TIME ONLY'
  $pairingCode = Read-Host 'Paste Alpha Scout pairing code'
  if ([string]::IsNullOrWhiteSpace($pairingCode)) { throw 'Pairing code required.' }
  Set-Content -Path $tokenFile -Value $pairingCode.Trim() -NoNewline
}
$token = (Get-Content $tokenFile -Raw).Trim()

$url = Read-Host 'Paste YouTube link'
if ([string]::IsNullOrWhiteSpace($url)) { throw 'YouTube link required.' }

Write-Host 'Reading transcript...'
$py = @'
import sys,re
from urllib.parse import urlparse,parse_qs
from youtube_transcript_api import YouTubeTranscriptApi
u=sys.argv[1].strip()
vid=None
if 'youtu.be/' in u:
    vid=urlparse(u).path.strip('/').split('/')[0]
else:
    q=parse_qs(urlparse(u).query)
    vid=(q.get('v') or [None])[0]
if not vid:
    m=re.search(r'(?:v=|youtu\.be/|shorts/)([A-Za-z0-9_-]{11})',u)
    vid=m.group(1) if m else None
if not vid:
    raise SystemExit('Could not find YouTube video id')
t=YouTubeTranscriptApi().fetch(vid)
print('\n'.join(x.text for x in t))
'@

$tmpPy = Join-Path $env:TEMP 'alpha_scout_youtube.py'
Set-Content -Path $tmpPy -Value $py -Encoding UTF8
$text = (& python $tmpPy $url | Out-String).Trim()
Remove-Item $tmpPy -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($text)) { throw 'Transcript was empty.' }

$body = @{
  device_id = $env:COMPUTERNAME
  kind = 'YOUTUBE_TRANSCRIPT'
  source_url = $url
  title = ''
  text = $text
} | ConvertTo-Json -Depth 4

Write-Host 'Sending to Alpha...'
$result = Invoke-RestMethod -Method Post `
  -Uri 'https://rclbninptekxitkdtmrs.supabase.co/functions/v1/alpha-local-ingest' `
  -Headers @{ 'x-alpha-scout-token' = $token } `
  -ContentType 'application/json' `
  -Body $body

Write-Host ''
if ($result.ok) {
  Write-Host 'SUCCESS - SENT TO ALPHA'
  Write-Host ('Status: ' + $result.status)
  Write-Host ('Characters: ' + $result.char_count)
  Write-Host ('Event ID: ' + $result.event_id)
} else {
  throw ('Alpha rejected the upload: ' + ($result | ConvertTo-Json -Compress))
}
