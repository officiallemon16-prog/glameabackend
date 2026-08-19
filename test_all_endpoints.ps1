$ErrorActionPreference = "Continue"
$Base = "http://localhost:8080"
$ProID = "360d7b2e-a48e-4d13-813b-371880e63053"
$ServiceID = "2e1fc452-27c4-44e4-9adc-9db71106ff2e"
$ReviewBookingID = "786295de-d2fc-4696-bdfb-a04264019fe9"

$script:Ok = 0
$script:Warn = 0
$script:Err = 0
$script:Total = 0

function Invoke-Api {
    param([string]$Method, [string]$Path, [string]$Token, [string]$Body)
    $h = @{}
    if ($Token) { $h["Authorization"] = "Bearer $Token" }
    try {
        if ([string]::IsNullOrEmpty($Body)) {
            $resp = Invoke-WebRequest -Uri ($Base + $Path) -Method $Method -Headers $h `
                -UseBasicParsing -ErrorAction Stop
        }
        else {
            $resp = Invoke-WebRequest -Uri ($Base + $Path) -Method $Method -Headers $h `
                -ContentType "application/json" -Body $Body -UseBasicParsing -ErrorAction Stop
        }
        return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $resp.Content }
    }
    catch {
        $code = 0
        $body = $_.Exception.Message
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try { $body = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
        }
        return [pscustomobject]@{ Status = $code; Body = $body }
    }
}

function Jv {
    param([string]$Json, [string]$Path)
    try {
        $val = $Json | ConvertFrom-Json
        foreach ($part in $Path.Split(".")) {
            if ($part -match '^(.*)\[(\d+)\]$') {
                $val = $val.$($Matches[1])[[int]$Matches[2]]
            }
            else {
                $val = $val.$part
            }
        }
        return $val
    } catch { return $null }
}

function Test-Ep {
    param([string]$Name, [string]$Method, [string]$Path, [string]$Token, [string]$Body)
    $r = Invoke-Api -Method $Method -Path $Path -Token $Token -Body $Body
    if ($r.Status -ge 200 -and $r.Status -lt 300) {
        $verdict = "OK  "
        $script:Ok++
    }
    elseif ($r.Status -ge 500) {
        $verdict = "ERR "
        $script:Err++
    }
    else {
        $verdict = "WARN"
        $script:Warn++
    }
    $script:Total++
    Write-Host ("  {0} {1,3} {2,-5} {3,-60} {4}" -f $verdict, $r.Status, $Method, $Path, $Name)
}

function Login {
    param([string]$Email)
    return Invoke-Api -Method "POST" -Path "/api/v1/auth/login" `
        -Body ('{"identifier":"' + $Email + '","password":"password123"}')
}

function Find-SlotStart {
    for ($d = 1; $d -le 14; $d++) {
        $date = (Get-Date).AddDays($d).ToString("yyyy-MM-dd")
        $r = Invoke-Api -Method "GET" -Token "" `
            -Path ("/api/v1/professionals/" + $ProID + "/availability/slots?date=" + $date + "&duration=180")
        if ($r.Status -ge 200 -and $r.Status -lt 300) {
            $slots = Jv $r.Body "data.slots"
            if ($slots -and $slots.Count -gt 0) {
                return $slots[0].start
            }
        }
    }
    return $null
}

Write-Host "==================================================================="
Write-Host " GLAMEA backend - endpoint status report"
Write-Host (" Base: {0}" -f $Base)
Write-Host "==================================================================="

