param([string]$Out = ".")
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$S = 1024
function C([string]$hex, [int]$a = 255) { $c = [System.Drawing.ColorTranslator]::FromHtml($hex); [System.Drawing.Color]::FromArgb($a, $c) }

# Squircle (superellipse n=5) - HarmonyOS / iOS continuous corner
function Squircle([double]$cx, [double]$cy, [double]$r, [double]$n = 5) {
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 720; $i++) {
        $t = 2 * [Math]::PI * $i / 720
        $c = [Math]::Cos($t); $s = [Math]::Sin($t)
        $x = $cx + $r * [Math]::Sign($c) * [Math]::Pow([Math]::Abs($c), 2 / $n)
        $y = $cy + $r * [Math]::Sign($s) * [Math]::Pow([Math]::Abs($s), 2 / $n)
        $pts.Add((New-Object System.Drawing.PointF([float]$x, [float]$y)))
    }
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddPolygon($pts.ToArray()); $p
}
function Ellipse([double]$cx, [double]$cy, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse([float]($cx - $r), [float]($cy - $r), [float](2 * $r), [float](2 * $r)); $p
}
# Bong mem: PathGradient tu tam (alpha) ra vien (trong suot)
function SoftShadow($g, [double]$cx, [double]$cy, [double]$r, [int]$alpha, [string]$hex = "#0A1E5C", [double]$focus = 0.72) {
    $p = Ellipse $cx $cy $r
    $b = New-Object System.Drawing.Drawing2D.PathGradientBrush($p)
    $b.CenterColor = C $hex $alpha
    $b.SurroundColors = @(C $hex 0)
    $b.FocusScales = New-Object System.Drawing.PointF([float]$focus, [float]$focus)
    $g.FillPath($b, $p)
}

$bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([System.Drawing.Color]::Transparent)

# --- Nen: squircle xanh HarmonyOS, gradient cheo + quang sang goc tren ---
$bg = Squircle 512 512 512
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(1024, 1024)), (C '#5FA8FF'), (C '#1D4FE0'))
$g.FillPath($lg, $bg)
$g.SetClip($bg)
SoftShadow $g 260 120 760 55 '#FFFFFF' 0   # quang sang mem tren-trai
SoftShadow $g 980 1040 640 70 '#0B2A9A' 0   # chieu sau duoi-phai

# --- Bong bong nho (vet bay ra tu bien bao) ---
$cx = 486; $cy = 476; $R = 318
SoftShadow $g 796 818 92 70
SoftShadow $g 878 900 52 60
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#FFFFFF' 235)), (Ellipse 786 800 66))
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#FFFFFF' 200)), (Ellipse 872 886 34))

# --- Bien gioi han toc do ---
SoftShadow $g ($cx + 10) ($cy + 34) ($R + 70) 120
$ring = Ellipse $cx $cy $R
$rg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, ($cy - $R))), (New-Object System.Drawing.Point(0, ($cy + $R))), (C '#FF6A6A'), (C '#E01E2E'))
$g.FillPath($rg, $ring)
$face = Ellipse $cx $cy ($R - 66)
$fg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, ($cy - $R))), (New-Object System.Drawing.Point(0, ($cy + $R))), (C '#FFFFFF'), (C '#EEF2F8'))
$g.FillPath($fg, $face)
# vien sang manh tren mep vong do (tao khoi)
$hl = New-Object System.Drawing.Pen((C "#FFFFFF" 45), 4)
$g.DrawArc($hl, [float]($cx - $R + 6), [float]($cy - $R + 6), [float](2 * $R - 12), [float](2 * $R - 12), 200, 140)

# --- So "60" (Bahnschrift ~ chu bien bao DIN), canh giua theo khung chu thuc ---
$fam = New-Object System.Drawing.FontFamily('Bahnschrift SemiBold')
$tp = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Winding)
$tp.AddString('60', $fam, [int][System.Drawing.FontStyle]::Regular, 320, (New-Object System.Drawing.PointF(0, 0)), [System.Drawing.StringFormat]::GenericTypographic)
$bb = $tp.GetBounds()
$m = New-Object System.Drawing.Drawing2D.Matrix
$m.Translate([float]($cx - $bb.X - $bb.Width / 2), [float]($cy - $bb.Y - $bb.Height / 2))
$tp.Transform($m)
$g.FillPath((New-Object System.Drawing.SolidBrush(C '#1B2233')), $tp)

$g.ResetClip(); $g.Dispose()
$bmp.Save((Join-Path $Out 'icon-1024.png'), [System.Drawing.Imaging.ImageFormat]::Png)

function Resize($src, [int]$n, [string]$path) {
    $b = New-Object System.Drawing.Bitmap($n, $n, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($b)
    $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'; $gg.CompositingQuality = 'HighQuality'; $gg.SmoothingMode = 'AntiAlias'
    $gg.DrawImage($src, 0, 0, $n, $n); $gg.Dispose()
    $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}
Resize $bmp 256 (Join-Path $Out 'LimitBubble.png')
Resize $bmp 29 (Join-Path $Out 'icon.png')
Resize $bmp 58 (Join-Path $Out 'icon@2x.png')
Resize $bmp 87 (Join-Path $Out 'icon@3x.png')
$bmp.Dispose()
