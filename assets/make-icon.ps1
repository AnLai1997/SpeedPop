param([string]$Out = ".")
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$S = 1024
function C([string]$hex, [int]$a = 255) { $c = [System.Drawing.ColorTranslator]::FromHtml($hex); [System.Drawing.Color]::FromArgb($a, $c) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([float]$x, [float]$y) }

# Squircle (superellipse n=5) - HarmonyOS / iOS continuous corner
function Squircle([double]$cx, [double]$cy, [double]$r, [double]$n = 5) {
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 720; $i++) {
        $t = 2 * [Math]::PI * $i / 720
        $c = [Math]::Cos($t); $s = [Math]::Sin($t)
        $pts.Add((P ($cx + $r * [Math]::Sign($c) * [Math]::Pow([Math]::Abs($c), 2 / $n)) ($cy + $r * [Math]::Sign($s) * [Math]::Pow([Math]::Abs($s), 2 / $n))))
    }
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddPolygon($pts.ToArray()); $p
}
function Ellipse([double]$cx, [double]$cy, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse([float]($cx - $r), [float]($cy - $r), [float](2 * $r), [float](2 * $r)); $p
}
function RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc([float]$x, [float]$y, [float]$d, [float]$d, 180, 90)
    $p.AddArc([float]($x + $w - $d), [float]$y, [float]$d, [float]$d, 270, 90)
    $p.AddArc([float]($x + $w - $d), [float]($y + $h - $d), [float]$d, [float]$d, 0, 90)
    $p.AddArc([float]$x, [float]($y + $h - $d), [float]$d, [float]$d, 90, 90)
    $p.CloseFigure(); $p
}
function VGrad([double]$y0, [double]$y1, [string]$top, [string]$bottom, [int]$a0 = 255, [int]$a1 = 255) {
    New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 $y0), (P 0 $y1), (C $top $a0), (C $bottom $a1))
}
# Bong mem: ve nhieu lop hinh dang no rong dan, alpha nho (giong Gaussian)
function SoftShadowPath($g, [scriptblock]$shape, [int]$steps, [double]$spread, [int]$alpha, [string]$hex = "#000A2E") {
    for ($i = $steps; $i -ge 1; $i--) {
        $grow = $spread * $i / $steps
        $g.FillPath((New-Object System.Drawing.SolidBrush(C $hex ([int]($alpha / $steps)))), (& $shape $grow))
    }
}
# Chu canh giua theo khung chu thuc
function TextPath([string]$t, [string]$font, [double]$size, [double]$cx, [double]$cy) {
    $fam = New-Object System.Drawing.FontFamily($font)
    $tp = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Winding)
    $tp.AddString($t, $fam, [int][System.Drawing.FontStyle]::Regular, [float]$size, (P 0 0), [System.Drawing.StringFormat]::GenericTypographic)
    $bb = $tp.GetBounds()
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate([float]($cx - $bb.X - $bb.Width / 2), [float]($cy - $bb.Y - $bb.Height / 2))
    $tp.Transform($m); $tp
}

$bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
$g.Clear([System.Drawing.Color]::Transparent)

# --- Nen: squircle xanh dam, sang nhe goc tren trai ---
$bg = Squircle 512 512 512
$g.FillPath((New-Object System.Drawing.Drawing2D.LinearGradientBrush((P -1 -1), (P 1025 1025), (C '#3D7DFF'), (C '#0B2BA0'))), $bg)
$g.SetClip($bg)
$glow = Ellipse 250 30 560
$gb = New-Object System.Drawing.Drawing2D.PathGradientBrush($glow)
$gb.CenterColor = C '#FFFFFF' 40; $gb.SurroundColors = @(C '#FFFFFF' 0)
$g.FillPath($gb, $glow)

