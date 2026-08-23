<#
  Deploys pink-mushroom-hunter.html to bunny.net Edge Storage + Pull Zone,
  and attaches the custom hostname pinkmushroom.bs40.com.

  Credentials are read from environment variables and are never printed.

    $env:BUNNY_API_KEY = '...'     # Account API key: dash.bunny.net -> Account -> API

  Phase 1 (creates everything, then stops for DNS):
    .\deploy-bunny.ps1

  -- then add the CNAME the script prints, at GoDaddy --

  Phase 2 (issues the TLS cert once DNS resolves):
    .\deploy-bunny.ps1 -Finish

  Re-upload the game after editing it:
    .\deploy-bunny.ps1 -Update
#>

[CmdletBinding()]
param(
  [string]$Hostname    = 'pinkmushroom.bs40.com',
  [string]$ZoneName    = 'pinkmushroom-bs40',
  [string]$Region      = 'DE',
  [string]$File        = '',   # resolved below; $PSScriptRoot is not yet set in param defaults
                               # when [CmdletBinding()] is present
  [switch]$Finish,
  [switch]$Update
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$API = 'https://api.bunny.net'

# ---------------------------------------------------------------- helpers
function Fail($msg) { Write-Host "  x $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "  + $msg" -ForegroundColor Green }
function Info($msg) { Write-Host "  . $msg" -ForegroundColor DarkGray }
function Step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }

function Bunny {
  param([string]$Method, [string]$Path, $Body, [string]$Key)
  $h = @{ AccessKey = $Key; Accept = 'application/json' }
  $args = @{ Method = $Method; Uri = "$API$Path"; Headers = $h }
  if ($null -ne $Body) {
    $args.Body        = ($Body | ConvertTo-Json -Depth 6 -Compress)
    $args.ContentType = 'application/json'
  }
  try { return Invoke-RestMethod @args }
  catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $detail = $_.Exception.Message
    throw "bunny API $Method $Path failed$(if($code){" (HTTP $code)"}): $detail"
  }
}

# GET /storagezone and /pullzone have returned both a bare array and a
# paged {Items:[...]} object across API versions -- normalise both.
function AsList($resp) {
  if ($null -eq $resp) { return @() }
  if ($resp.PSObject.Properties.Name -contains 'Items') { return @($resp.Items) }
  return @($resp)
}

# Storage upload host is derived from the zone's primary region; DE has no prefix.
function StorageHost([string]$r) {
  if ([string]::IsNullOrWhiteSpace($r) -or $r.ToUpper() -eq 'DE') { return 'storage.bunnycdn.com' }
  return "$($r.ToLower()).storage.bunnycdn.com"
}

function Upload {
  param([string]$StorageZone, [string]$StoragePassword, [string]$StorageHost,
        [string]$LocalFile, [string[]]$RemoteNames, [int]$Retries = 5)
  foreach ($name in $RemoteNames) {
    $uri = "https://$StorageHost/$StorageZone/$name"
    $done = $false
    for ($i = 1; $i -le $Retries -and -not $done; $i++) {
      try {
        Invoke-RestMethod -Method Put -Uri $uri `
          -Headers @{ AccessKey = $StoragePassword } `
          -InFile $LocalFile -ContentType 'application/octet-stream' | Out-Null
        Ok "uploaded $name"
        $done = $true
      } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($i -lt $Retries) {
          # A just-created zone can take a few seconds to be accepted at the edge.
          Info "attempt $i on $name returned HTTP $code -- retrying in $($i * 2)s"
          Start-Sleep -Seconds ($i * 2)
        } else {
          Fail "upload of $name failed after $Retries attempts (HTTP $code)"
        }
      }
    }
  }
}

# ---------------------------------------------------------------- preflight
if ([string]::IsNullOrWhiteSpace($File)) { $File = Join-Path $PSScriptRoot 'pink-mushroom-hunter.html' }

$key     = $env:BUNNY_API_KEY
$keyFile = Join-Path $PSScriptRoot '.bunny-key'
$fromFile = $false
if ([string]::IsNullOrWhiteSpace($key) -and (Test-Path $keyFile)) {
  $key = (Get-Content $keyFile -Raw).Trim()
  $fromFile = $true
}
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Host ""
  Fail @"
No bunny.net API key found.

Get it from dash.bunny.net -> Account -> API -> API Key, then EITHER:

  (a) set it in this shell and run the script yourself --
        `$env:BUNNY_API_KEY = 'your-key-here'

  (b) drop it on its own line into
        $keyFile
      which this script reads automatically. Delete the file when done.

Do not paste the key into chat -- it would land in the transcript.
"@
}
if ($fromFile) { Info "key loaded from .bunny-key" }
if (-not (Test-Path $File)) { Fail "cannot find $File" }
$sizeKb = [math]::Round((Get-Item $File).Length / 1KB, 1)

Write-Host "`n=== astroswarm -> bunny.net ===" -ForegroundColor Yellow
Info "file      $File ($sizeKb KB)"
Info "hostname  $Hostname"
Info "zones     $ZoneName (storage + pull)"

