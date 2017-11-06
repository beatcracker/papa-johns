<#
.Synopsis
    Get a code for free complimenatry pizza from puzzle.papajohns.ru

.Description
    No need to play a game, just run this script and get a code for free random pizza in your next order.

.Parameter User
    Email registered on puzzle.papajohns.ru

.Parameter Password
    Password for email registered on puzzle.papajohns.ru

.Parameter Sid
    If you don't want to pass email/password combo to script, you can login to the puzzle.papajohns.ru and use a value of 'sid' cookie.

.Parameter Delay
    Delay between sending game data to server. Default is 1 second.

.Notes
    I'm too lazy to pass username/password/sid as a proper crendtials object. Sorry about that.
#>
[CmdletBinding(DefaultParameterSetName = 'Login')]
Param (

    [Parameter(Mandatory = $true, ParameterSetName = 'Login')]
    [ValidateNotNullOrEmpty()]
    [string]$User,

    [Parameter(Mandatory = $true, ParameterSetName = 'Login')]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [Parameter(Mandatory = $true, ParameterSetName = 'Sid')]
    [string]$Sid,

    [int]$Delay = 1
)

<#
.SYNOPSIS
    Format debug output.
#>
filter Out-Table{
    $_ | Format-Table -AutoSize | Out-String
}

<#
.SYNOPSIS
    Fix for site not setting encoding correctly which breaks cyrillic.
#>
function ConvertTo-Utf8String {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [Alias('RawContentStream')]
        [System.IO.MemoryStream]$InputObject
    )

    Process {
        [System.Text.Encoding]::UTF8.GetString(
            $InputObject.ToArray()
        )
    }
}


$GameSuccess = 'success'

[uri]$GameBaseUrl = 'https://puzzle.papajohns.ru/ajax/game'
$GameSession = New-Object -TypeName Microsoft.PowerShell.Commands.WebRequestSession

if ($Sid) {
    $GameCookie = @{
        sid = $Sid
    }

    'Setting cookies:', ($GameCookie | Out-Table) | Write-Verbose

    $GameCookie.GetEnumerator() | ForEach-Object {
        $Cookie = New-Object -TypeName System.Net.Cookie

        $Cookie.Name = $_.Key
        $Cookie.Value = $_.Value

        $CookieDomain = if ('sid' -eq $_.Key) {
            $GameBaseUrl.DnsSafeHost
        } else {
            $GameBaseUrl.DnsSafeHost -replace '.+?(\..+)', '$1'
        }

        $Cookie.Domain = $CookieDomain

        $GameSession.Cookies.Add($Cookie);
    }
} else {
    Write-Progress -Activity 'Logging in...'

    $Auth = Invoke-WebRequest -Method Post -WebSession $GameSession -UseBasicParsing -Body @{
        login = $User
        passwd = $Password
    } -Uri 'https://puzzle.papajohns.ru/ajax/authorization/site/submit.html' -ContentType 'application/x-www-form-urlencoded'

    $AuthConverted = $Auth | ConvertTo-Utf8String | ConvertFrom-Json
    if ($GameSuccess -eq $AuthConverted.result) {
        'Logins success!', ($AuthConverted | Out-Table) | Write-Verbose
    } else {
        ($AuthConverted | Out-Table) | Write-Verbose
        throw "Login failed: $($AuthConverted.errorsText)"
    }
}

Write-Progress -Activity 'Requesting new game...'

$GameData = Invoke-WebRequest -UseBasicParsing -Uri "$GameBaseUrl/start.html" -Method Post -WebSession $GameSession | ConvertFrom-Json
($GameData | Out-Table) | Write-Verbose


if ($GameSuccess -eq $GameData.Result) {
    $GameCellsSorted = @{}

    $GameCellsSorted = 0..($GameData.game.cells.Count - 1) | ForEach-Object {
        [pscustomobject]@{
            Item = $GameData.game.cells[$_]
            Index = $_
        }
    } | Sort-Object -Property Item

    @('Sorted items:') + ($GameCellsSorted | ForEach-Object {$_ | Out-Table}) | Write-Verbose

    "Sleeping for requested delay: $($GameData.game.studyTime) seconds" | Write-Verbose
    Start-Sleep -Seconds $GameData.game.studyTime

    $GamePctIncrement = [math]::Floor(100 / $GameCellsSorted.Count)
    $GameTotalPct = 0
    $GameResult = $GameCellsSorted | ForEach-Object {
        $GameTotalPct += $GamePctIncrement
        Write-Progress -Activity 'Playing game' -Status "$GameTotalPct% Complete:" -PercentComplete $GameTotalPct

        $GameItem = @{
            game_id = $GameData.game.id
            cell = $_.Index + 1 # Start array from 1
        }

        'Sending item data:', ($GameItem | Out-Table) | Write-Verbose

        Invoke-WebRequest -Body $GameItem -UseBasicParsing -Uri "$GameBaseUrl/step.html" -Method Post -WebSession $GameSession -ContentType 'application/x-www-form-urlencoded'

        "Sleeping for: $Delay seconds" | Write-Verbose
        Start-Sleep -Seconds $Delay
    }

    Write-Progress -Activity 'Playing game' -Status "$GameTotalPct% Complete:" -PercentComplete $GameTotalPct
    'Done:' | Write-Verbose

    ($GameResult[-1] | ConvertTo-Utf8String | ConvertFrom-Json).game
} else {
    'Failed!', ($GameData | Out-Table) | Write-Error
}