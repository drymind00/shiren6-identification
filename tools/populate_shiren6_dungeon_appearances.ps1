param(
    [string]$CsvPath = (Join-Path $PSScriptRoot '..\outputs\shiren6_notion_import\シレン6 アイテム図鑑・値段識別_インポート用.csv')
)

$ErrorActionPreference = 'Stop'

$sourceUrl = 'https://tsuemaki-daisuki.vercel.app/exported_reports.js'
$dungeons = [ordered]@{
    'とぐろ島'             = 'D001'
    '魃の砂丘'             = 'D005'
    '水龍の洞窟'           = 'D006'
    '鬼木島'               = 'D008'
    '推測の修験道'         = 'D009'
    '推測の修験道 裏'      = 'D019'
    '罠師の抜け道'         = 'D013'
    '仕掛けの修験道'       = 'D014'
    '買い物上手の修験道'   = 'D015'
    '桃まんダンジョン'     = 'D010'
    '杖と巻物の領域'       = 'D018'
    '神器の海廊'           = 'D017'
    'ドスコイダンジョン'   = 'D011'
    'カカ・ルーの神意'     = 'D012'
    'デッ怪ラッシュ'       = 'D016'
    'ヤマカガシ峠'         = 'D007'
    'とぐろ島の神髄'       = 'D022'
    '無双の島'             = 'D020'
}

# レポートのアイテムテーブルに載らないが、このツールでは出現候補として
# 扱う必要がある入手手段だけを明示する。通常の出現情報は必ずレポートから
# 再計算するため、古いCSVの Yes を引き継がない。
$manualAppearanceOverrides = @{
    # 例: 'とぐろ島の神髄' = @('必中の剣')
}

function Expand-EmbeddedJson {
    param(
        [Parameter(Mandatory)] [string]$JavaScript,
        [Parameter(Mandatory)] [string]$VariableName
    )

    $pattern = 'const ' + [regex]::Escape($VariableName) + ' = "([\s\S]*?)";'
    $match = [regex]::Match($JavaScript, $pattern)
    if (-not $match.Success) {
        throw "埋め込みデータ $VariableName が見つかりません。"
    }

    $compressed = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
    $memory = [IO.MemoryStream]::new($compressed)
    $zlib = [IO.Compression.ZLibStream]::new($memory, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($zlib, [Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
    finally {
        $reader.Dispose()
        $zlib.Dispose()
        $memory.Dispose()
    }
}

$resolvedCsvPath = [IO.Path]::GetFullPath($CsvPath)
if (-not (Test-Path -LiteralPath $resolvedCsvPath)) {
    throw "CSVが見つかりません: $resolvedCsvPath"
}

$javascript = (Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing).Content
$reports = Expand-EmbeddedJson -JavaScript $javascript -VariableName 'compressedReports'
$localization = Expand-EmbeddedJson -JavaScript $javascript -VariableName 'compressedLocalization'
$rows = @(Import-Csv -LiteralPath $resolvedCsvPath)

$availableByDungeon = @{}
foreach ($entry in $dungeons.GetEnumerator()) {
    $report = $reports | Where-Object { $_.dungeon.dungeon_id -eq $entry.Value } | Select-Object -First 1
    if ($null -eq $report) {
        throw "ダンジョンデータが見つかりません: $($entry.Key) ($($entry.Value))"
    }

    $maxFloor = [int]$report.dungeon.floors.extended
    if ($maxFloor -lt 1) {
        $maxFloor = [int]$report.dungeon.floors.normal
    }

    # 各階で参照される10系統（床、店、壁内店、変化、トド、浮島、NPC、
    # デッ怪、壁、盗み）のアイテムテーブルを集約する。
    $usedTableIds = @{}
    foreach ($floorProperty in $report.floors.PSObject.Properties) {
        $floor = $floorProperty.Value
        if ([int]$floor.floor -lt 1 -or [int]$floor.floor -gt $maxFloor) {
            continue
        }
        foreach ($tableId in $floor.item.item_tables) {
            $usedTableIds[[string]$tableId] = $true
        }
    }

    $availableNames = @{}
    foreach ($tableId in $usedTableIds.Keys) {
        $table = $report.dungeon.item_tables.([string]$tableId)
        if ($null -eq $table) {
            continue
        }
        foreach ($item in $table.items) {
            $name = $localization.item_name.([string]$item.item_id).ja
            if ($name) {
                $availableNames[$name] = $true
            }
        }
    }
    $availableByDungeon[$entry.Key] = $availableNames
}

foreach ($dungeonName in $manualAppearanceOverrides.Keys) {
    if (-not $availableByDungeon.ContainsKey($dungeonName)) {
        throw "手動出現情報のダンジョン名が不正です: $dungeonName"
    }
    foreach ($itemName in $manualAppearanceOverrides[$dungeonName]) {
        $availableByDungeon[$dungeonName][$itemName] = $true
    }
}

foreach ($row in $rows) {
    foreach ($dungeonName in $dungeons.Keys) {
        $row.$dungeonName = if ($availableByDungeon[$dungeonName].ContainsKey($row.アイテム名)) { 'Yes' } else { 'No' }
    }
}

$rows | Export-Csv -LiteralPath $resolvedCsvPath -NoTypeInformation -Encoding utf8BOM

$summary = foreach ($dungeonName in $dungeons.Keys) {
    [pscustomobject]@{
        Dungeon = $dungeonName
        Yes = @($rows | Where-Object { $_.$dungeonName -eq 'Yes' }).Count
        No = @($rows | Where-Object { $_.$dungeonName -ne 'Yes' }).Count
    }
}

$summary | Format-Table -AutoSize
Write-Host "更新完了: $resolvedCsvPath"
