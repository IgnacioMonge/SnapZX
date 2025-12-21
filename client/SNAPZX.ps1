# =========================
# Strictness / diagnostics
# =========================
Set-StrictMode -Version Latest

function Invoke-UI {
    param([Parameter(Mandatory=$true)][scriptblock]$Action)
    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]$Action)
    } else {
        & $Action
    }
}

# Force cmdlet non-terminating errors to be catchable
if (-not $global:PSDefaultParameterValues) { $global:PSDefaultParameterValues = @{} }
$global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$ErrorActionPreference = 'Continue'

# SNAPZX SNA Uploader (ZX Spectrum) - version 3.9 (AppData Config)
# (C) M. Monge García 2025

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.NetworkInformation

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$B64_LOGO = "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"
$B64_ICON = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAWqSURBVFhHzZZrbFNlGMf/z+m6snX3DbZ15TYKGi5uHSgDIuJgMMZGYvYBY3AEnYoBg4NJRoRE4hBQokElCrKBrBvdhQQTDFEwUz9sCUvQb86AIBQSGMgMbqPXf8w5XS+jHSAkYJNfztv39vze57znPQcAIJD9AvEJhI+YC2r8xy8AYD+AMAEQd0Hto4hQouDv458n0FdDbQ8LPjRXNAF10J0Bh9clJibSZMpmdnYI9X9mZmZQIiQTJnG/AuHBFVGoKAr1ej2fnjWL8+bOpd1up8/rpc/ro88X4tatW1yyZAkXLFjAnJycUGZCAYcWM6LA8OBGo5FWq5UNDQ1sstnYd7OPbpeLHrebXo83Eq+Xbrdbo7u7m+s2bqDJnEODwRAW/B4CamNMTAzz8608ceKEtjJtUpeLTqeTt2/f5sDAAE93d7Ozs5NdXV3aVSt3drG/v5+Dg4N0OV30uj2aVG1tLSdbJmuZDOyHEQSEsbGx3LljJwcHBrSVqsH7+vp44fwF1tXVaSletGiR1k/R6agLQxUvKipicXEx6w8coMPhoMft0cSvXb2mZdJkMlGnU6ILqJUrV66ky+XWVupyOvnt8eOsqKjwDxDRgo6elMv8ZaXMKy1hfulSWstKaS1bxoLyMo7Lz9P6qKtMSkriqVOntKyoEmo2D319KJiJqALLy5fz0sVL7Onpoc1mY3x8PEVRmJSVycLKSm5osXPXmTNsdbnY4nL6catll3b97NxZVrfYObV4IePTUjh69GhtU/7Y0cG/btxgfX19+MaMFFBRUzh27Fito8Fo5FMlJTzidrPV52Wbx802l5ONly+z0eGgzeHQrodVrlxhm9PJo14PWz1ufvrneY7Ly6M+Nlabq6ysjFlZWdoZMuIt8O9W0dKUmZvL1/Z9yab+frZ7vdzT8xtr7Ha+vu8LZkwYz3SzeRhZFgvfaqjnOy1HePh6L1ucTu51XOLC9esZG28cSv1dnoLwR1A9zVJzTKzYuoVf9V7j+uYmTpk/P9SekEpkWwhTCElIDo59fvUq7jx9mnvOn+fsypepj48Ljh1R4M5zQGWU0UjLnMLgxJg+n1ixmdj9M2HvJVqvE23XifZeYtd3REWNXw5g2oQJtMybR12sPuJkHFEgmkQQ61Ji1y/EUQ/Rfo04ctVP81Wi6SrR6CLqnUT5MSKxwC8cDDqcBxAQIn0qUX6WKP2JME8nzE/6yVGvM4j87UTRFSKvkYhJiZjjngIjdBqOmAikEIYEwpxPmK3E2JlEnBpQCCWXwKjIcdGJFAiXiDIglNbCV4jdN4kP+vys+YaIU+998JS7H6IL3BeGFGLODqLqb+KNW0TBJorERLx2R+LhBdRJ9NmE+SUi7TkC+oggd2OYwIN/kgVu19Bb7r/zsAIPTXQBZYhAOcrAiG+84agZCc9KoByRqegC/p0eQpUIlMP7aB+m4W1BqfDHOfA/8B4I1EURSABYDXAzwCoBs5LBjyvBiRnCqgVg8QyhwSBctxbctg2cZBHGpgqnrBVOelWYWqAQo4zEimrizTqicDEl5gki9UMixkKkfEToC8IzERJQIL7ZAK8DXAVwjIDTc0BfA3isBjxZDdaUCK2zhOfOgQcPgjYbaBwvXPi9cPoWYcFuoeh0RMoY4vOTRNGLFOiJpPeInF4iebd2SI2YgTSAawD+AHCjgNNM4D82cN9qcKAB3FQinPmM8NJFsLkZbGv3CyzqEE5cJTSMUYg4I/FJG7H1MGXMOIqSSqS8T2T96s+Akh5dQDeUgWaAewGmC2hOBpuqwNwMYc1isCxPODFXWFcHLl4sfLsaNKQLp9UKR2X4P9ckLpFYt5N49xDl2Rco+plEagMhGUTqAcJQFP0WCMQDiFcJ487/EkCGXyH+vqF2xU+wTi0HQKBe3fR/BAS2C6RHIL8/Qs4KpEMT+L/85HHwLy4zJtRx7UizAAAAAElFTkSuQmCC"


# --- CONFIGURATION (STABLE v2.6 VALUES - UNTOUCHED) ---
$cfg = [pscustomobject]@{
  
    # NETWORK
    SOCKET_BUFFER_SIZE = 1024 
    CONN_FAIL_THRESHOLD = 2
    CONN_GRACE_MS = 3000
    LAIN_PORT = 6144
    
    SNA_48K_SIZE = 49179
    SNA_128K_SIZE = 131103
    DESIRED_SEND_RATE_KBPS = 3.5 
    TIMER_INTERVAL_MS = 50
    SEND_PROGRESS_MAX_PCT = 100.0
    WAIT_PROGRESS_MAX_BEFORE_ACK = 100.0
    WAIT_PROGRESS_EASE_TAU_SEC = 15.0
    PROGRESS_MAX_RATE_PCT_PER_SEC = 12.0
    PROGRESS_MIN_STEP_PCT = 0.01
    PROGRESS_SMOOTHING_FACTOR = 0.35
    SEND_START_THRESHOLD_BYTES_MIN = 1024
    SEND_START_THRESHOLD_FRACTION = 0.05
    
    # TIMEOUTS
    CONNECT_TOTAL_TIMEOUT_MS = 30000
    CONNECT_RETRY_EVERY_MS = 250
    WAIT_ACK_TIMEOUT_MS = 120000
    SEND_STALL_TIMEOUT_MS = 10000
    CLOSE_GRACE_DELAY_MS = 650
    CHUNK_SIZE = 1024
    
    # PROBING
    CONNECTION_CHECK_INTERVAL_MS = 3000
    CONNECTION_CHECK_TIMEOUT_MS = 1000
    CONNECTION_POLL_INTERVAL_MS = 100
    PING_TIMEOUT_MS = 600
    STATS_UPDATE_INTERVAL_MS = 400
    FILE_CACHE_DURATION_MS = 2000
}