Write-Host ""
Write-Host "[1] HEALTH / PUBLIC"
Test-Ep "health" "GET" "/health" "" ""
Test-Ep "ready" "GET" "/ready" "" ""
Test-Ep "categories" "GET" "/api/v1/categories" "" ""
Test-Ep "category by slug" "GET" "/api/v1/categories/hair" "" ""
Test-Ep "services" "GET" "/api/v1/services" "" ""
Test-Ep "public settings" "GET" "/api/v1/settings" "" ""
Test-Ep "public deals" "GET" "/api/v1/deals" "" ""
Test-Ep "professionals" "GET" "/api/v1/professionals" "" ""
Test-Ep "professional public" "GET" ("/api/v1/professionals/" + $ProID) "" ""
Test-Ep "professional reviews" "GET" ("/api/v1/professionals/" + $ProID + "/reviews") "" ""
Test-Ep "professional availability" "GET" ("/api/v1/professionals/" + $ProID + "/availability") "" ""
Test-Ep "availability slots" "GET" ("/api/v1/professionals/" + $ProID + "/availability/slots?date=2026-08-20&duration=180") "" ""
Test-Ep "professional portfolio" "GET" ("/api/v1/professionals/" + $ProID + "/portfolio") "" ""
Test-Ep "discovery home" "GET" "/api/v1/discovery/home" "" ""
Test-Ep "discovery search" "GET" "/api/v1/discovery/search?q=braids" "" ""
Test-Ep "discovery category" "GET" "/api/v1/discovery/categories/hair" "" ""
Test-Ep "discovery professional" "GET" ("/api/v1/discovery/professionals/" + $ProID) "" ""
Test-Ep "discovery professional services" "GET" ("/api/v1/discovery/professionals/" + $ProID + "/services") "" ""

Write-Host ""
Write-Host "[2] AUTH"
$c1 = Login "customer1@glamea.test"
$Cust = Jv $c1.Body "data.tokens.access_token"
$p1 = Login "pro@glamea.test"
$Pro = Jv $p1.Body "data.tokens.access_token"
$a1 = Login "admin@glamea.test"
$Admin = Jv $a1.Body "data.tokens.access_token"
Test-Ep "login (customer)" "POST" "/api/v1/auth/login" "" '{"identifier":"customer1@glamea.test","password":"password123"}'
Test-Ep "login (pro)" "POST" "/api/v1/auth/login" "" '{"identifier":"pro@glamea.test","password":"password123"}'
Test-Ep "login (admin)" "POST" "/api/v1/auth/login" "" '{"identifier":"admin@glamea.test","password":"password123"}'
Test-Ep "login wrong password" "POST" "/api/v1/auth/login" "" '{"identifier":"customer1@glamea.test","password":"wrong"}'
Test-Ep "auth refresh" "POST" "/api/v1/auth/refresh" $Cust "{}"

Write-Host ""
Write-Host "[3] CUSTOMER (auth)"
Test-Ep "users/me" "GET" "/api/v1/users/me" $Cust ""
Test-Ep "bookings me" "GET" "/api/v1/bookings/me" $Cust ""
Test-Ep "payments wallet" "GET" "/api/v1/payments/wallet" $Cust ""
Test-Ep "payments transactions" "GET" "/api/v1/payments/transactions" $Cust ""
Test-Ep "reviews me" "GET" "/api/v1/reviews/me" $Cust ""
Test-Ep "notifications me" "GET" "/api/v1/notifications/me" $Cust ""
Test-Ep "notifications unread" "GET" "/api/v1/notifications/me/unread-count" $Cust ""
Test-Ep "notifications read-all" "POST" "/api/v1/notifications/me/read-all" $Cust "{}"
Test-Ep "conversations me" "GET" "/api/v1/conversations/me" $Cust ""
Test-Ep "disputes me" "GET" "/api/v1/disputes/me" $Cust ""

$custBk = Invoke-Api -Method "GET" -Path "/api/v1/bookings/me" -Token $Cust
$BookingID = Jv $custBk.Body "data.bookings[0].id"
if (-not $BookingID) { $BookingID = $ProID }

Test-Ep "booking by id" "GET" ("/api/v1/bookings/" + $BookingID) $Cust ""
Test-Ep "booking history" "GET" ("/api/v1/bookings/" + $BookingID + "/history") $Cust ""
Test-Ep "booking conversation" "GET" ("/api/v1/bookings/" + $BookingID + "/conversation") $Cust ""
Test-Ep "booking messages" "GET" ("/api/v1/bookings/" + $BookingID + "/messages") $Cust ""

$custDisp = Invoke-Api -Method "GET" -Path "/api/v1/disputes/me" -Token $Cust
$DisputeID = Jv $custDisp.Body "data.disputes[0].id"
if (-not $DisputeID) { $DisputeID = "none" }
Test-Ep "dispute by id" "GET" ("/api/v1/disputes/" + $DisputeID) $Cust ""
Test-Ep "dispute messages" "GET" ("/api/v1/disputes/" + $DisputeID + "/messages") $Cust ""

