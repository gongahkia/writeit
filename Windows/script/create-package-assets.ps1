param(
  [Parameter(Mandatory = $true)]
  [string]$AssetDirectory
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $AssetDirectory | Out-Null

Add-Type -AssemblyName System.Drawing
foreach ($name in @("Square44x44Logo.png", "Square150x150Logo.png", "Square310x310Logo.png", "Wide310x150Logo.png")) {
  $path = Join-Path $AssetDirectory $name
  if (Test-Path $path) { continue }
  $width = if ($name -eq "Wide310x150Logo.png") { 620 } else { 400 }
  $height = if ($name -eq "Wide310x150Logo.png") { 300 } else { 400 }
  $bitmap = New-Object System.Drawing.Bitmap $width, $height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([System.Drawing.Color]::FromArgb(24, 24, 24))
  $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(95, 206, 178))
  $font = New-Object System.Drawing.Font "Segoe UI", ([Math]::Min($width, $height) / 3), ([System.Drawing.FontStyle]::Bold)
  $format = New-Object System.Drawing.StringFormat
  $rectangle = [System.Drawing.RectangleF]::new(0, 0, $width, $height)
  $format.Alignment = [System.Drawing.StringAlignment]::Center
  $format.LineAlignment = [System.Drawing.StringAlignment]::Center
  $graphics.DrawString("W", $font, $brush, $rectangle, $format)
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $format.Dispose()
  $font.Dispose()
  $brush.Dispose()
  $graphics.Dispose()
  $bitmap.Dispose()
}