# Constants
$LAIN_PORT = $cfg.LAIN_PORT
$SNA_48K_SIZE  = $cfg.SNA_48K_SIZE
$SNA_128K_SIZE = $cfg.SNA_128K_SIZE
$CHUNK_SIZE = $cfg.CHUNK_SIZE
$MAX_BYTES_PER_TICK = [int][Math]::Max(128, [Math]::Floor($cfg.DESIRED_SEND_RATE_KBPS * 1024 * ($cfg.TIMER_INTERVAL_MS / 1000.0)))

# --- UTILS ---
function Is-NonEmpty([string]$s) { return -not [string]::IsNullOrWhiteSpace($s) }
function Test-Ip([string]$ip) { [System.Net.IPAddress]$addr=$null; return [System.Net.IPAddress]::TryParse($ip, [ref]$addr) }
function Is-SnaExtension([string]$path) { if (-not (Is-NonEmpty $path)) { return $false }; return ([System.IO.Path]::GetExtension($path) -ieq ".sna") }
function Safe-TestPath([string]$path) { if (-not (Is-NonEmpty $path)) { return $false }; return (Test-Path -LiteralPath $path) }
function Safe-FileLength([string]$path) { if (-not (Safe-TestPath $path)) { return $null }; try { return (Get-Item -LiteralPath $path).Length } catch { return $null } }

function Get-SnaKindBySize([string]$path) {
    $len = Safe-FileLength $path
    if ($null -eq $len) { return $null }
    switch ($len) {
        $SNA_48K_SIZE  { return "48K" }
        $SNA_128K_SIZE { return "128K" }
        default        { return $null }
    }
}

function Normalize-SnaName([string]$path) {
    $leaf = [System.IO.Path]::GetFileName($path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if ([string]::IsNullOrWhiteSpace($base)) { $base = "LAIN" }
    $base = $base.ToUpperInvariant()
    $base = ($base -replace "[^A-Z0-9_]", "_")
    if ($base.Length -gt 8) { $base = $base.Substring(0, 8) }
    return ("{0}.SNA" -f $base)
}

function Get-Crc16Ccitt([string]$path) {
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $crc = 0xFFFF; $buf = New-Object byte[] 8192
        while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            for ($i = 0; $i -lt $read; $i++) {
                $crc = $crc -bxor (([int]$buf[$i]) -shl 8)
                for ($bit = 0; $bit -lt 8; $bit++) {
                    if (($crc -band 0x8000) -ne 0) { $crc = ($crc -shl 1) -bxor 0x1021 } else { $crc = ($crc -shl 1) }
                    $crc = $crc -band 0xFFFF
                }
            }
        }
        return [UInt16]$crc
    } finally { if ($fs) { $fs.Close(); $fs.Dispose() } }
}

function Is-ValidSnaFile([string]$path) { return (Safe-TestPath $path) -and (Is-SnaExtension $path) -and ($null -ne (Get-SnaKindBySize $path)) }

# --- CONFIG PERSISTENCE (MODIFICADO: AppData\Local\SnapZX) ---
function Get-ConfigPath { 
    $appData = [System.Environment]::GetFolderPath('LocalApplicationData')
    $configDir = Join-Path $appData "SnapZX"
    if (-not (Test-Path $configDir)) { 
        try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null } catch {}
    }
    return Join-Path $configDir "config.json" 
}

function Load-Config {
    $cfgPath = Get-ConfigPath
    if (Test-Path $cfgPath) {
        try {
            $json = Get-Content $cfgPath -Raw | ConvertFrom-Json
            if ($json.Ip) { $txtIp.Text = $json.Ip }
            if ($json.LastPath -and (Test-Path $json.LastPath)) { $openDlg.InitialDirectory = [System.IO.Path]::GetDirectoryName($json.LastPath) }
        } catch {}
    }
}
function Save-Config { $data = @{ Ip = $txtIp.Text; LastPath = $txtFile.Text }; $data | ConvertTo-Json | Set-Content (Get-ConfigPath) }

# --- RESOURCES (MODIFICADO PARA EXE STANDALONE) ---
function Get-AppIcon {
    # Solo miramos la variable interna, ignoramos el disco
    if (-not [string]::IsNullOrEmpty($script:B64_ICON)) {
        try {
            $bytes = [Convert]::FromBase64String($script:B64_ICON)
            $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
            # Truco para convertir PNG (base64) a Icono en memoria
            $bmp = [System.Drawing.Bitmap]::FromStream($ms)
            return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
        } catch {}
    }
    return $null
}

function Get-LogoImage {
    # Solo miramos la variable interna, ignoramos el disco
    if (-not [string]::IsNullOrEmpty($script:B64_LOGO)) {
        try {
            $bytes = [Convert]::FromBase64String($script:B64_LOGO)
            $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
            return [System.Drawing.Image]::FromStream($ms)
        } catch {}
    }
    return $null
}

$global:AppIcon = Get-AppIcon
$global:LogoImage = Get-LogoImage

function Refresh-SelectedFileCache {
    $path = $txtFile.Text
    if ([string]::IsNullOrWhiteSpace($path)) { $state.CachedFilePath = ""; $state.CachedFileOk = $false; $state.CachedSnaName = ""; return }
    $nowTicks = [DateTime]::UtcNow.Ticks
    if ($state.CachedFilePath -eq $path -and $state.CachedFileOk -ne $null -and ($nowTicks - $state.FileCacheLastCheckTicks) -lt ($cfg.FILE_CACHE_DURATION_MS * 10000)) { return }
    $state.CachedFilePath = $path; $state.CachedFileOk = $false; $state.CachedSnaName = ""; $state.FileCacheLastCheckTicks = $nowTicks
    try {
        $fi = New-Object System.IO.FileInfo($path)
        if (-not $fi.Exists -or -not ($fi.Extension -ieq ".sna")) { return }
        $len = $fi.Length
        if ($len -eq $SNA_48K_SIZE) { $state.CachedKind = "48K" } elseif ($len -eq $SNA_128K_SIZE) { $state.CachedKind = "128K" } else { $state.CachedKind = $null; return }
        $state.CachedSnaName = Normalize-SnaName $path; $state.CachedFileOk = $true
    } catch { $state.CachedFileOk = $false }
}