Write-Host ""
Write-Host "[4] PROFESSIONAL (auth)"
Test-Ep "professionals me" "GET" "/api/v1/professionals/me" $Pro ""
Test-Ep "professional services (by filter)" "GET" ("/api/v1/services?professional_id=" + $ProID) "" ""
Test-Ep "professional bookings" "GET" "/api/v1/professionals/me/bookings" $Pro ""
Test-Ep "professional reviews" "GET" "/api/v1/professionals/me/reviews" $Pro ""
Test-Ep "professional deals" "GET" "/api/v1/professionals/me/deals" $Pro ""
Test-Ep "availability windows me" "GET" "/api/v1/availability/windows" $Pro ""
Test-Ep "availability exceptions me" "GET" "/api/v1/availability/exceptions" $Pro ""
Test-Ep "payouts balance" "GET" "/api/v1/payouts/balance" $Pro ""
Test-Ep "payouts requests" "GET" "/api/v1/payouts/requests" $Pro ""
Test-Ep "payouts accounts" "GET" "/api/v1/payouts/accounts" $Pro ""
Test-Ep "portfolio me" "GET" "/api/v1/portfolio/me" $Pro ""
Test-Ep "verification me" "GET" "/api/v1/verification/me" $Pro ""

Write-Host ""
Write-Host "[5] ADMIN (auth)"
Test-Ep "admin dashboard" "GET" "/api/v1/admin/dashboard" $Admin ""
Test-Ep "admin dashboard metrics" "GET" "/api/v1/admin/dashboard/metrics" $Admin ""
Test-Ep "admin users" "GET" "/api/v1/admin/users" $Admin ""
Test-Ep "admin professionals" "GET" "/api/v1/admin/professionals" $Admin ""
Test-Ep "admin audit logs" "GET" "/api/v1/admin/audit-logs" $Admin ""
Test-Ep "admin disputes" "GET" "/api/v1/admin/disputes" $Admin ""
Test-Ep "admin payouts" "GET" "/api/v1/admin/payouts" $Admin ""
Test-Ep "admin deals" "GET" "/api/v1/admin/deals" $Admin ""
Test-Ep "admin verification docs" "GET" "/api/v1/admin/verification/documents" $Admin ""
Test-Ep "analytics summary" "GET" "/api/v1/admin/analytics/summary" $Admin ""
Test-Ep "analytics trends" "GET" "/api/v1/admin/analytics/trends" $Admin ""
Test-Ep "analytics revenue-by-service" "GET" "/api/v1/admin/analytics/revenue-by-service" $Admin ""
Test-Ep "analytics top-professionals" "GET" "/api/v1/admin/analytics/top-professionals" $Admin ""
Test-Ep "reports bookings" "GET" "/api/v1/admin/reports/bookings" $Admin ""
Test-Ep "reports payments" "GET" "/api/v1/admin/reports/payments" $Admin ""
Test-Ep "reports payouts" "GET" "/api/v1/admin/reports/payouts" $Admin ""
Test-Ep "admin settings" "GET" "/api/v1/admin/settings" $Admin ""
Test-Ep "admin setting by name" "GET" "/api/v1/admin/settings/commission_rate" $Admin ""