# ---------------------------------------------------------------- phase 2
if ($Finish) {
  Step "[1/3] Checking DNS"
  $cname = $null
  try { $cname = Resolve-DnsName $Hostname -Type CNAME -ErrorAction Stop } catch {}
  if (-not $cname) {
    try { $a = Resolve-DnsName $Hostname -ErrorAction Stop } catch {}
    if (-not $a) { Fail "$Hostname does not resolve yet. Add the CNAME first, then wait a few minutes and re-run." }
  }
  Ok "$Hostname resolves"

  $pz = AsList (Bunny GET "/pullzone?page=1&perPage=1000" $null $key) | Where-Object { $_.Name -eq $ZoneName }
  if (-not $pz) { Fail "pull zone '$ZoneName' not found -- run phase 1 first" }

  Step "[2/3] Requesting free TLS certificate (Let's Encrypt)"
  try {
    Bunny GET "/pullzone/loadFreeCertificate?hostname=$Hostname" $null $key | Out-Null
    Ok "certificate issued"
  } catch {
    Fail "certificate request failed. This normally means DNS has not fully propagated to bunny's validators yet -- wait ~10 min and re-run.`n     $($_.Exception.Message)"
  }

  Step "[3/3] Forcing HTTPS"
  Bunny POST "/pullzone/$($pz.Id)/setForceSSL" @{ Hostname = $Hostname; ForceSSL = $true } $key | Out-Null
  Ok "force SSL enabled"

  Write-Host "`nDone. https://$Hostname is live.`n" -ForegroundColor Green
  exit 0
}

# ---------------------------------------------------------------- storage zone
Step "[1/4] Storage zone"
$sz = AsList (Bunny GET "/storagezone?page=1&perPage=1000" $null $key) | Where-Object { $_.Name -eq $ZoneName }
if ($sz) {
  Ok "reusing existing storage zone (id $($sz.Id), region $($sz.Region))"
} else {
  try {
    $sz = Bunny POST "/storagezone" @{ Name = $ZoneName; Region = $Region; ZoneTier = 0 } $key
    Ok "created storage zone (id $($sz.Id), region $($sz.Region))"
  } catch {
    Fail "could not create storage zone '$ZoneName'. Storage zone names are globally unique across all of bunny.net -- if it is taken, re-run with -ZoneName something-else.`n     $($_.Exception.Message)"
  }
}
# The password handed back by POST /storagezone is NOT accepted by the storage
# endpoints straight away -- re-read the zone and use the canonical one.
$sz = AsList (Bunny GET "/storagezone?page=1&perPage=1000" $null $key) | Where-Object { $_.Name -eq $ZoneName }
if (-not $sz) { Fail "storage zone '$ZoneName' vanished between create and read" }
if ([string]::IsNullOrWhiteSpace($sz.Password)) { Fail "storage zone returned no password -- cannot upload" }

$shost = $sz.StorageHostname
if ([string]::IsNullOrWhiteSpace($shost)) { $shost = StorageHost $sz.Region }

# ---------------------------------------------------------------- upload
Step "[2/4] Uploading"
Info "endpoint $shost"
# index.html so the bare hostname serves the game; the named copy is a convenience.
Upload -StorageZone $ZoneName -StoragePassword $sz.Password -StorageHost $shost `
       -LocalFile $File -RemoteNames @('index.html', 'pink-mushroom-hunter.html')

# Splash posters ride alongside rather than being inlined as base64 -- 336KB in
# the HTML would block first paint. The game degrades gracefully without them.
foreach ($img in @('splash-portrait.webp','splash-landscape.webp')) {
  $ip = Join-Path $PSScriptRoot $img
  if (Test-Path $ip) {
    Upload -StorageZone $ZoneName -StoragePassword $sz.Password -StorageHost $shost `
           -LocalFile $ip -RemoteNames @($img)
  } else {
    Info "skipped $img (not present locally)"
  }
}

if ($Update) {
  Step "Purging CDN cache"
  $pz = AsList (Bunny GET "/pullzone?page=1&perPage=1000" $null $key) | Where-Object { $_.Name -eq $ZoneName }
  if ($pz) {
    Bunny POST "/pullzone/$($pz.Id)/purgeCache" $null $key | Out-Null
    Ok "cache purged"
  }
  Write-Host "`nUpdated. https://$Hostname`n" -ForegroundColor Green
  exit 0
}

# ---------------------------------------------------------------- pull zone
Step "[3/4] Pull zone"
$pz = AsList (Bunny GET "/pullzone?page=1&perPage=1000" $null $key) | Where-Object { $_.Name -eq $ZoneName }
if ($pz) {
  Ok "reusing existing pull zone (id $($pz.Id))"
} else {
  try {
    $pz = Bunny POST "/pullzone" @{ Name = $ZoneName; Type = 0; OriginType = 2; StorageZoneId = $sz.Id } $key
    Ok "created pull zone (id $($pz.Id)) -> $ZoneName.b-cdn.net"
  } catch {
    Fail "could not create pull zone '$ZoneName'. Pull zone names are globally unique -- if taken, re-run with -ZoneName something-else.`n     $($_.Exception.Message)"
  }
}

# ---------------------------------------------------------------- hostname
Step "[4/4] Custom hostname"
$already = $false
if ($pz.Hostnames) { $already = @($pz.Hostnames | Where-Object { $_.Value -eq $Hostname }).Count -gt 0 }
if ($already) {
  Ok "$Hostname already attached"
} else {
  try {
    Bunny POST "/pullzone/$($pz.Id)/addHostname" @{ Hostname = $Hostname } $key | Out-Null
    Ok "attached $Hostname"
  } catch {
    Fail "could not attach hostname: $($_.Exception.Message)"
  }
}

# ---------------------------------------------------------------- next steps
Write-Host @"

--------------------------------------------------------------
  Live now on the bunny hostname:

      https://$ZoneName.b-cdn.net

  NEXT: add this DNS record at GoDaddy (bs40.com is on
  ns27/ns28.domaincontrol.com), under DNS -> Manage Zones:

      Type    CNAME
      Name    $($Hostname.Split('.')[0])
      Value   $ZoneName.b-cdn.net
      TTL     600

  Then, once it resolves, run:

      .\deploy-bunny.ps1 -Finish

  to issue the TLS certificate and force HTTPS on $Hostname.
--------------------------------------------------------------

"@ -ForegroundColor Yellow