function New-CircleBitmap([System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 14,14
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush $color
    $g.FillEllipse($brush, 1,1,11,11)
    $g.Dispose(); $brush.Dispose()
    return $bmp
}

# --- NETWORK LOGIC (UNTOUCHED STABLE v2.6) ---
function Test-LainAppHandshake {
    param([string]$Ip, [int]$Port = $LAIN_PORT, [string]$ProbeName = "PING", [int]$TimeoutMs = 800)
    $oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Stop'
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($Ip, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($iar) | Out-Null; $client.NoDelay = $true
        $ns = $client.GetStream(); $ns.ReadTimeout = $TimeoutMs; $ns.WriteTimeout = $TimeoutMs
        $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($ProbeName)
        if ($nameBytes.Length -gt 255) { $nameBytes = $nameBytes[0..254] }
        $nlen = [int]$nameBytes.Length
        $hdr = New-Object byte[] (13 + $nlen)
        $hdr[0]=0x4C; $hdr[1]=0x41; $hdr[2]=0x49; $hdr[3]=0x4E; $hdr[10]=0x46; $hdr[11]=0x4E; $hdr[12]=[byte]$nlen
        if ($nlen -gt 0) { [Array]::Copy($nameBytes, 0, $hdr, 13, $nlen) }
        $ns.Write($hdr, 0, $hdr.Length); $ns.Flush()
        $buf = New-Object byte[] 64; $t0 = [Environment]::TickCount
        $acc = ""
        while ([Environment]::TickCount - $t0 -lt $TimeoutMs) {
            if (-not $ns.DataAvailable) { Start-Sleep -Milliseconds 30; continue }
            $r = $ns.Read($buf, 0, $buf.Length)
            if ($r -le 0) { break }
            for ($i = 0; $i -lt $r; $i++) { if ($buf[$i] -eq 0x06) { return $true } }
            if ($r -lt 10) { try { $acc += [System.Text.Encoding]::ASCII.GetString($buf, 0, $r) } catch {}; if ($acc.Contains("OK`r`n") -or $acc.Contains("ACK")) { return $true } }
        }
        return $false
    } catch { return $false } finally { try { if ($client) { $client.Close(); $client.Dispose() } } catch {} }
    $ErrorActionPreference = $oldEap
}

function Apply-ButtonStyle {
    param($btn, $color)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0; $btn.BackColor = $color; $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9); $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
}

# --- ABOUT BOX ---
function Show-AboutBox {
    $ab = New-Object System.Windows.Forms.Form
    $ab.Text = "About SnapZX"
    if ($global:AppIcon) { $ab.Icon = $global:AppIcon }
    $ab.Size = New-Object System.Drawing.Size(420, 270)
    $ab.StartPosition = "CenterParent"
    $ab.FormBorderStyle = "FixedDialog"
    $ab.MaximizeBox = $false; $ab.MinimizeBox = $false
    $ab.BackColor = [System.Drawing.Color]::WhiteSmoke
    
    $abHeader = New-Object System.Windows.Forms.Panel
    $abHeader.Height = 65
    $abHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $abHeader.BackColor = [System.Drawing.Color]::Black
    
    $pbAbLogo = New-Object System.Windows.Forms.PictureBox
    $pbAbLogo.Location = New-Object System.Drawing.Point(0, 0)
    $pbAbLogo.Size = New-Object System.Drawing.Size(200, 65)
    $pbAbLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $pbAbLogo.BackColor = [System.Drawing.Color]::Transparent
    if ($global:LogoImage) { $pbAbLogo.Image = $global:LogoImage }
    $abHeader.Controls.Add($pbAbLogo)

    $abHeader.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $wPanel = $abHeader.Width; $hPanel = $abHeader.Height
        
        if (-not $global:LogoImage) {
            $fontTitle = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
            $g.DrawString("SnapZX", $fontTitle, [System.Drawing.Brushes]::White, 15, 10)
            $fontTitle.Dispose()
        }
        
        $stripeW = 10; $startX = $wPanel - ($stripeW*4) - 20; $slant = 12
        $colors = @([System.Drawing.Color]::FromArgb(216,0,0), [System.Drawing.Color]::FromArgb(255,216,0), [System.Drawing.Color]::FromArgb(0,192,0), [System.Drawing.Color]::FromArgb(0,192,222))
        for ($i = 0; $i -lt 4; $i++) {
            $brush = New-Object System.Drawing.SolidBrush $colors[$i]
            $x = $startX + ($i * $stripeW)
            $pts = [System.Drawing.Point[]]@(
                (New-Object System.Drawing.Point -Arg ($x-$slant), ($hPanel)),
                (New-Object System.Drawing.Point -Arg ($x+$stripeW-$slant), ($hPanel)),
                (New-Object System.Drawing.Point -Arg ($x+$stripeW), 0),
                (New-Object System.Drawing.Point -Arg $x, 0)
            )
            $g.FillPolygon($brush, $pts); $brush.Dispose()
        }
    })
    $ab.Controls.Add($abHeader)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "A SNA files uploader for ZX Spectrum`nusing ESP-12 via AY-3-8912"
    $lblDesc.AutoSize = $true; $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDesc.Location = New-Object System.Drawing.Point(20, 80)
    $ab.Controls.Add($lblDesc)
    
    $lblLain = New-Object System.Windows.Forms.Label
    $lblLain.Text = "Based on code from LAIN by Alex Nihirash:"
    $lblLain.AutoSize = $true; $lblLain.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblLain.Location = New-Object System.Drawing.Point(20, 120)
    $ab.Controls.Add($lblLain)
    
    $lnkLain = New-Object System.Windows.Forms.LinkLabel
    $lnkLain.Text = "https://github.com/nihirash/Lain"
    $lnkLain.AutoSize = $true; $lnkLain.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lnkLain.Location = New-Object System.Drawing.Point(20, 138)
    $lnkLain.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
    $lnkLain.Add_LinkClicked({ try { [System.Diagnostics.Process]::Start("https://github.com/nihirash/Lain") } catch {} })
    $ab.Controls.Add($lnkLain)
    
    $lblMe = New-Object System.Windows.Forms.Label
    $lblMe.Text = "(c) M. Ignacio Monge García / Github repository:"
    $lblMe.AutoSize = $true; $lblMe.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblMe.Location = New-Object System.Drawing.Point(20, 165)
    $ab.Controls.Add($lblMe)
    
    $lnkMe = New-Object System.Windows.Forms.LinkLabel
    $lnkMe.Text = "https://github.com/IgnacioMonge/SnapZX"
    $lnkMe.AutoSize = $true; $lnkMe.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lnkMe.Location = New-Object System.Drawing.Point(20, 183)
    $lnkMe.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
    $lnkMe.Add_LinkClicked({ try { [System.Diagnostics.Process]::Start("https://github.com/IgnacioMonge/SnapZX") } catch {} })
    $ab.Controls.Add($lnkMe)
    
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Size = New-Object System.Drawing.Size(80, 28)
    $btnClose.Location = New-Object System.Drawing.Point(310, 195)
    Apply-ButtonStyle $btnClose ([System.Drawing.Color]::Gray)
    $btnClose.Add_Click({ $ab.Close() })
    $ab.Controls.Add($btnClose)
    
    $ab.ShowDialog($form) | Out-Null
}