# --- Man hinh CarPlay (xe): dock mong ben trai + ban do toi co tuyen dan duong ---
$sx = 150; $sy = 382; $sw = 724; $sh = 462; $sr = 58
SoftShadowPath $g { param($k) RoundRect ($sx - $k) ($sy - $k + 28) ($sw + 2 * $k) ($sh + 2 * $k) ($sr + $k) } 14 44 140
$screen = RoundRect $sx $sy $sw $sh $sr
$g.FillPath((VGrad $sy ($sy + $sh) '#1A2440' '#0A0F1E'), $screen)
$g.SetClip($screen, [System.Drawing.Drawing2D.CombineMode]::Intersect)
$roadPen = New-Object System.Drawing.Pen((C '#FFFFFF' 15), 44)
$roadPen.StartCap = 'Round'; $roadPen.EndCap = 'Round'
$g.DrawBezier($roadPen, (P 330 900), (P 430 660), (P 640 710), (P 920 520))
$g.DrawLine($roadPen, (P 650 380), (P 720 900))
$route = New-Object System.Drawing.Pen((C '#4DA3FF'), 16)
$route.StartCap = 'Round'; $route.EndCap = 'Round'
$g.DrawBezier($route, (P 330 900), (P 430 660), (P 640 710), (P 920 520))
$g.FillRectangle((New-Object System.Drawing.SolidBrush(C '#FFFFFF' 10)), [float]$sx, [float]$sy, [float]98, [float]$sh)
$dockCols = @('#34C759', '#4DA3FF', '#FF9F0A')
for ($i = 0; $i -lt 3; $i++) {
    $g.FillPath((New-Object System.Drawing.SolidBrush(C $dockCols[$i] 235)), (RoundRect ($sx + 27) ($sy + 150 + $i * 82) 44 44 13))
}
$g.SetClip($bg)
$g.DrawPath((New-Object System.Drawing.Pen((C '#FFFFFF' 38), 4)), $screen)
# Mui ten vi tri tren tuyen
$arrow = New-Object System.Drawing.Drawing2D.GraphicsPath
$arrow.AddPolygon(@((P 0 -40), (P 30 34), (P 0 19), (P -30 34)))
$am = New-Object System.Drawing.Drawing2D.Matrix
$am.Translate(440, 752); $am.Rotate(48)
$arrow.Transform($am)
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#FFFFFF')), $arrow)

# --- Bong bong toc do noi tren man xe: vien thuoc trang [toc do | bien gioi han] ---
$bx = 248; $by = 190; $bw = 560; $bh = 240; $br = $bh / 2
SoftShadowPath $g { param($k) RoundRect ($bx - $k) ($by - $k + 26) ($bw + 2 * $k) ($bh + 2 * $k) ($br + $k) } 14 44 170
$pill = RoundRect $bx $by $bw $bh $br
$g.FillPath((VGrad $by ($by + $bh) '#FFFFFF' '#E8EDF5'), $pill)
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#121A2C')), (TextPath '52' 'Bahnschrift SemiBold' 176 ($bx + $br + 62) ($by + $br)))
$cx = $bx + $bw - $br; $cy = $by + $br; $R = $br - 24
$g.FillPath((VGrad ($cy - $R) ($cy + $R) '#FF5A5F' '#DF1F2D'), (Ellipse $cx $cy $R))
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#FFFFFF')), (Ellipse $cx $cy ($R - 21)))
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#121A2C')), (TextPath '60' 'Bahnschrift SemiBold' 112 $cx $cy))

$g.ResetClip(); $g.Dispose()
$bmp.Save((Join-Path $Out 'icon-1024.png'), [System.Drawing.Imaging.ImageFormat]::Png)

function Resize($src, [int]$n, [string]$path) {
    $b = New-Object System.Drawing.Bitmap($n, $n, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($b)
    $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'; $gg.CompositingQuality = 'HighQuality'; $gg.SmoothingMode = 'AntiAlias'
    $gg.DrawImage($src, 0, 0, $n, $n); $gg.Dispose()
    $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}
Resize $bmp 256 (Join-Path $Out 'CarSpeed.png')
Resize $bmp 29 (Join-Path $Out 'icon.png')
Resize $bmp 58 (Join-Path $Out 'icon@2x.png')
Resize $bmp 87 (Join-Path $Out 'icon@3x.png')
$bmp.Dispose()
