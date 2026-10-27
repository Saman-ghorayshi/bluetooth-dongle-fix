# BTFix test suite — dependency free.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
#
# The suite is intentionally self-contained: it uses a tiny assertion helper
# instead of Pester, so it runs on a stock Windows box with nothing installed.

$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Failures = @()
$script:Current = ''

function Describe {
    param([string]$Name, [scriptblock]$Body)
    $script:Current = $Name
    Write-Host ''
    Write-Host "== $Name" -ForegroundColor Cyan
    & $Body
}

function It {
    param([string]$Name, [scriptblock]$Body)
    try {
        $result = & $Body
        if ($result -eq $false) { throw 'returned $false' }
        $script:Passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Failed++
        $script:Failures += "$script:Current :: $Name :: $($_.Exception.Message)"
        Write-Host "  FAIL  $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ($Expected -ne $Actual) {
        throw "expected '$Expected' but got '$Actual' $Because"
    }
}

function Assert-True {
    param($Condition, [string]$Because = '')
    if (-not $Condition) { throw "expected a true condition $Because" }
}

function Assert-False {
    param($Condition, [string]$Because = '')
    if ($Condition) { throw "expected a false condition $Because" }
}

function Assert-Match {
    param([string]$Pattern, $Actual)
    if ("$Actual" -notmatch $Pattern) { throw "'$Actual' does not match '$Pattern'" }
}

function Write-Summary {
    Write-Host ''
    Write-Host ('-' * 60)
    Write-Host ("passed: {0}   failed: {1}" -f $script:Passed, $script:Failed)
    if ($script:Failed -gt 0) {
        Write-Host ''
        Write-Host 'failures:' -ForegroundColor Red
        foreach ($f in $script:Failures) { Write-Host "  - $f" -ForegroundColor Red }
    }
    exit ([int]($script:Failed -gt 0))
}
