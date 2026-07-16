param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [Parameter(Mandatory = $true)]
    [string]$OutputCsv
)

$ErrorActionPreference = 'Stop'

$rows = Import-Csv -LiteralPath $InputCsv
if (-not $rows -or $rows.Count -eq 0) {
    throw "Input CSV has no data rows: $InputCsv"
}

$headers = @($rows[0].PSObject.Properties.Name)
$requiredHeaders = @('アイテム名', 'カテゴリ', '買値', '売値')
foreach ($header in $requiredHeaders) {
    if ($header -notin $headers) {
        throw "Required column is missing: $header"
    }
}

$checkboxHeaders = @(
    'とぐろ島', 'とぐろ島の神髄', 'カカ・ルーの神意', 'デッ怪ラッシュ',
    'ドスコイダンジョン', 'ヤマカガシ峠', '仕掛けの修験道',
    '推測の修験道', '推測の修験道 裏', '杖と巻物の領域',
    '桃まんダンジョン', '水龍の洞窟', '無双の島', '神器の海廊',
    '罠師の抜け道', '識別済', '買い物上手の修験道', '鬼木島', '魃の砂丘'
)
$strictSingleValueHeaders = @('カテゴリ', '買値', '売値')
$outputHeaders = @(
    'アイテム名', '識別済', 'カテゴリ', '買値', '売値', '容量・回数', '識別方法', 'メモ',
    'とぐろ島', '魃の砂丘', '水龍の洞窟', '鬼木島',
    '推測の修験道', '推測の修験道 裏', '罠師の抜け道', '仕掛けの修験道',
    '買い物上手の修験道', '桃まんダンジョン', '杖と巻物の領域', '神器の海廊',
    'ドスコイダンジョン', 'カカ・ルーの神意', 'デッ怪ラッシュ', 'ヤマカガシ峠',
    'とぐろ島の神髄', '無双の島'
)

if (@($outputHeaders | Where-Object { $_ -notin $headers }).Count -gt 0) {
    throw 'One or more output columns are missing from the input CSV.'
}

function Get-BestTextValue {
    param([object[]]$Values)

    $candidates = @(
        $Values |
            ForEach-Object { if ($null -eq $_) { '' } else { ([string]$_).Trim() } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if ($candidates.Count -eq 0) {
        return ''
    }

    return @($candidates | Sort-Object Length -Descending)[0]
}

$mergedRows = foreach ($group in ($rows | Group-Object 'アイテム名')) {
    if ([string]::IsNullOrWhiteSpace($group.Name)) {
        throw 'A row has an empty item name.'
    }

    $merged = [ordered]@{}
    foreach ($header in $headers) {
        $values = @($group.Group | ForEach-Object { $_.$header })

        if ($header -eq 'アイテム名') {
            $merged[$header] = $group.Name
            continue
        }

        if ($header -in $checkboxHeaders) {
            $merged[$header] = if ($values -contains 'Yes') { 'Yes' } else { 'No' }
            continue
        }

        if ($header -in $strictSingleValueHeaders) {
            $nonEmpty = @(
                $values |
                    ForEach-Object { if ($null -eq $_) { '' } else { ([string]$_).Trim() } } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
            if ($nonEmpty.Count -gt 1) {
                throw "Conflicting values for '$header' on '$($group.Name)': $($nonEmpty -join ', ')"
            }
            $merged[$header] = if ($nonEmpty.Count -eq 1) { $nonEmpty[0] } else { '' }
            continue
        }

        $merged[$header] = Get-BestTextValue -Values $values
    }

    [pscustomobject]$merged
}

# The only missing price in the export. Verified against the current item price table.
$sureHitSword = @($mergedRows | Where-Object 'アイテム名' -eq '必中の剣')
if ($sureHitSword.Count -eq 1) {
    $sureHitSword[0].'買値' = '20000'
    $sureHitSword[0].'売値' = '8000'
    $sureHitSword[0].'メモ' = '神髄6回目クリア報酬。通常価格は買値20000・売値8000。'
}

$categoryOrder = @{
    '武器' = 1; '盾' = 2; '腕輪' = 3; '草・種' = 4; '巻物' = 5;
    '杖' = 6; '壺' = 7; '食料' = 8; '矢・石' = 9; 'お香' = 10;
    '桃まん' = 11; '札' = 12; 'その他' = 13
}

$mergedRows = @(
    $mergedRows | Sort-Object `
        @{ Expression = { if ($categoryOrder.ContainsKey($_.'カテゴリ')) { $categoryOrder[$_.'カテゴリ'] } else { 999 } } },
        @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.'買値')) { [decimal]::MaxValue } else { [decimal]$_.'買値' } } },
        @{ Expression = { $_.'アイテム名' } }
)

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$mergedRows | Select-Object $outputHeaders | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -UseQuotes AsNeeded -Encoding utf8BOM

$duplicateCount = @($mergedRows | Group-Object 'アイテム名' | Where-Object Count -gt 1).Count
$missingPriceCount = @($mergedRows | Where-Object {
    [string]::IsNullOrWhiteSpace($_.'買値') -or [string]::IsNullOrWhiteSpace($_.'売値')
}).Count

if ($duplicateCount -ne 0) {
    throw "Verification failed: $duplicateCount duplicate item groups remain."
}
if ($missingPriceCount -ne 0) {
    throw "Verification failed: $missingPriceCount rows still have a missing price."
}

[pscustomobject]@{
    InputRows = $rows.Count
    OutputRows = $mergedRows.Count
    RemovedDuplicateRows = $rows.Count - $mergedRows.Count
    RemainingDuplicateGroups = $duplicateCount
    MissingPriceRows = $missingPriceCount
    OutputCsv = $OutputCsv
}