# ---------------- UI CONSTRUCTION ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "SnapZX"
if ($global:AppIcon) { $form.Icon = $global:AppIcon }
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.ClientSize = New-Object System.Drawing.Size(600, 325) 
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# --- Header (BLACK) ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Height = 65 
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.BackColor = [System.Drawing.Color]::Black

# --- Logo PictureBox (Clickable) ---
$pbLogo = New-Object System.Windows.Forms.PictureBox
$pbLogo.Location = New-Object System.Drawing.Point(0, 0)
$pbLogo.Size = New-Object System.Drawing.Size(200, 65)
$pbLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$pbLogo.BackColor = [System.Drawing.Color]::Transparent
$pbLogo.Cursor = [System.Windows.Forms.Cursors]::Hand
$pbLogo.Add_Click({ Show-AboutBox })
if ($global:LogoImage) { $pbLogo.Image = $global:LogoImage }
$pnlHeader.Controls.Add($pbLogo)

$pnlHeader.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $wPanel = $pnlHeader.Width
    $hPanel = $pnlHeader.Height
    
    if (-not $global:LogoImage) {
        $fontTitle = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
        $g.DrawString("SnapZX", $fontTitle, [System.Drawing.Brushes]::White, 15, 10)
        $fontTitle.Dispose()
    }
    
    $stripeW = 15; $totalBadgeW = ($stripeW*4)+20; $startX = $wPanel-$totalBadgeW-10; $slant = 15
    $colors = @([System.Drawing.Color]::FromArgb(216,0,0), [System.Drawing.Color]::FromArgb(255,216,0), [System.Drawing.Color]::FromArgb(0,192,0), [System.Drawing.Color]::FromArgb(0,192,222))
    
    for ($i = 0; $i -lt 4; $i++) {
        $brush = New-Object System.Drawing.SolidBrush $colors[$i]
        $x = $startX + ($i * $stripeW)
        $pts = [System.Drawing.Point[]]@(
            (New-Object System.Drawing.Point -Arg ($x-$slant), ($hPanel)),
            (New-Object System.Drawing.Point -Arg ($x+$stripeW-$slant), ($hPanel)),
            (New-Object System.Drawing.Point -Arg ($x+$stripeW), 0),
            (New-Object System.Drawing.Point -Arg $x, 0)
        )
        $g.FillPolygon($brush, $pts); $brush.Dispose()
    }
    
    $fontSub = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $subText = "SNA files uploader"
    $subSize = $g.MeasureString($subText, $fontSub)
    $subX = $startX - $subSize.Width - 15
    $subY = $hPanel - $subSize.Height - 6
    $g.DrawString($subText, $fontSub, [System.Drawing.Brushes]::Yellow, $subX, $subY)
    $fontSub.Dispose()
})

# --- Connection Area ---
$grpConn = New-Object System.Windows.Forms.GroupBox
$grpConn.Text = "Spectrum Connection"
$grpConn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$grpConn.Location = New-Object System.Drawing.Point(20, 80)
$grpConn.Size = New-Object System.Drawing.Size(560, 65)

$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = "IP Address:"
$lblIp.Location = New-Object System.Drawing.Point(20, 30)
$lblIp.AutoSize = $true; $lblIp.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Location = New-Object System.Drawing.Point(100, 27)
$txtIp.Size = New-Object System.Drawing.Size(180, 23)
$txtIp.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtIp.Text = "192.168.0.205"

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = ": 6144"
$lblPort.Location = New-Object System.Drawing.Point(285, 30)
$lblPort.AutoSize = $true; $lblPort.ForeColor = [System.Drawing.Color]::Gray

$lblConnStatus = New-Object System.Windows.Forms.Label
$lblConnStatus.Text = ""
$lblConnStatus.AutoSize = $false
$lblConnStatus.Location = New-Object System.Drawing.Point(340, 27)
$lblConnStatus.Size = New-Object System.Drawing.Size(170, 20)
$lblConnStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblConnStatus.ForeColor = [System.Drawing.Color]::DarkGray
$lblConnStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$picConn = New-Object System.Windows.Forms.PictureBox
$picConn.Location = New-Object System.Drawing.Point(520, 27)
$picConn.Size = New-Object System.Drawing.Size(16, 16)
$picConn.Cursor = [System.Windows.Forms.Cursors]::Hand
$bmpGray = New-CircleBitmap ([System.Drawing.Color]::LightGray)
$bmpGreen = New-CircleBitmap ([System.Drawing.Color]::LimeGreen)
$bmpYellow = New-CircleBitmap ([System.Drawing.Color]::Gold)
$bmpBlue = New-CircleBitmap ([System.Drawing.Color]::DeepSkyBlue)
$bmpRed  = New-CircleBitmap ([System.Drawing.Color]::Crimson)
$picConn.Image = $bmpGray

$grpConn.Controls.AddRange(@($lblIp, $txtIp, $lblPort, $lblConnStatus, $picConn))

# --- File Area ---
$grpFile = New-Object System.Windows.Forms.GroupBox
$grpFile.Text = "Snapshot File (.sna)"
$grpFile.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$grpFile.Location = New-Object System.Drawing.Point(20, 155)
$grpFile.Size = New-Object System.Drawing.Size(560, 70)

$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Location = New-Object System.Drawing.Point(20, 30)
$txtFile.Size = New-Object System.Drawing.Size(430, 23)
$txtFile.ReadOnly = $true; $txtFile.BackColor = [System.Drawing.Color]::White
$txtFile.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtFile.Text = "Drag & Drop .SNA file here..."

$btnSelect = New-Object System.Windows.Forms.Button
$btnSelect.Text = "Browse..."
$btnSelect.Location = New-Object System.Drawing.Point(460, 29)
$btnSelect.Size = New-Object System.Drawing.Size(80, 25)
Apply-ButtonStyle $btnSelect ([System.Drawing.Color]::SlateGray)

$grpFile.Controls.AddRange(@($txtFile, $btnSelect))

# --- Actions Area ---
$pnlActions = New-Object System.Windows.Forms.Panel
$pnlActions.Location = New-Object System.Drawing.Point(20, 240)
$pnlActions.Size = New-Object System.Drawing.Size(560, 40)

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = "Send"
$btnSend.Location = New-Object System.Drawing.Point(480, 7)
$btnSend.Size = New-Object System.Drawing.Size(80, 25)
Apply-ButtonStyle $btnSend ([System.Drawing.Color]::SeaGreen)
$btnSend.Enabled = $false

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(390, 7)
$btnCancel.Size = New-Object System.Drawing.Size(80, 25)
Apply-ButtonStyle $btnCancel ([System.Drawing.Color]::LightGray)
$btnCancel.ForeColor = [System.Drawing.Color]::Black
$btnCancel.Enabled = $false

$pnlActions.Controls.AddRange(@($btnSend, $btnCancel))

# --- Progress & Status ---
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Dock = [System.Windows.Forms.DockStyle]::Bottom
$progress.Height = 10; $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous

