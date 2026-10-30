# 글(.md)의 front matter와 본문 표/문장에서 값을 읽어 그림 3종을 만든다.
#   assets/img/<글 slug>/cover.svg  (1200x630 대표 이미지)
#   assets/img/<글 slug>/cover.png  (같은 카드의 PNG. SNS 미리보기용. Windows 에서만 생성)
#   assets/img/<글 slug>/card.svg   (인사 카드를 사원증 모양으로)
#   assets/img/<글 slug>/steps.svg  (전·후 단계 비교)
# 글에는 숫자나 문장을 새로 만들어 넣지 않는다. 글에 적힌 값만 그린다.
# 본문에는 "## 인사 카드" 와 "## 전과 후" 제목 바로 아래에 그림 줄을, front matter 에는 image: 줄을 넣는다.
# 여러 번 실행해도 같은 결과가 나온다(이미 있으면 갱신).
#
# 사용:  powershell -File tools/make_images.ps1                 (_drafts, _posts 의 모든 글)
#        powershell -File tools/make_images.ps1 -Post _drafts/01-....md
#        옵션: -Site <사이트 폴더>  -NoInsert (본문·front matter 는 건드리지 않음)  -NoPng
param(
    [string]$Site = ".",
    [string]$Post = "",
    [switch]$NoInsert,
    [switch]$NoPng
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 색: 남색(바탕·제목), 노랑(강조), 연회색(카드 바탕). 나머지는 흰색과 회색 글자.
$NAVY = "#1B2A49"; $AMBER = "#F5A623"; $PAPER = "#F4F6FA"; $GRAY = "#5B6475"
$FONT = "'Noto Sans KR','Malgun Gothic','Apple SD Gothic Neo',sans-serif"

function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }

# 글자 폭 추정(em 단위): 한글·전각 1.0, 영문 대문자 0.68, 영문 소문자·숫자 0.56, 공백 0.3, 그 밖의 기호 0.5
function TextWidth([string]$s, [double]$size) {
    $w = 0.0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -gt 0x2E80) { $w += 1.0 }
        elseif ($ch -match "[A-Z]") { $w += 0.68 }
        elseif ($ch -match "[a-z0-9]") { $w += 0.56 }
        elseif ($ch -eq " ") { $w += 0.3 }
        else { $w += 0.5 }
    }
    return $w * $size
}

# 최대 폭을 넘지 않게 줄바꿈한다. 공백 단위로 먼저 나누고, 한 단어가 너무 길면 글자 단위로 자른다.
function WrapText([string]$s, [double]$size, [double]$maxW) {
    $lines = @(); $cur = ""
    foreach ($word in ($s -split " ")) {
        $try = if ($cur) { "$cur $word" } else { $word }
        if ((TextWidth $try $size) -le $maxW) { $cur = $try; continue }
        if ($cur) { $lines += $cur; $cur = "" }
        if ((TextWidth $word $size) -le $maxW) { $cur = $word; continue }
        foreach ($ch in $word.ToCharArray()) {
            $try = "$cur$ch"
            if ((TextWidth $try $size) -le $maxW) { $cur = $try } else { $lines += $cur; $cur = [string]$ch }
        }
    }
    if ($cur) { $lines += $cur }
    return ,$lines
}

function T([double]$x, [double]$y, [double]$size, [string]$weight, [string]$fill, [string]$text, [string]$anchor = "start", [string]$extra = "") {
    return "<text x=""$x"" y=""$y"" font-size=""$size"" font-weight=""$weight"" fill=""$fill"" text-anchor=""$anchor"" $extra>$(Esc $text)</text>`n"
}

function SvgHead([int]$w, [int]$h, [string]$title) {
    return "<svg xmlns=""http://www.w3.org/2000/svg"" width=""$w"" height=""$h"" viewBox=""0 0 $w $h"" font-family=""$FONT"" role=""img"" aria-label=""$(Esc $title)"">`n<title>$(Esc $title)</title>`n"
}

