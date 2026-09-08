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
out_path=sys.argv[2]
meta_path=sys.argv[3]
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

api=YouTubeTranscriptApi()
items=list(api.list(vid))
if not items:
    raise SystemExit('No transcript is available for this video')

# Preference: English, then Hindi, then any manual transcript, then any available transcript.
def score(t):
    code=(getattr(t,'language_code','') or '').lower()
    generated=bool(getattr(t,'is_generated',False))
    if code.startswith('en') and not generated: return 0
    if code.startswith('en'): return 1
    if code.startswith('hi') and not generated: return 2
    if code.startswith('hi'): return 3
    if not generated: return 4
    return 5

chosen=sorted(items,key=score)[0]
lang=getattr(chosen,'language_code','unknown') or 'unknown'
fetched=chosen.fetch()
text='\n'.join(x.text for x in fetched).strip()
if not text:
    raise SystemExit('Transcript was empty')

# Write UTF-8 files instead of printing transcript to the Windows console.
# This avoids cp1252/Unicode errors for Hindi and other languages.
with open(out_path,'w',encoding='utf-8',newline='\n') as f:
    f.write(text)
with open(meta_path,'w',encoding='utf-8') as f:
    f.write(lang)
'@

$tmpPy = Join-Path $env:TEMP 'alpha_scout_youtube.py'
$tmpTranscript = Join-Path $env:TEMP ('alpha_scout_transcript_' + [guid]::NewGuid().ToString('N') + '.txt')
$tmpMeta = Join-Path $env:TEMP ('alpha_scout_meta_' + [guid]::NewGuid().ToString('N') + '.txt')
Set-Content -Path $tmpPy -Value $py -Encoding UTF8

& python $tmpPy $url $tmpTranscript $tmpMeta
if ($LASTEXITCODE -ne 0) {
  Remove-Item $tmpPy,$tmpTranscript,$tmpMeta -ErrorAction SilentlyContinue
  throw 'Could not retrieve transcript.'
}

$text = (Get-Content $tmpTranscript -Raw -Encoding UTF8).Trim()
$language = (Get-Content $tmpMeta -Raw -Encoding UTF8).Trim()
Remove-Item $tmpPy,$tmpTranscript,$tmpMeta -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($text)) { throw 'Transcript was empty.' }
if ([string]::IsNullOrWhiteSpace($language)) { $language = 'unknown' }
Write-Host ('Transcript language: ' + $language)

$body = @{
  device_id = $env:COMPUTERNAME
  kind = 'YOUTUBE_TRANSCRIPT'
  source_url = $url
  title = ('YouTube transcript [' + $language + ']')
  text = $text
} | ConvertTo-Json -Depth 4
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

Write-Host 'Sending to Alpha...'
$result = Invoke-RestMethod -Method Post `
  -Uri 'https://rclbninptekxitkdtmrs.supabase.co/functions/v1/alpha-local-ingest' `
  -Headers @{ 'x-alpha-scout-token' = $token } `
  -ContentType 'application/json; charset=utf-8' `
  -Body $bodyBytes

Write-Host ''
if ($result.ok) {
  Write-Host 'SUCCESS - SENT TO ALPHA'
  Write-Host ('Status: ' + $result.status)
  Write-Host ('Language: ' + $language)
  Write-Host ('Characters: ' + $result.char_count)
  Write-Host ('Event ID: ' + $result.event_id)
} else {
  throw ('Alpha rejected the upload: ' + ($result | ConvertTo-Json -Compress))
}