$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlStatus.Height = 25; $pnlStatus.BackColor = [System.Drawing.Color]::WhiteSmoke

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready."
$lblStatus.AutoSize = $false; $lblStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$pnlStatus.Controls.Add($lblStatus)

$form.Controls.AddRange(@($pnlHeader, $grpConn, $grpFile, $pnlActions, $progress, $pnlStatus))

# --- Tooltips & Dialogs ---
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($picConn, "Click to test connection")
$openDlg = New-Object System.Windows.Forms.OpenFileDialog
$openDlg.Filter = "SNA snapshots (*.sna)|*.sna|All files (*.*)|*.*"

# ---------------- STATE MACHINE & LOGIC ----------------
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = $cfg.TIMER_INTERVAL_MS
$connectionTimer = New-Object System.Windows.Forms.Timer; $connectionTimer.Interval = $cfg.CONNECTION_POLL_INTERVAL_MS
$script:TransferBlinkTimer = New-Object System.Windows.Forms.Timer; $script:TransferBlinkTimer.Interval = 350
$script:TransferBlinkVisible = $true

$state = [pscustomobject]@{
    Phase = "Idle"; Ip = $null; Path = $null; SnaName = ""; Kind = $null;
    Bytes = $null; HeaderBytes = $null; HeaderSent = 0; FileStream = $null;
    SendBuf = $null; SendBufOffset = 0; SendBufCount = 0; SendBufIsHeader = $false;
    Total = 0; HeaderLen = 0; PayloadLen = 0; Sent = 0;
    Client = $null; Sock = $null; ConnectAR = $null;
    ConnectStartUtc = [DateTime]::MinValue; NextRetryUtc = [DateTime]::MinValue; WaitStartUtc = [DateTime]::MinValue;
    TransferStartUtc = [DateTime]::MinValue; LastSendProgressUtc = [DateTime]::MinValue; LastStatsUpdate = [DateTime]::UtcNow;
    ProgressStarted = $false; UiProgress = 0.0; TargetProgress = 0.0; LastTickUtc = [DateTime]::UtcNow;
    CloseObservedUtc = [DateTime]::MinValue; AckReceived = $false; AckBuffer = ""; Cancelled = $false;
    IsCheckingConnection = $false; TransferActive = $false; IpAlive = $false; PortStatus = "Unknown"; AppStatus = "Unknown";
    AutoProbeSuspended = $false; LastAutoProbeIp = ""; LastHandshakeUtc = [DateTime]::MinValue; LastPortProbeUtc = [DateTime]::MinValue; LastConnectionCheckUtc = [DateTime]::MinValue;
    CachedFilePath = ""; CachedFileOk = $null; CachedKind = $null; CachedSnaName = ""; FileCacheLastCheckTicks = 0;
    ConnCheckPhase = "Idle"; ConnCheckIp = $null; ConnCheckForceProbe = $false; ConnCheckSkipHandshake = $false;
    LastOpenVerifyUtc = [DateTime]::MinValue; ConnCheckStartUtc = [DateTime]::MinValue; NextAutoConnCheckUtc = [DateTime]::MinValue;
    PingTask = $null; ProbeClient = $null; ProbeTask = $null; ProbeAR = $null; ProbeStartUtc = [DateTime]::MinValue;
    ConnFailCount = 0; ConnFailThreshold = $cfg.CONN_FAIL_THRESHOLD; ConnGraceMs = $cfg.CONN_GRACE_MS; LastConnectedUtc = [DateTime]::MinValue
}

$script:StateLock = New-Object object
function Invoke-WithStateLock { param([scriptblock]$Action); [System.Threading.Monitor]::Enter($script:StateLock); try { & $Action } finally { [System.Threading.Monitor]::Exit($script:StateLock) } }

# --- LOGIC FUNCTIONS (UNTOUCHED) ---
function Start-ConnectionCheck([string]$ip, [bool]$forcePortProbe = $false, [bool]$skipHandshake = $false) {
    if ($state.Phase -ne "Idle" -or $state.TransferActive) { return }
    $now = [DateTime]::UtcNow
    if (-not $forcePortProbe -and $state.ConnCheckPhase -eq "Idle" -and $state.LastConnectionCheckUtc -ne [DateTime]::MinValue -and ($now - $state.LastConnectionCheckUtc).TotalMilliseconds -lt 250) { return }
    if ($state.ConnCheckPhase -ne "Idle") { $state.ConnCheckForceProbe = ($state.ConnCheckForceProbe -or $forcePortProbe); return }

    if (-not (Test-Ip $ip)) { Apply-ConnIndicatorStable "Gray" "Invalid IP"; $state.IpAlive = $false; $state.PortStatus = "Unknown"; Update-Buttons-State; return }

    $state.IsCheckingConnection = $true; $state.ConnCheckIp = $ip; $state.ConnCheckForceProbe = $forcePortProbe; $state.ConnCheckSkipHandshake = $skipHandshake
    $state.ConnCheckPhase = "Pinging"; $state.ConnCheckStartUtc = $now; $state.LastConnectionCheckUtc = $now; $state.PingTask = $null; $state.IpAlive = $true
    if ($connectionTimer.Interval -ne $cfg.CONNECTION_POLL_INTERVAL_MS) { $connectionTimer.Interval = $cfg.CONNECTION_POLL_INTERVAL_MS }
}

function End-ConnectionCheck {
    $state.ConnCheckPhase = "Idle"; $state.ConnCheckForceProbe = $false; $state.ConnCheckSkipHandshake = $false; $state.ConnCheckIp = $null
    $state.IsCheckingConnection = $false; $state.PingTask = $null; $state.ProbeTask = $null
    try { if ($state.ProbeClient) { $state.ProbeClient.Close() } } catch {}; $state.ProbeClient = $null
    $state.AutoProbeSuspended = ($state.PortStatus -eq "Open" -and $state.AppStatus -eq "Ready")
    $nextMs = if ($state.PortStatus -ne "Open") { 500 } elseif ($state.AppStatus -ne "Ready") { 1200 } else { 3500 }
    if ($connectionTimer.Interval -ne [int]$nextMs) { $connectionTimer.Interval = [int]$nextMs }
    $state.NextAutoConnCheckUtc = [DateTime]::UtcNow.AddMilliseconds([int]$nextMs)
    Update-Buttons-State
}