Write-Host ""
Write-Host "[6] WRITE OPERATIONS (creates live data)"
$stamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
$startAt = Find-SlotStart
Write-Host ("  picked slot start: " + $startAt)
if (-not $startAt) { $startAt = "2026-09-05T10:00:00+01:00" }
$bkBody = '{"service_id":"' + $ServiceID + '","start_at":"' + $startAt + '","home_service":false,"customer_notes":"endpoint sweep"}'
$bkResp = Invoke-Api -Method "POST" -Path "/api/v1/bookings" -Token $Cust -Body $bkBody
$NewBookingID = Jv $bkResp.Body "data.booking.id"
Write-Host ("  create booking -> status=" + $bkResp.Status + " id=" + $NewBookingID)
if (-not $NewBookingID) {
    $r2 = Invoke-Api -Method "GET" -Path "/api/v1/bookings/me" -Token $Cust
    $NewBookingID = Jv $r2.Body "data.bookings[0].id"
    Write-Host ("  fallback booking id: " + $NewBookingID)
}
Test-Ep "create deposit intent" "POST" "/api/v1/payments/intents" $Cust ('{"booking_id":"' + $NewBookingID + '","amount_type":"DEPOSIT"}')
Test-Ep "send message" "POST" ("/api/v1/bookings/" + $NewBookingID + "/messages") $Cust ('{"body":"endpoint sweep msg ' + $stamp + '"}')
Test-Ep "mark messages read" "POST" ("/api/v1/bookings/" + $NewBookingID + "/messages/read") $Pro "{}"
Test-Ep "reschedule booking" "POST" ("/api/v1/bookings/" + $NewBookingID + "/reschedule") $Cust '{"start_at":"2026-09-06T11:00:00+01:00"}'
Test-Ep "cancel booking" "POST" ("/api/v1/bookings/" + $NewBookingID + "/cancel") $Cust '{"reason":"endpoint sweep cleanup"}'
Test-Ep "create review" "POST" "/api/v1/reviews" $Cust ('{"booking_id":"' + $ReviewBookingID + '","rating":5,"comment":"sweep review"}')
Test-Ep "raise dispute" "POST" "/api/v1/disputes" $Cust ('{"booking_id":"' + $NewBookingID + '","reason":"OTHER","description":"sweep dispute"}')
Test-Ep "create deal (pro)" "POST" "/api/v1/professionals/me/deals" $Pro ('{"code":"SWEEP' + $stamp + '","name":"Sweep deal","discount_type":"PERCENT","discount_value":10,"min_order_amount":1000}')
Test-Ep "add payout account (pro)" "POST" "/api/v1/payouts/accounts" $Pro ('{"bank_name":"GTBank","account_number":"7' + $stamp + '","account_name":"Ada Obi"}')
Test-Ep "request payout (pro)" "POST" "/api/v1/payouts/requests" $Pro '{"amount":100}'
Test-Ep "set availability windows (pro)" "PUT" "/api/v1/availability/windows" $Pro '{"windows":[{"day_of_week":5,"start_minutes":540,"end_minutes":1020}]}'
Test-Ep "add availability exception (pro)" "POST" "/api/v1/availability/exceptions" $Pro '{"date":"2026-09-05","start_minutes":540,"end_minutes":1020,"is_available":true,"note":"sweep"}'
Test-Ep "create category (admin)" "POST" "/api/v1/categories" $Admin ('{"name":"SweepCat' + $stamp + '","slug":"sweepcat' + $stamp + '","description":"sweep"}')
Test-Ep "create service (pro)" "POST" "/api/v1/services" $Pro ('{"name":"Sweep Svc ' + $stamp + '","description":"sweep","base_price":1000,"currency":"NGN","duration_minutes":60,"deposit_percentage":10,"home_service_available":false,"display_order":0,"variants":[]}')
Test-Ep "admin payout pay (bogus id)" "POST" "/api/v1/admin/payouts/00000000-0000-4000-8000-000000000000/pay" $Admin '{"note":"sweep"}'
Test-Ep "admin resolve dispute (bogus id)" "POST" "/api/v1/admin/disputes/00000000-0000-4000-8000-000000000000/resolve" $Admin '{"resolution":"NO_REFUND"}'
Test-Ep "admin settings patch" "PATCH" "/api/v1/admin/settings" $Admin '{"commission_rate":"0.10"}'
Test-Ep "webhook (mock gateway)" "POST" "/api/v1/payments/webhook/paystack" $Admin '{}'
Test-Ep "auth logout" "POST" "/api/v1/auth/logout" $Cust "{}"

Write-Host ""
Write-Host "==================================================================="
Write-Host (" TOTAL: {0}   OK: {1}   WARN: {2}   ERR: {3}" -f $script:Total, $script:Ok, $script:Warn, $script:Err)
Write-Host "  OK   = 2xx response"
Write-Host "  WARN = endpoint responded with a 3xx/4xx (validation or business rule)"
Write-Host "  ERR  = 5xx server error (needs attention)"
Write-Host "==================================================================="
