# /hotel-search --test fixture 手动跑
# 模拟 Claude 跑 /hotel-search --test 时的完整执行链
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File run-fixture.ps1
# 依赖: PowerShell 5.1 (Windows 自带)

# PS 5.1 用 ServicePointManager 全局跳过 TLS 校验 (对应 curl -k)
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    $source = @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
    Add-Type -TypeDefinition $source
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$BASE = 'https://api-test.hotelbyte.com'
$today = Get-Date
$ci = $today.AddDays(30).ToString('yyyyMMdd')
$co = $today.AddDays(32).ToString('yyyyMMdd')
$session = [guid]::NewGuid().ToString()

Write-Host '=== FIXTURE (--test mode) ==='
Write-Host ('destination=Tokyo, checkIn={0}, checkOut={1}, adults=2, USD, en-US, minStar=0, maxRates=5' -f $ci, $co)
Write-Host ''

# Step 1: ticket
try {
    $t = Invoke-RestMethod -Uri "$BASE/api/auth/ticket" -Method Post -ContentType 'application/json' `
        -Body '{"appKey":"hotelbyte_api_demo","appSecret":"hotelbyte_api_demo","ttl":3600}'
    Write-Host ('STEP 1 ticket: {0}  (code={1})' -f $t.data.ticket, $t.code)
} catch {
    Write-Host ('STEP 1 FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

# Step 2: search
$body = @{
    destination='Tokyo'; checkIn=$ci; checkOut=$co
    adultCount=2; childrenCount=0; currency='USD'; language='en-US'
    filter=@{ price=@{ low=0; high=99999 } }
    minStarRating=0; maxRatesPerHotel=5
} | ConvertTo-Json -Compress

$headers = @{
    'Authorization' = "Bearer $($t.data.ticket)"
    'Session-Id' = $session
    'Language' = 'en-US'
    'Currency' = 'USD'
}

try {
    $s = Invoke-RestMethod -Uri "$BASE/api/search/hotelList" -Method Post -ContentType 'application/json' `
        -Headers $headers -Body $body
    Write-Host 'STEP 2 search HTTP=200'
} catch {
    Write-Host ('STEP 2 FAILED: {0}' -f $_.Exception.Message)
    exit 1
}
Write-Host ''

$status = $s.data.result.status
$reason = $s.data.result.reason
$lst = $s.data.list
$corr = $s.data.result.correlationId

Write-Host '=== DISPOSITION (按 SKILL.md 步骤 5) ==='
Write-Host ('result.status = {0}' -f $status)
Write-Host ('result.reason = {0}' -f $reason)
Write-Host ('data.list length = {0}' -f $lst.Count)
Write-Host ('session = {0}' -f $session)
Write-Host ('correlationId = {0}' -f $corr)
Write-Host ''

if ($status -eq 'success' -and $lst.Count -gt 0) {
    Write-Host ('# Search results: Tokyo, {0} -> {1}, 2 adults, USD, 0-star+' -f $ci, $co)
    Write-Host ''
    Write-Host '| # | hotelId | star | minPrice |'
    Write-Host '|---|---------|------|----------|'
    for ($i=0; $i -lt [Math]::Min(8,$lst.Count); $i++) {
        $h = $lst[$i]
        Write-Host ('| {0} | {1} | {2} | {3} |' -f ($i+1), $h.hotelId, $h.starRating, $h.minPrice)
    }
} elseif ($status -eq 'failed' -and $reason -eq 'no_availability') {
    Write-Host '# No hotels available'
    Write-Host ('destination: Tokyo  dates: {0} -> {1}' -f $ci, $co)
    Write-Host 'API returned status=failed / reason=no_availability (demo env supplier has no stock for these dates).'
    Write-Host ''
    Write-Host 'Suggestions:'
    Write-Host '- Try a different destination'
    Write-Host '- Move dates 30-90 days forward'
    Write-Host '- Drop the minStarRating constraint'
    Write-Host ''
    Write-Host ('> correlationId={0}' -f $corr)
} else {
    Write-Host ('code={0} msg={1}' -f $s.code, $s.msg)
}