function Process-ConnectionCheckState {
    if ($state.Phase -ne "Idle" -or $state.TransferActive) { return }
    $now = [DateTime]::UtcNow
    switch ($state.ConnCheckPhase) {
        "Idle" {
            if ($now -lt $state.NextAutoConnCheckUtc) { return }
            $ip = $txtIp.Text.Trim()
            if ($ip -ne $state.LastAutoProbeIp) { $state.LastAutoProbeIp = $ip; $state.AutoProbeSuspended = $false; Start-ConnectionCheck -ip $ip -forcePortProbe:$true; return }
            if ($state.AutoProbeSuspended -and $state.PortStatus -eq "Open") {
                if ($state.LastOpenVerifyUtc -eq [DateTime]::MinValue -or (($now - $state.LastOpenVerifyUtc).TotalMilliseconds -ge 3500)) {
                    $state.LastOpenVerifyUtc = $now; Start-ConnectionCheck -ip $ip -forcePortProbe:$true -skipHandshake:$false; return
                }
                $state.NextAutoConnCheckUtc = $now.AddMilliseconds(3500); return
            }
            Start-ConnectionCheck -ip $ip -forcePortProbe:$false
            return
        }
        "Pinging" {
            $state.PingTask = $null; $state.IpAlive = $true # Skip ICMP
            $needProbe = $state.ConnCheckForceProbe -or $state.PortStatus -eq "Unknown" -or (($now - $state.LastPortProbeUtc).TotalMilliseconds -ge 1500)
            if (-not $needProbe) { End-ConnectionCheck; return }
            $state.LastPortProbeUtc = $now
            try {
                $state.ProbeClient = New-Object System.Net.Sockets.TcpClient
                $state.ProbeAR = $state.ProbeClient.BeginConnect($state.ConnCheckIp, $LAIN_PORT, $null, $null)
                $state.ProbeStartUtc = $now; $state.ConnCheckPhase = "Probing"
            } catch { $state.PortStatus = "Closed"; $state.AppStatus = "Unknown"; Apply-ConnIndicatorStable "Yellow" "Port closed"; End-ConnectionCheck }
            return
        }
        "Probing" {
            if ($state.ProbeAR) {
                if ($state.ProbeAR.IsCompleted) {
                    $ok = $false; try { $state.ProbeClient.EndConnect($state.ProbeAR); $ok = $true } catch {}
                    $state.PortStatus = if ($ok) { "Open" } else { "Closed" }
                    if ($state.PortStatus -eq "Open") {
                        $hsOk = $false; try { $hsOk = Test-LainAppHandshake -Ip $state.ConnCheckIp -Port $LAIN_PORT } catch {}
                        $state.AppStatus = if ($hsOk) { "Ready" } else { "NotRunning" }
                        $state.LastHandshakeUtc = $now
                    } else { $state.AppStatus = "Unknown" }
                    
                    if ($state.PortStatus -eq "Open") {
                        # CAMBIO: TEXTO MODIFICADO
                        if ($state.AppStatus -eq "NotRunning") { Apply-ConnIndicatorStable "Blue" "Port open but not reachable" } 
                        else { Apply-ConnIndicatorStable "Green" "Ready" }
                    } else { Apply-ConnIndicatorStable "Yellow" "Port unreachable" }
                    $state.ProbeAR = $null; End-ConnectionCheck; return
                }
                if ([int](($now - $state.ProbeStartUtc).TotalMilliseconds) -gt $cfg.CONNECTION_CHECK_TIMEOUT_MS) {
                     $state.PortStatus = "Closed"; $state.AppStatus = "Unknown"; Apply-ConnIndicatorStable "Yellow" "SnapZX server not reachable"; $state.ProbeAR = $null; End-ConnectionCheck; return
                }
            }
            return
        }
    }
}

function Invoke-PortProbe {
    if ($state.Phase -ne "Idle") { return }
    $ip = $txtIp.Text.Trim()
    if (-not (Test-Ip $ip)) { Apply-ConnIndicatorStable "Gray" "Invalid IP"; return }
    Apply-ConnIndicatorStable "Blue" "Probing..."
    $state.AutoProbeSuspended = $false; $state.LastAutoProbeIp = $ip
    Start-ConnectionCheck -ip $ip -forcePortProbe:$true
    Process-ConnectionCheckState
}

function Apply-ConnIndicatorStable($Level, $TipText) {
    if ($script:form -and $script:form.InvokeRequired) { $null = $script:form.BeginInvoke([Action]{ Apply-ConnIndicatorStable $Level $TipText }); return }
    
    $lblConnStatus.Text = $TipText

    $now = [DateTime]::UtcNow
    if ($Level -eq "Blue") { $picConn.Image = $bmpBlue; $toolTip.SetToolTip($picConn, $TipText); return }
    
    if ($Level -eq "Green") { 
        $state.ConnFailCount = 0; $state.LastConnectedUtc = $now; $picConn.Image = $bmpGreen; $toolTip.SetToolTip($picConn, $TipText); return 
    }
    
    # CAMBIO: SOPORTE PARA ROJO
    if ($Level -eq "Red") {
        $picConn.Image = $bmpRed; $toolTip.SetToolTip($picConn, $TipText); return
    }
    
    if ($state.LastConnectedUtc -ne [DateTime]::MinValue -and ($now - $state.LastConnectedUtc).TotalMilliseconds -lt $state.ConnGraceMs) {
        $picConn.Image = $bmpGreen; return
    }
    $state.ConnFailCount++
    if ($state.ConnFailCount -lt $state.ConnFailThreshold -and $state.LastConnectedUtc -ne [DateTime]::MinValue) { return }

    if ($Level -eq "Yellow") { $picConn.Image = $bmpYellow } else { $picConn.Image = $bmpGray }
    $toolTip.SetToolTip($picConn, $TipText)
}

function Update-Buttons-State {
    if ($script:form -and $script:form.InvokeRequired) { $null = $script:form.BeginInvoke([Action]{ Update-Buttons-State }); return }

    if ($state.CachedKind) {
        $grpFile.Text = "Snapshot File (.sna) - Detected: " + $state.CachedKind
    } else {
        $grpFile.Text = "Snapshot File (.sna)"
    }

    if ($state.Phase -ne "Idle") {
        $btnSelect.Enabled = $false; $btnSend.Enabled = $false; $btnCancel.Enabled = $true; $txtIp.Enabled = $false
        $btnSend.BackColor = [System.Drawing.Color]::Silver
        $btnCancel.BackColor = [System.Drawing.Color]::IndianRed
        $btnCancel.ForeColor = [System.Drawing.Color]::White
        return
    }
    
    $btnSelect.Enabled = $true; $btnCancel.Enabled = $false; $txtIp.Enabled = $true
    $btnCancel.BackColor = [System.Drawing.Color]::LightGray
    $btnCancel.ForeColor = [System.Drawing.Color]::Black
    
    Refresh-SelectedFileCache
    $ipOk = Test-Ip ($txtIp.Text.Trim())
    $fileOk = ($state.CachedFileOk -eq $true)

    if ($fileOk -and $ipOk -and $state.PortStatus -eq "Open" -and $state.AppStatus -eq "Ready") {
        $btnSend.Enabled = $true; $btnSend.BackColor = [System.Drawing.Color]::SeaGreen
        $lblStatus.Text = "Ready to send."
    } else {
        $btnSend.Enabled = $false; $btnSend.BackColor = [System.Drawing.Color]::Silver
        if (-not $ipOk) { $lblStatus.Text = "Invalid IP address." }
        elseif ($state.PortStatus -ne "Open") { $lblStatus.Text = "Spectrum not reachable." }
        elseif ($state.AppStatus -ne "Ready") { $lblStatus.Text = "Waiting for SnapZX server." }
        elseif (-not $fileOk) { $lblStatus.Text = "Select a .SNA file." }
    }
}

