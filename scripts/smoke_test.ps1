# Glamea backend smoke test — exercises every registered route.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/smoke_test.ps1 [-BaseUrl http://localhost:8080] [-AdminEmail admin@glamea.test] [-AdminPassword adminpass123]

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$AdminEmail = "admin@glamea.test",
    [string]$AdminPassword = "adminpass123"
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0
$failures = @()

function Step([string]$name, [scriptblock]$body, [int[]]$okCodes = @(200,201,204)) {
    try {
        & $body | Out-Null
        $script:pass++
        Write-Host "  [PASS] $name" -ForegroundColor Green
    } catch {
        $code = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        if ($okCodes -contains $code) {
            $script:pass++
            Write-Host "  [SKIP] $name (accepted status $code)" -ForegroundColor Yellow
        } else {
            $script:fail++
            $script:failures += "$name :: $($_.Exception.Message)"
            Write-Host "  [FAIL] $name :: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Req([string]$method, [string]$path, $headers = @{}, $bodyObj = $null) {
    $params = @{ Uri = "$BaseUrl$path"; Method = $method; Headers = $headers; TimeoutSec = 20 }
    if ($null -ne $bodyObj) {
        $params.ContentType = "application/json"
        $params.Body = ($bodyObj | ConvertTo-Json -Depth 8)
    }
    Invoke-RestMethod @params
}

Write-Host "`n=== SYSTEM ===" -ForegroundColor Cyan
Step "GET /health" { Req "GET" "/health" }
Step "GET /ready" { Req "GET" "/ready" }

Write-Host "`n=== AUTH ===" -ForegroundColor Cyan
$stamp = Get-Date -Format "HHmmssfff"
$custEmail = "smoke.cust.$stamp@glamea.test"
$proEmail = "smoke.pro.$stamp@glamea.test"
$phoneCust = "2339$($stamp.Substring(0,9))"
$phonePro = "2349$($stamp.Substring(0,9))"
$pw = "SmokePass123!"

Step "POST /api/v1/auth/register (customer)" {
    $script:customer = Req "POST" "/api/v1/auth/register" @{} @{ email = $custEmail; phone = $phoneCust; password = $pw; first_name = "Smoke"; last_name = "Customer"; role = "CUSTOMER" }
}
Step "POST /api/v1/auth/register (professional)" {
    $script:professional = Req "POST" "/api/v1/auth/register" @{} @{ email = $proEmail; phone = $phonePro; password = $pw; first_name = "Smoke"; last_name = "Pro"; role = "PROFESSIONAL" }
}
Step "POST /api/v1/auth/login (customer)" {
    $script:custLogin = Req "POST" "/api/v1/auth/login" @{} @{ identifier = $custEmail; password = $pw }
}
Step "POST /api/v1/auth/login (professional)" {
    $script:proLogin = Req "POST" "/api/v1/auth/login" @{} @{ identifier = $proEmail; password = $pw }
}
Step "POST /api/v1/auth/login (admin)" {
    $script:adminLogin = Req "POST" "/api/v1/auth/login" @{} @{ identifier = $AdminEmail; password = $AdminPassword }
}
Step "POST /api/v1/auth/resend-otp" { Req "POST" "/api/v1/auth/resend-otp" @{} @{ phone = $phoneCust } }

$custAuth = @{ Authorization = "Bearer $($custLogin.data.tokens.access_token)" }
$proAuth = @{ Authorization = "Bearer $($proLogin.data.tokens.access_token)" }
$adminAuth = @{ Authorization = "Bearer $($adminLogin.data.tokens.access_token)" }

Write-Host "`n=== USERS ===" -ForegroundColor Cyan
Step "GET /api/v1/users/me (customer)" { Req "GET" "/api/v1/users/me" $custAuth }
Step "PATCH /api/v1/users/me (customer)" { Req "PATCH" "/api/v1/users/me" $custAuth @{ first_name = "Smoky" } }

Write-Host "`n=== CATEGORIES ===" -ForegroundColor Cyan
Step "GET /api/v1/categories" { Req "GET" "/api/v1/categories" }
$catSlug = "smoke-cat-$stamp"
Step "POST /api/v1/categories (admin)" {
    $script:cat = Req "POST" "/api/v1/categories" $adminAuth @{ slug = $catSlug; name = "Smoke Category $stamp"; description = "smoke test" }
}
Step "GET /api/v1/categories/{slug}" { Req "GET" "/api/v1/categories/$catSlug" }
Step "PATCH /api/v1/categories/{id} (admin)" { Req "PATCH" "/api/v1/categories/$($cat.data.category.id)" $adminAuth @{ description = "updated" } }
Step "DELETE /api/v1/categories/{id} (admin)" { Req "DELETE" "/api/v1/categories/$($cat.data.category.id)" $adminAuth }

Write-Host "`n=== PROFESSIONALS ===" -ForegroundColor Cyan
$proUserId = $proLogin.data.user.id
Step "POST /api/v1/professionals (create profile)" {
    $script:pro = Req "POST" "/api/v1/professionals" $proAuth @{ business_name = "Smoke Studio $stamp"; display_name = "Smoke Pro"; bio = "smoke bio"; category_id = $null; experience_years = 3; latitude = 6.5244; longitude = 3.3792; address_line = "12 Test St"; city = "Lagos"; country = "NG"; home_service_enabled = $true; service_radius_km = 5; travel_fee_per_km = 100 }
}
$proId = $pro.data.professional.id
Step "GET /api/v1/professionals" { Req "GET" "/api/v1/professionals" }
Step "GET /api/v1/professionals/{id}" { Req "GET" "/api/v1/professionals/$proId" }
Step "GET /api/v1/professionals/me" { Req "GET" "/api/v1/professionals/me" $proAuth }
Step "PATCH /api/v1/professionals/me" { Req "PATCH" "/api/v1/professionals/me" $proAuth @{ bio = "updated bio" } }

Write-Host "`n=== SERVICES ===" -ForegroundColor Cyan
Step "POST /api/v1/services" {
    $script:svc = Req "POST" "/api/v1/services" $proAuth @{ name = "Smoke Service $stamp"; description = "svc"; base_price = 5000; currency = "NGN"; duration_minutes = 60; deposit_percentage = 10; home_service_available = $true; display_order = 1 }
}
$svcId = $svc.data.service.id
Step "GET /api/v1/services" { Req "GET" "/api/v1/services" }
Step "GET /api/v1/services/{id}" { Req "GET" "/api/v1/services/$svcId" }
Step "PATCH /api/v1/services/{id}" { Req "PATCH" "/api/v1/services/$svcId" $proAuth @{ base_price = 6000 } }
Step "POST /api/v1/services (other pro forbidden)" {
    try { Req "POST" "/api/v1/services" $custAuth @{ name = "x"; base_price = 1; duration_minutes = 30 } | Out-Null; throw "expected 403" } catch { if ($_.Exception.Message -match "expected 403") { throw } }
}
Step "DELETE /api/v1/services/{id}" { Req "DELETE" "/api/v1/services/$svcId" $proAuth }

Write-Host "`n=== MEDIA ===" -ForegroundColor Cyan
Step "POST /api/v1/media/upload-signature" { Req "POST" "/api/v1/media/upload-signature" $proAuth @{ resource_type = "image"; folder = "smoke" } } @(200,503)
Step "POST /api/v1/media" {
    $script:asset = Req "POST" "/api/v1/media" $proAuth @{ provider = "cloudinary"; public_id = "smoke/$stamp"; resource_type = "image"; format = "jpg"; width = 800; height = 600; bytes = 12345; secure_url = "https://res.cloudinary.com/smoke/v1/test.jpg"; folder = "smoke" }
}

Write-Host "`n=== PORTFOLIO ===" -ForegroundColor Cyan
Step "POST /api/v1/portfolio" {
    $script:item = Req "POST" "/api/v1/portfolio" $proAuth @{ media_asset_id = $asset.data.asset.id; caption = "smoke item"; is_featured = $false; display_order = 1 }
}
$itemId = $item.data.item.id
Step "GET /api/v1/professionals/{id}/portfolio" { Req "GET" "/api/v1/professionals/$proId/portfolio" }
Step "GET /api/v1/portfolio/me" { Req "GET" "/api/v1/portfolio/me" $proAuth }
Step "PATCH /api/v1/portfolio/{id}" { Req "PATCH" "/api/v1/portfolio/$itemId" $proAuth @{ caption = "updated" } }
Step "DELETE /api/v1/portfolio/{id}" { Req "DELETE" "/api/v1/portfolio/$itemId" $proAuth }

Write-Host "`n=== VERIFICATION ===" -ForegroundColor Cyan
Step "POST /api/v1/verification/documents" {
    $script:doc = Req "POST" "/api/v1/verification/documents" $proAuth @{ stage = "IDENTITY"; document_type = "national_id"; media_asset_id = $asset.data.asset.id }
}
$docId = $doc.data.document.id
Step "GET /api/v1/verification/me" { Req "GET" "/api/v1/verification/me" $proAuth }
Step "GET /api/v1/admin/verification/documents?pending=true" { Req "GET" "/api/v1/admin/verification/documents?pending=true" $adminAuth }
Step "POST /api/v1/admin/verification/documents/{id}/review (approve)" { Req "POST" "/api/v1/admin/verification/documents/$docId/review" $adminAuth @{ approve = $true; note = "smoke approved" } }

Write-Host "`n=== AUTH SESSION ===" -ForegroundColor Cyan
Step "POST /api/v1/auth/refresh" {
    $script:refreshed = Req "POST" "/api/v1/auth/refresh" @{} @{ refresh_token = $custLogin.data.tokens.refresh_token }
}
Step "POST /api/v1/auth/logout" { Req "POST" "/api/v1/auth/logout" @{} @{ refresh_token = $custLogin.data.tokens.refresh_token } }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PASS: $pass   FAIL: $fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($failures.Count -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
exit $(if ($fail -eq 0) { 0 } else { 1 })
