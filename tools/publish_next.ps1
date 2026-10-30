# 다음 발행 글 하나를 _drafts 에서 _posts 로 옮긴다.
# - 대상: front matter 에 "status: ready" 가 있는 초안 중 파일명 순서가 가장 앞선 것 하나
# - git / 네트워크 작업은 하지 않는다 (커밋·push 는 워크플로가 담당)
# - Windows PowerShell 5.1 과 PowerShell 7(Actions 러너) 모두에서 동작
#
# 사용:  pwsh tools/publish_next.ps1 [-Site .] [-DryRun] [-Now "2026-11-03 09:00"]
param(
    [string]$Site = ".",
    [switch]$DryRun,
    [string]$Now = ""
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$drafts = Join-Path $Site "_drafts"
$posts  = Join-Path $Site "_posts"
if (-not (Test-Path $drafts)) { throw "_drafts 폴더가 없습니다: $drafts" }
if (-not (Test-Path $posts))  { New-Item -ItemType Directory -Path $posts | Out-Null }

# 발행 시각: 한국 시간(UTC+9). -Now 로 덮어쓸 수 있다(테스트용).
if ($Now) {
    $stamp = [datetime]::Parse($Now)
} else {
    $stamp = [datetime]::UtcNow.AddHours(9)
}
$dateStr = $stamp.ToString("yyyy-MM-dd")
$dateFm  = $stamp.ToString("yyyy-MM-dd HH:mm:ss") + " +0900"

$ready = @()
foreach ($f in (Get-ChildItem $drafts -Filter "*.md" -File | Sort-Object Name)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $utf8)
    $m = [regex]::Match($text, "(?s)\A---\r?\n(.*?)\r?\n---")
    if (-not $m.Success) { Write-Host "SKIP (front matter 없음): $($f.Name)"; continue }
    if ($m.Groups[1].Value -match "(?m)^status:\s*ready\s*$") { $ready += $f }
}

if ($ready.Count -eq 0) {
    Write-Host "NOTHING: 발행 대기(status: ready) 초안이 없습니다."
    exit 0
}

$pick = $ready[0]
$slug = $pick.BaseName -replace "^\d+[-_]", ""
$target = Join-Path $posts "$dateStr-$slug.md"
if (Test-Path $target) { throw "이미 같은 이름의 글이 있습니다: $target" }

$text = [System.IO.File]::ReadAllText($pick.FullName, $utf8)
$fmEnd = [regex]::Match($text, "(?s)\A---\r?\n.*?\r?\n---").Length
$head = $text.Substring(0, $fmEnd)
$rest = $text.Substring($fmEnd)

$head = [regex]::Replace($head, "(?m)^status:\s*ready\s*\r?\n?", "")
$head = [regex]::Replace($head, "(?m)^date:.*\r?\n?", "")
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
# 닫는 --- 바로 앞에 date 줄을 넣는다
$head = [regex]::Replace($head, "(\r?\n)---\z", "$nl" + "date: $dateFm" + '$1---')
$out = $head + $rest

$title = [regex]::Match($head, '(?m)^title:\s*"?(.*?)"?\s*$').Groups[1].Value

if ($DryRun) {
    Write-Host "DRY-RUN: 아래 글이 발행 대상입니다 (파일 변경 없음)"
    Write-Host "  초안 : $($pick.Name)"
    Write-Host "  제목 : $title"
    Write-Host "  이동 : _posts/$dateStr-$slug.md"
    Write-Host "  date : $dateFm"
    Write-Host "  남은 ready 초안: $($ready.Count - 1)편"
    exit 0
}

[System.IO.File]::WriteAllText($target, $out, $utf8)
Remove-Item $pick.FullName
Write-Host "PUBLISHED: $title"
Write-Host "  _posts/$dateStr-$slug.md"
Write-Host "  남은 ready 초안: $($ready.Count - 1)편"