function Set-AppState($NewPhase) {
    if ($script:form -and $script:form.InvokeRequired) { $null = $script:form.BeginInvoke([Action]{ Set-AppState $NewPhase }); return }
    $state.Phase = $NewPhase
    
    if ($NewPhase -eq "WaitingAck") { $progress.Visible = $false } else { $progress.Visible = $true }

    if ($NewPhase -eq "Idle") {
        $state.TransferActive = $false
        $script:TransferBlinkTimer.Stop(); $picConn.Visible = $true
        $lblStatus.Text = "Ready."
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $progress.Value = 0
    } else {
        $script:TransferBlinkTimer.Start()
    }
    Update-Buttons-State
}

function Format-Bytes([long]$bytes) {
    if ($bytes -lt 1024) { return "$bytes B" } elseif ($bytes -lt 1048576) { return "{0:F1} KB" -f ($bytes / 1024) } else { return "{0:F1} MB" -f ($bytes / 1048576) }
}

function Update-Statistics {
    if ($state.Phase -ne "Sending") { return }
    $elapsed = [DateTime]::UtcNow - $state.TransferStartUtc
    if ($elapsed.TotalSeconds -le 0) { return }
    $speed = $state.Sent / $elapsed.TotalSeconds
    $pct = if ($state.Total -gt 0) { [math]::Round(($state.Sent / $state.Total) * 100, 0) } else { 0 }
    
    # CAMBIO: TEXTO (Sin parentesis)
    $lblStatus.Text = "Transferring $pct% ({0}/s)" -f (Format-Bytes $speed)
}