# ---- 글 읽기 ----
function ReadPost([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $m = [regex]::Match($text, "(?s)\A---\r?\n(.*?)\r?\n---")
    if (-not $m.Success) { return $null }
    $fm = $m.Groups[1].Value
    $get = { param($k) $mm = [regex]::Match($fm, "(?m)^$k\s*:\s*""?(.*?)""?\s*$"); if ($mm.Success) { $mm.Groups[1].Value } else { "" } }
    $p = @{ Path = $path; Text = $text; Title = (& $get "title"); Subtitle = (& $get "subtitle") }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $name = $name -replace "^\d{4}-\d{2}-\d{2}-", ""
    $p.Slug = $name -replace "^\d+[-_]", ""

    # 인사 카드 표
    $p.Card = [ordered]@{}
    $sec = [regex]::Match($text, "(?ms)^## 인사 카드\s*\r?\n(.*?)(?=^## |\z)")
    if ($sec.Success) {
        foreach ($ln in ($sec.Groups[1].Value -split "\r?\n")) {
            $cells = [regex]::Match($ln, "^\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|\s*$")
            if ($cells.Success -and $cells.Groups[1].Value -ne "---" -and $cells.Groups[2].Value -notmatch "^-+$") {
                $p.Card[$cells.Groups[1].Value] = $cells.Groups[2].Value
            }
        }
    }

    # 전·후 단계
    $p.Before = $null; $p.After = $null; $p.AiTime = ""; $p.Dim = ""
    $stepRe = "단계:\s*([^)]*)\)"
    foreach ($ln in ($text -split "\r?\n")) {
        if ($ln -match "^- 전:.*?(\d+)단계:\s*([^)]*)\)") {
            $p.Before = @{ Count = $Matches[1]; Steps = @($Matches[2] -split "\s*,\s*" | Where-Object { $_ }) }
        }
        elseif ($ln -match "^- 후:.*?([\d~]+)단계:\s*([^)]*)\)") {
            $p.After = @{ Count = $Matches[1]; Steps = @($Matches[2] -split "\s*,\s*" | Where-Object { $_ }) }
            if ($ln -match "AI 처리\s*([\d~]+초)") { $p.AiTime = $Matches[1] }
        }
        elseif ($ln -match '그중\s*[\x22“]([^\x22”]+)[\x22”]') { $p.Dim = $Matches[1] }
    }
    return $p
}

function CleanCell([string]$v) {
    $v = [regex]::Replace($v, "\[([^\]]+)\]\([^)]*\)", "`$1")   # 링크는 글자만
    return $v
}

# ---- 대표 이미지 ----
function MakeCover($p, [string]$dir) {
    $badge = ""
    if ($p.Card.Contains("팀원")) { $badge = ($p.Card["팀원"] -replace "\s*\(AI\)\s*$", "") }
    $s = SvgHead 1200 630 ("AI 본부장 대표 이미지: " + $p.Title)
    $s += "<rect width=""1200"" height=""630"" fill=""$NAVY""/>`n<rect x=""0"" y=""0"" width=""16"" height=""630"" fill=""$AMBER""/>`n"
    $s += T 80 96 34 "700" $AMBER "AI 본부장" "start" "letter-spacing=""1"""
    $tSize = 56
    $lines = WrapText $p.Title $tSize 960
    $y = 220
    foreach ($ln in $lines) { $s += T 80 $y $tSize "700" "#FFFFFF" $ln; $y += 76 }
    if ($p.Subtitle) {
        $y += 8
        foreach ($ln in (WrapText $p.Subtitle 30 960)) { $s += T 80 $y 30 "400" "#C9D1E3" $ln; $y += 44 }
    }
    if ($badge) {
        $bw = [math]::Round((TextWidth $badge 28) + 56)
        $by = [math]::Min(560, [math]::Max(500, $y - 20))
        $s += "<rect x=""80"" y=""$by"" width=""$bw"" height=""56"" rx=""28"" fill=""$AMBER""/>`n"
        $s += T (80 + $bw / 2) ($by + 38) 28 "700" $NAVY $badge "middle"
    }
    $s += "</svg>`n"
    [System.IO.File]::WriteAllText((Join-Path $dir "cover.svg"), $s, $utf8)
    return @{ Badge = $badge; Lines = $lines }
}

function MakeCoverPng($p, [string]$dir, [string]$badge) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 1200, 630
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAliasGridFit"
    $navy = [System.Drawing.ColorTranslator]::FromHtml($NAVY); $amber = [System.Drawing.ColorTranslator]::FromHtml($AMBER)
    $g.Clear($navy)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $amber), 0, 0, 16, 630)
    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $draw = {
        param($text, $px, $x, $y, $bold, $color)
        $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
        $f = New-Object System.Drawing.Font("Malgun Gothic", $px, $style, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString($text, $f, (New-Object System.Drawing.SolidBrush $color), $x, $y, $fmt)
        $f.Dispose()
    }
    $white = [System.Drawing.Color]::White; $soft = [System.Drawing.ColorTranslator]::FromHtml("#C9D1E3")
    & $draw "AI 본부장" 34 80 62 $true $amber
    $y = 220 - 50
    foreach ($ln in (WrapText $p.Title 56 900)) { & $draw $ln 56 80 $y $true $white; $y += 76 }
    if ($p.Subtitle) {
        $y += 8
        foreach ($ln in (WrapText $p.Subtitle 30 900)) { & $draw $ln 30 80 ($y + 22) $false $soft; $y += 44 }
    }
    if ($badge) {
        $f = New-Object System.Drawing.Font("Malgun Gothic", 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $bw = [int]($g.MeasureString($badge, $f, 2000, $fmt).Width + 56)
        $f.Dispose()
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 28; $x0 = 80; $y0 = [math]::Min(560, [math]::Max(500, $y + 30)); $h = 56
        $path.AddArc($x0, $y0, $r * 2, $h, 90, 180); $path.AddArc($x0 + $bw - $r * 2, $y0, $r * 2, $h, 270, 180); $path.CloseFigure()
        $g.FillPath((New-Object System.Drawing.SolidBrush $amber), $path)
        $f = New-Object System.Drawing.Font("Malgun Gothic", 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString($badge, $f, (New-Object System.Drawing.SolidBrush $navy), $x0 + 28, $y0 + 10, $fmt)
        $f.Dispose()
    }
    $g.Dispose()
    $bmp.Save((Join-Path $dir "cover.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# ---- 인사 카드(사원증) ----
function MakeCard($p, [string]$dir) {
    $c = $p.Card
    if ($c.Count -eq 0) { return $false }
    $role = if ($c.Contains("팀원")) { $c["팀원"] } else { $p.Title }
    $rows = @()
    foreach ($k in @("하는 일", "일하는 방식", "월 비용", "처리 시간")) {
        if (-not $c.Contains($k)) { continue }
        $v = CleanCell $c[$k]
        if ($k -eq "월 비용") { $v = ($v -replace "\s*\(.*$", "") }
        if ($k -eq "처리 시간") { $v = ($v -replace "\..*$", "") }
        $rows += , @($k, $v)
    }
    $h = 390 + 76 * $rows.Count
    $s = SvgHead 900 $h ("인사 카드: " + $role)
    $s += "<rect width=""900"" height=""$h"" fill=""$PAPER""/>`n"
    $s += "<rect x=""40"" y=""40"" width=""820"" height=""$($h - 80)"" rx=""28"" fill=""#FFFFFF"" stroke=""$NAVY"" stroke-width=""3""/>`n"
    $s += "<rect x=""40"" y=""40"" width=""820"" height=""120"" rx=""28"" fill=""$NAVY""/>`n<rect x=""40"" y=""120"" width=""820"" height=""40"" fill=""$NAVY""/>`n"
    $s += "<rect x=""410"" y=""58"" width=""80"" height=""16"" rx=""8"" fill=""$PAPER""/>`n"
    $s += T 450 128 36 "700" "#FFFFFF" "AI 본부장 사원증" "middle"
    $s += "<circle cx=""130"" cy=""250"" r=""46"" fill=""$AMBER""/>`n"
    $s += T 130 264 40 "700" $NAVY "AI" "middle"
    $s += T 210 238 22 "400" $GRAY "팀원"
    $y = 280
    foreach ($ln in (WrapText $role 40 600)) { $s += T 210 $y 40 "700" $NAVY $ln; $y += 48 }
    $y = 330
    foreach ($r in $rows) {
        $s += "<line x1=""80"" y1=""$($y - 20)"" x2=""820"" y2=""$($y - 20)"" stroke=""#D9DEE8"" stroke-width=""2""/>`n"
        $s += T 80 ($y + 22) 22 "700" $GRAY $r[0]
        $vl = WrapText $r[1] 26 560
        $yy = $y + 24
        foreach ($ln in $vl) { $s += T 260 $yy 26 "400" $NAVY $ln; $yy += 34 }
        $y += 76
    }
    $s += "</svg>`n"
    [System.IO.File]::WriteAllText((Join-Path $dir "card.svg"), $s, $utf8)
    return $true
}

# ---- 전·후 단계 ----
function MakeSteps($p, [string]$dir) {
    if (-not $p.Before -or -not $p.After) { return $false }
    $n = [math]::Max($p.Before.Steps.Count, $p.After.Steps.Count)
    $rowH = 84; $top = 190
    $h = $top + $n * $rowH + 100
    $s = SvgHead 1200 $h ("전과 후 단계 비교: 전 " + $p.Before.Count + "단계, 후 " + $p.After.Count + "단계")
    $s += "<rect width=""1200"" height=""$h"" fill=""$PAPER""/>`n"
    $s += T 60 70 36 "700" $NAVY "전과 후"
    $s += T 60 108 22 "400" $GRAY "같은 일을 하는 데 거치는 단계"
    # 열 머리
    $s += "<rect x=""60"" y=""122"" width=""500"" height=""12"" rx=""6"" fill=""$GRAY""/>`n"
    $s += "<rect x=""640"" y=""122"" width=""500"" height=""12"" rx=""6"" fill=""$AMBER""/>`n"
    $s += T 60 170 28 "700" $GRAY ("전 · " + $p.Before.Count + "단계")
    $s += T 640 170 28 "700" $NAVY ("후 · " + $p.After.Count + "단계")
    $y = $top + 20
    for ($i = 0; $i -lt $p.Before.Steps.Count; $i++) {
        $st = $p.Before.Steps[$i]
        $dim = ($p.Dim -and $st.Contains($p.Dim))
        $op = if ($dim) { "0.38" } else { "1" }
        $dash = if ($dim) { " stroke-dasharray=""8 6""" } else { "" }
        $s += "<g opacity=""$op"">`n<rect x=""60"" y=""$y"" width=""500"" height=""64"" rx=""14"" fill=""#FFFFFF"" stroke=""$GRAY"" stroke-width=""2""$dash/>`n"
        $s += "<circle cx=""96"" cy=""$($y + 32)"" r=""20"" fill=""$GRAY""/>`n"
        $s += T 96 ($y + 40) 22 "700" "#FFFFFF" ([string]($i + 1)) "middle"
        $s += T 132 ($y + 40) 26 "400" $NAVY $st
        $s += "</g>`n"
        if ($dim) { $s += T 540 ($y + 39) 20 "700" $GRAY "후에는 빠져요" "end" }
        $y += $rowH
    }
    $y = $top + 20
    for ($i = 0; $i -lt $p.After.Steps.Count; $i++) {
        $st = $p.After.Steps[$i]
        $opt = $st.StartsWith("필요하면")
        $dash = if ($opt) { " stroke-dasharray=""8 6""" } else { "" }
        $s += "<rect x=""640"" y=""$y"" width=""500"" height=""64"" rx=""14"" fill=""#FFFFFF"" stroke=""$NAVY"" stroke-width=""3""$dash/>`n"
        $s += "<circle cx=""676"" cy=""$($y + 32)"" r=""20"" fill=""$NAVY""/>`n"
        $s += T 676 ($y + 40) 22 "700" "#FFFFFF" ([string]($i + 1)) "middle"
        $s += T 712 ($y + 40) 26 "400" $NAVY $st
        $y += $rowH
    }
    $foot = $h - 40
    if ($p.AiTime) { $s += T 640 $foot 26 "700" $NAVY ("AI 처리 " + $p.AiTime) }
    $s += T 60 $foot 20 "400" $GRAY "단계 수는 작업을 나눠 센 값이에요 · 사례는 가상이에요"
    $s += "</svg>`n"
    [System.IO.File]::WriteAllText((Join-Path $dir "steps.svg"), $s, $utf8)
    return $true
}

# ---- 본문·front matter 갱신 ----
function UpdatePost($p, [bool]$hasCard, [bool]$hasSteps, [bool]$hasPng) {
    $text = $p.Text
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $slug = $p.Slug
    $imgPath = if ($hasPng) { "cover.png" } else { "cover.svg" }
    $img = "/assets/img/$slug/$imgPath"
    $m = [regex]::Match($text, "(?s)\A---\r?\n(.*?)\r?\n---")
    $fm = $m.Groups[1].Value
    if ($fm -match "(?m)^image:") { $fm = [regex]::Replace($fm, "(?m)^image:.*$", "image: $img") }
    else { $fm = $fm + $nl + "image: $img" }
    $text = "---" + $nl + $fm + $nl + "---" + $text.Substring($m.Length)

    $ins = {
        param($text, $heading, $marker, $alt, $file)
        $url = "{{ '/assets/img/$slug/$file' | relative_url }}"
        $line = "![$alt]($url)<!-- img:$marker -->"
        if ($text -match "(?m)^!\[[^\]]*\]\([^)]*\)<!-- img:$marker -->[ \t]*$") {
            return [regex]::Replace($text, "(?m)^!\[[^\]]*\]\([^)]*\)<!-- img:$marker -->[ \t]*$", $line.Replace("`$", "`$`$"))
        }
        return [regex]::Replace($text, "(?m)^($heading)\s*\r?\n", ("`$1" + $nl + $nl + $line.Replace("`$", "`$`$") + $nl + $nl), 1)
    }
    if ($hasCard) {
        $role = if ($p.Card.Contains("팀원")) { $p.Card["팀원"] } else { $p.Title }
        $text = & $ins $text "## 인사 카드" "card" ("사원증 모양으로 정리한 인사 카드: " + $role) "card.svg"
    }
    if ($hasSteps) {
        $alt = "전 " + $p.Before.Count + "단계와 후 " + $p.After.Count + "단계를 나란히 놓은 그림. 빠지는 단계는 흐리게 표시했어요"
        $text = & $ins $text "## 전과 후" "steps" $alt "steps.svg"
    }
    [System.IO.File]::WriteAllText($p.Path, $text, $utf8)
}

# ---- 실행 ----
$files = @()
if ($Post) { $files += (Resolve-Path $Post).Path }
else {
    foreach ($d in @("_drafts", "_posts")) {
        $dp = Join-Path $Site $d
        if (Test-Path $dp) { $files += (Get-ChildItem $dp -Filter "*.md" -File | Sort-Object Name | ForEach-Object { $_.FullName }) }
    }
}
if ($files.Count -eq 0) { Write-Host "NOTHING: 처리할 글이 없습니다."; exit 0 }

foreach ($f in $files) {
    $p = ReadPost $f
    if (-not $p -or -not $p.Title) { Write-Host "SKIP (front matter 또는 title 없음): $f"; continue }
    $dir = Join-Path (Join-Path (Join-Path $Site "assets") "img") $p.Slug
    New-Item -ItemType Directory -Force $dir | Out-Null
    $cover = MakeCover $p $dir
    $hasPng = $false
    if (-not $NoPng) {
        try { MakeCoverPng $p $dir $cover.Badge; $hasPng = $true }
        catch { Write-Host "WARN: cover.png 를 만들지 못했습니다(이 환경에 System.Drawing 이 없을 수 있어요): $($_.Exception.Message)" }
    }
    $hasCard = MakeCard $p $dir
    $hasSteps = MakeSteps $p $dir
    if (-not $NoInsert) { UpdatePost $p $hasCard $hasSteps $hasPng }
    Write-Host ("OK: {0}  -> assets/img/{1}/ cover.svg{2}{3}{4}" -f ([System.IO.Path]::GetFileName($f)), $p.Slug, $(if ($hasPng) { " cover.png" } else { "" }), $(if ($hasCard) { " card.svg" } else { "" }), $(if ($hasSteps) { " steps.svg" } else { "" }))
}
