# Genera los iconos de Android y la imagen de arranque a partir de assets/logo.jpg.
# Uso (desde la raíz del repo, en Windows): powershell -File tres_pisos_app/tool/generar_iconos.ps1

Add-Type -AssemblyName System.Drawing

$raiz = Resolve-Path 'tres_pisos_app'
$res = Join-Path $raiz 'android\app\src\main\res'
$original = New-Object System.Drawing.Bitmap((Join-Path $raiz 'assets\logo.jpg'))
$w = $original.Width; $h = $original.Height

# Color de fondo: promedio de las cuatro esquinas del logo, para que el borde de la foto no se note.
$suma = @(0, 0, 0); $n = 0
foreach ($esquina in @(@(0, 0), @(($w - 12), 0), @(0, ($h - 12)), @(($w - 12), ($h - 12)))) {
    for ($i = 0; $i -lt 12; $i++) { for ($j = 0; $j -lt 12; $j++) {
        $c = $original.GetPixel($esquina[0] + $i, $esquina[1] + $j)
        $suma[0] += $c.R; $suma[1] += $c.G; $suma[2] += $c.B; $n++
    } }
}
$fondo = [System.Drawing.Color]::FromArgb([int]($suma[0] / $n), [int]($suma[1] / $n), [int]($suma[2] / $n))
"Fondo: #{0:X2}{1:X2}{2:X2}" -f $fondo.R, $fondo.G, $fondo.B

# Logo con los bordes difuminados a transparente (8 % de cada lado).
$logo = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$margen = [Math]::Round([Math]::Min($w, $h) * 0.08)
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $d = [Math]::Min([Math]::Min($x, $w - 1 - $x), [Math]::Min($y, $h - 1 - $y))
        $c = $original.GetPixel($x, $y)
        $a = if ($d -ge $margen) { 255 } else { [int](255 * $d / $margen) }
        $logo.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B))
    }
}
$original.Dispose()

# Dibuja el logo centrado en un lienzo cuadrado de $lado px; el alto del logo es $proporcion del lado.
function Nuevo-Icono([int]$lado, [double]$proporcion, [bool]$transparente, [string]$destino) {
    $bmp = New-Object System.Drawing.Bitmap($lado, $lado, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    if ($transparente) { $g.Clear([System.Drawing.Color]::Transparent) } else { $g.Clear($fondo) }
    $alto = $lado * $proporcion
    $ancho = $alto * $logo.Width / $logo.Height
    $x = ($lado - $ancho) / 2
    $y = ($lado - $alto) / 2
    $g.DrawImage($logo, [single]$x, [single]$y, [single]$ancho, [single]$alto)
    $g.Dispose()
    New-Item -ItemType Directory -Force (Split-Path $destino) | Out-Null
    $bmp.Save($destino, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$densidades = @{ 'mdpi' = 1.0; 'hdpi' = 1.5; 'xhdpi' = 2.0; 'xxhdpi' = 3.0; 'xxxhdpi' = 4.0 }
foreach ($d in $densidades.GetEnumerator()) {
    # Icono clásico (Android 7): 48 dp, el letrero ocupa casi todo el alto.
    Nuevo-Icono ([int](48 * $d.Value)) 0.92 $false (Join-Path $res "mipmap-$($d.Key)\ic_launcher.png")
    # Capa frontal del icono adaptativo (Android 8+): 108 dp; el letrero cabe en la zona segura central.
    Nuevo-Icono ([int](108 * $d.Value)) 0.60 $true (Join-Path $res "mipmap-$($d.Key)\ic_launcher_foreground.png")
}

# Pantalla de arranque: el letrero sobre fondo oscuro (sin destello blanco). JPEG para que pese poco.
$arranque = Join-Path $res 'drawable-nodpi\logo_arranque.jpg'
Remove-Item (Join-Path $res 'drawable-nodpi\logo_arranque.png') -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Split-Path $arranque) | Out-Null
$bmp = New-Object System.Drawing.Bitmap(300, 452)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear($fondo)
$g.DrawImage($logo, 0, 0, 300, 452)
$g.Dispose()
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$calidad = New-Object System.Drawing.Imaging.EncoderParameters(1)
$calidad.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]88)
$bmp.Save($arranque, $jpeg, $calidad)
$bmp.Dispose()
Set-Content (Join-Path $env:TEMP 'claude\color_fondo.txt') ('#{0:X2}{1:X2}{2:X2}' -f $fondo.R, $fondo.G, $fondo.B)

# Vista previa para revisar el resultado.
Nuevo-Icono 432 0.60 $false (Join-Path $env:TEMP 'claude\vista_adaptativo.png')
$logo.Dispose()
Get-ChildItem $res -Recurse -Filter *.png | ForEach-Object { '{0,6} {1}' -f $_.Length, $_.FullName.Substring($res.Length + 1) }