function Start-SendWorkflow {
    if ($state.Phase -ne "Idle") { return }
    $ip = $txtIp.Text.Trim(); $path = $txtFile.Text
    Refresh-SelectedFileCache
    
    if (-not (Test-LainAppHandshake -Ip $ip -Port $LAIN_PORT)) {
        [System.Windows.Forms.MessageBox]::Show("Spectrum connection failed. Ensure .snapzx is running.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    
    try {
        $connectionTimer.Stop()
        $fi = Get-Item $path; $plen = [int]$fi.Length; $snaName = $state.CachedSnaName
        $payloadCrc = Get-Crc16Ccitt -path $path
        
        $nBytes = [System.Text.Encoding]::ASCII.GetBytes($snaName)
        $nlen = $nBytes.Length
        $hdr = New-Object byte[] (13 + $nlen)
        $hdr[0]=0x4C; $hdr[1]=0x41; $hdr[2]=0x49; $hdr[3]=0x4E
        [Array]::Copy([System.BitConverter]::GetBytes([UInt32]$plen), 0, $hdr, 4, 4)
        [Array]::Copy([System.BitConverter]::GetBytes([UInt16]$payloadCrc), 0, $hdr, 8, 2)
        $hdr[10]=0x46; $hdr[11]=0x4E; $hdr[12]=[byte]$nlen
        if ($nlen -gt 0) { [Array]::Copy($nBytes, 0, $hdr, 13, $nlen) }

        $state.Ip = $ip; $state.Path = $path; $state.Kind = $state.CachedKind
        $state.HeaderBytes = $hdr; $state.HeaderSent = 0
        $state.FileStream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $state.SendBuf = New-Object byte[] $CHUNK_SIZE; $state.SendBufOffset=0; $state.SendBufCount=0; $state.SendBufIsHeader=$false
        $state.Total = ($hdr.Length + $plen); $state.HeaderLen = $hdr.Length; $state.PayloadLen = $plen; $state.Sent = 0
        $state.ConnectStartUtc = [DateTime]::UtcNow; $state.TransferStartUtc = [DateTime]::UtcNow
        $state.NextRetryUtc = [DateTime]::UtcNow; $state.AckReceived = $false; $state.Cancelled = $false
        $state.TransferActive = $true

        Set-AppState "Connecting"; 
        $lblStatus.Text = "Connecting..."
        $lblConnStatus.Text = "Connecting..."
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        
        Start-ConnectAttempt
        $timer.Start()
    } catch {
        $connectionTimer.Start()
        [System.Windows.Forms.MessageBox]::Show("Could not read file.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Start-ConnectAttempt {
    try {
        if ($state.Sock) { $state.Sock.Close() }; if ($state.Client) { $state.Client.Close() }
        $state.Client = New-Object System.Net.Sockets.TcpClient
        $state.Client.SendBufferSize = $cfg.SOCKET_BUFFER_SIZE
        $state.Client.SendTimeout = 8000; $state.Client.ReceiveTimeout = 500
        $state.ConnectAR = $state.Client.BeginConnect($state.Ip, $LAIN_PORT, $null, $null)
    } catch {}
}

function Transfer-EngineTick {
    try {
        switch ($state.Phase) {
            "Connecting" {
                if ([int]([DateTime]::UtcNow - $state.ConnectStartUtc).TotalMilliseconds -gt $cfg.CONNECT_TOTAL_TIMEOUT_MS) { Finish-Send $true; return }
                if ($state.ConnectAR -and $state.ConnectAR.IsCompleted) {
                    try {
                        $state.Client.EndConnect($state.ConnectAR)
                        $state.Sock = $state.Client.Client; $state.Sock.NoDelay=$true; $state.Sock.Blocking=$false
                        $state.Sock.SendBufferSize = $cfg.SOCKET_BUFFER_SIZE
                        Set-AppState "Sending"; $state.ConnectAR = $null
                        # CAMBIO: Mensaje inicial
                        $lblStatus.Text = "Connected. Transferring..."
                        $lblConnStatus.Text = "Transferring"
                        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                    } catch { Start-ConnectAttempt; Start-Sleep -Milliseconds 250 }
                }
            }
            "Sending" {
                if ($state.Cancelled) { Finish-Send $false $true; return }
                if ($state.Sent -ge $state.Total) { 
                    Set-AppState "WaitingAck"
                    $state.WaitStartUtc=[DateTime]::UtcNow
                    $lblStatus.Text="Waiting ACK..."
                    $lblConnStatus.Text="Waiting ACK..."
                    return 
                }
                
                $budget = $MAX_BYTES_PER_TICK
                while ($budget -gt 0 -and $state.Sent -lt $state.Total) {
                    if ($state.SendBufCount -le 0) {
                        if ($state.HeaderSent -lt $state.HeaderLen) {
                             $fill = [Math]::Min($CHUNK_SIZE, ($state.HeaderLen - $state.HeaderSent))
                             [Array]::Copy($state.HeaderBytes, $state.HeaderSent, $state.SendBuf, 0, $fill)
                             $state.SendBufCount=$fill; $state.SendBufIsHeader=$true
                        } else {
                             $read = $state.FileStream.Read($state.SendBuf, 0, $CHUNK_SIZE)
                             if ($read -le 0) { break }
                             $state.SendBufCount=$read; $state.SendBufIsHeader=$false
                        }
                        $state.SendBufOffset = 0
                    }
                    $toSend = [Math]::Min($state.SendBufCount, $budget)
                    try {
                        if ($state.Sock.Poll(0, [System.Net.Sockets.SelectMode]::SelectWrite)) {
                            $n = $state.Sock.Send($state.SendBuf, $state.SendBufOffset, $toSend, [System.Net.Sockets.SocketFlags]::None)
                            $state.Sent+=$n; $budget-=$n; $state.SendBufOffset+=$n; $state.SendBufCount-=$n
                            if ($state.SendBufIsHeader) { $state.HeaderSent+=$n }
                        } else { break }
                    } catch { break }
                }
                
                $pct = if ($state.Total -gt 0) { [int](($state.Sent / $state.Total)*100) } else { 0 }
                if ($progress.Value -ne $pct) { $progress.Value = $pct }
                Update-Statistics
            }
            "WaitingAck" {
                if ([int]([DateTime]::UtcNow - $state.WaitStartUtc).TotalMilliseconds -gt $cfg.WAIT_ACK_TIMEOUT_MS) { Finish-Send $true; return }
                try {
                    if ($state.Sock.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead)) {
                        $buf = New-Object byte[] 256; $r = $state.Sock.Receive($buf, 0, 256, [System.Net.Sockets.SocketFlags]::None)
                        if ($r -gt 0) { 
                             $txt = [System.Text.Encoding]::ASCII.GetString($buf,0,$r)
                             if ($txt.Contains("OK") -or $txt.Contains("ACK") -or ($buf[0] -eq 6)) {
                                 $state.AckReceived = $true; Set-AppState "Finalizing"; $state.CloseObservedUtc = [DateTime]::UtcNow
                             }
                        } else { Set-AppState "Finalizing"; $state.CloseObservedUtc = [DateTime]::UtcNow }
                    }
                } catch { Set-AppState "Finalizing"; $state.CloseObservedUtc = [DateTime]::UtcNow }
            }
            "Finalizing" {
                 if ([int]([DateTime]::UtcNow - $state.CloseObservedUtc).TotalMilliseconds -gt 600) { Finish-Send $false; return }
            }
        }
    } catch { Finish-Send $false $true; [System.Windows.Forms.MessageBox]::Show("Transfer Error: " + $_.Exception.Message) }
}

function Finish-Send($timeout, $cancel=$false) {
    $timer.Stop(); try { if ($state.FileStream) { $state.FileStream.Close() } } catch {}; Cleanup-Connection
    Set-AppState "Idle"
    
    # CAMBIO: Logica de Cancelacion (ROJO)
    if ($cancel) {
        $msg = "Cancelled."
        Apply-ConnIndicatorStable "Red" "Transfer cancelled"
    } elseif ($timeout) {
        $msg = "Done (Timeout)."
    } else {
        $msg = "Transfer Complete!"
    }
    
    $lblStatus.Text = $msg
    $connectionTimer.Start()
}

function Cleanup-Connection { try { if ($state.Sock) { $state.Sock.Close() }; if ($state.Client) { $state.Client.Close() } } catch {} }

# --- EVENT WIRING ---
$timer.Add_Tick({ Transfer-EngineTick })
$connectionTimer.Add_Tick({ Invoke-WithStateLock { Process-ConnectionCheckState } })
$script:TransferBlinkTimer.Add_Tick({ if ($state.TransferActive) { $picConn.Visible = -not $picConn.Visible } else { $picConn.Visible = $true } })
$picConn.Add_Click({ Invoke-PortProbe })
$btnSelect.Add_Click({ if ($openDlg.ShowDialog() -eq "OK") { $txtFile.Text = $openDlg.FileName } })
$btnSend.Add_Click({ Start-SendWorkflow })
$btnCancel.Add_Click({ $state.Cancelled = $true })
$txtIp.Add_TextChanged({ End-ConnectionCheck; $state.IpAlive=$false; $state.PortStatus="Unknown"; Apply-ConnIndicatorStable "Gray" "Checking..."; Update-Buttons-State })
$txtFile.Add_TextChanged({ Refresh-SelectedFileCache; Update-Buttons-State })

# Drag & Drop
$form.AllowDrop = $true
$form.Add_DragEnter({ if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$form.Add_DragDrop({ $files = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop); if ($files.Count -eq 1) { $txtFile.Text = $files[0] } })

# Persistence
$form.Add_Shown({ Load-Config; Update-Buttons-State })
$form.Add_FormClosing({ Save-Config; $timer.Stop(); $connectionTimer.Stop(); Cleanup-Connection })

# --- START ---
Apply-ConnIndicatorStable "Gray" "Initializing..."
$pnlHeader.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $wPanel = $pnlHeader.Width
    $hPanel = $pnlHeader.Height
    
    # Fallback text if logo missing
    if (-not $global:LogoImage) {
        $fontTitle = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
        $g.DrawString("SnapZX", $fontTitle, [System.Drawing.Brushes]::White, 15, 10)
        $fontTitle.Dispose()
    }
    
    # Badge (Right)
    $stripeW = 15; $totalBadgeW = ($stripeW*4)+20; $startX = $wPanel-$totalBadgeW-10; $slant = 15
    $colors = @([System.Drawing.Color]::FromArgb(216,0,0), [System.Drawing.Color]::FromArgb(255,216,0), [System.Drawing.Color]::FromArgb(0,192,0), [System.Drawing.Color]::FromArgb(0,192,222))
    
    for ($i = 0; $i -lt 4; $i++) {
        $brush = New-Object System.Drawing.SolidBrush $colors[$i]
        $x = $startX + ($i * $stripeW)
        $pts = [System.Drawing.Point[]]@(
            (New-Object System.Drawing.Point -Arg ($x-$slant), ($hPanel)),
            (New-Object System.Drawing.Point -Arg ($x+$stripeW-$slant), ($hPanel)),
            (New-Object System.Drawing.Point -Arg ($x+$stripeW), 0),
            (New-Object System.Drawing.Point -Arg $x, 0)
        )
        $g.FillPolygon($brush, $pts); $brush.Dispose()
    }
    
    # Subtitle (Right of logo, left of badge)
    $fontSub = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $subText = "SNA files uploader"
    $subSize = $g.MeasureString($subText, $fontSub)
    $subX = $startX - $subSize.Width - 15
    # CAMBIO 1: Texto pegado al borde inferior
    $subY = $hPanel - $subSize.Height - 6
    $g.DrawString($subText, $fontSub, [System.Drawing.Brushes]::Yellow, $subX, $subY)
    $fontSub.Dispose()
})

$connectionTimer.Start()
Process-ConnectionCheckState
[void]$form.ShowDialog()