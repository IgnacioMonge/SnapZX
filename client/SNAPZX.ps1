
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


# Force cmdlet non-terminating errors to be catchable without scattering -ErrorAction Stop
$script:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Keep default behavior for non-cmdlet errors; critical sections can locally set ErrorActionPreference='Stop'
$ErrorActionPreference = 'Continue'

# SNAPZX SNA Uploader (ZX Spectrum) - version 1.1
# (C) M. Monge García 2025
# based on LAIN esxdos command from Nihirash (https://github.com/nihirash/Lain)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.NetworkInformation

# UTF-8 encoding for compatibility
try { 
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 
} catch {
    Write-Debug "Could not set UTF-8 encoding"
}

# Configuration constants
# Centralized configuration
$cfg = [pscustomobject]@{
    SOCKET_BUFFER_SIZE = 8192
    CONN_FAIL_THRESHOLD = 2
    CONN_GRACE_MS = 3000
    LAIN_PORT = 6144
    SNA_48K_SIZE = 49179
    SNA_128K_SIZE = 131103
    P_BASE_AFTER_SEND_START = 0
    SEND_PROGRESS_MAX_PCT = 100.0
    WAIT_PROGRESS_MAX_BEFORE_ACK = 100.0
    WAIT_PROGRESS_EASE_TAU_SEC = 15.0
    PROGRESS_MAX_RATE_PCT_PER_SEC = 12.0
    PROGRESS_MIN_STEP_PCT = 0.01
    PROGRESS_SMOOTHING_FACTOR = 0.35
    SEND_START_THRESHOLD_BYTES_MIN = 8192
    SEND_START_THRESHOLD_FRACTION = 0.05
    CONNECT_TOTAL_TIMEOUT_MS = 30000
    CONNECT_RETRY_EVERY_MS = 250
    WAIT_ACK_TIMEOUT_MS = 120000
    SEND_STALL_TIMEOUT_MS = 8000
    CLOSE_GRACE_DELAY_MS = 650
    TIMER_INTERVAL_MS = 50
    DESIRED_SEND_RATE_KBPS = 4
    CHUNK_SIZE = 4096
    CONNECTION_CHECK_INTERVAL_MS = 3000
    CONNECTION_CHECK_TIMEOUT_MS = 1000
    CONNECTION_POLL_INTERVAL_MS = 100
    PING_TIMEOUT_MS = 600
    STATS_UPDATE_INTERVAL_MS = 400
    FILE_CACHE_DURATION_MS = 2000
}

# Constants derived from configuration (do not edit below; edit $cfg above)

# Protocol / file sizes
$LAIN_PORT = $cfg.LAIN_PORT
$SNA_48K_SIZE  = $cfg.SNA_48K_SIZE
$SNA_128K_SIZE = $cfg.SNA_128K_SIZE

# Progress behavior
$P_BASE_AFTER_SEND_START = $cfg.P_BASE_AFTER_SEND_START
$SEND_PROGRESS_MAX_PCT = $cfg.SEND_PROGRESS_MAX_PCT
$WAIT_PROGRESS_MAX_BEFORE_ACK = $cfg.WAIT_PROGRESS_MAX_BEFORE_ACK
$WAIT_PROGRESS_EASE_TAU_SEC = $cfg.WAIT_PROGRESS_EASE_TAU_SEC
$PROGRESS_MAX_RATE_PCT_PER_SEC = $cfg.PROGRESS_MAX_RATE_PCT_PER_SEC
$PROGRESS_MIN_STEP_PCT = $cfg.PROGRESS_MIN_STEP_PCT
$PROGRESS_SMOOTHING_FACTOR = $cfg.PROGRESS_SMOOTHING_FACTOR
$SEND_START_THRESHOLD_BYTES_MIN = $cfg.SEND_START_THRESHOLD_BYTES_MIN
$SEND_START_THRESHOLD_FRACTION = $cfg.SEND_START_THRESHOLD_FRACTION

# Connection retry policy
$CONNECT_TOTAL_TIMEOUT_MS = $cfg.CONNECT_TOTAL_TIMEOUT_MS
$CONNECT_RETRY_EVERY_MS = $cfg.CONNECT_RETRY_EVERY_MS

# Wait-ACK policy
$WAIT_ACK_TIMEOUT_MS = $cfg.WAIT_ACK_TIMEOUT_MS

# Close-confirm grace delay
$CLOSE_GRACE_DELAY_MS = $cfg.CLOSE_GRACE_DELAY_MS

# Transfer pacing
$TIMER_INTERVAL_MS = $cfg.TIMER_INTERVAL_MS  # ms
$DESIRED_SEND_RATE_KBPS = $cfg.DESIRED_SEND_RATE_KBPS
$CHUNK_SIZE = $cfg.CHUNK_SIZE
$MAX_BYTES_PER_TICK = [int][Math]::Max(512, [Math]::Floor($cfg.DESIRED_SEND_RATE_KBPS * 1024 * ($cfg.TIMER_INTERVAL_MS / 1000.0)))

# Connection monitoring
$CONNECTION_CHECK_INTERVAL_MS = $cfg.CONNECTION_CHECK_INTERVAL_MS
$CONNECTION_CHECK_TIMEOUT_MS = $cfg.CONNECTION_CHECK_TIMEOUT_MS
$CONNECTION_POLL_INTERVAL_MS = $cfg.CONNECTION_POLL_INTERVAL_MS
$OPEN_VERIFY_INTERVAL_MS = $(if ($cfg.PSObject.Properties.Name -contains 'OPEN_VERIFY_INTERVAL_MS') { [int]$cfg.OPEN_VERIFY_INTERVAL_MS } else { 8000 })
# Adaptive probing intervals (UI responsiveness vs. server friendliness)
# - Closed: faster discovery so the UI enables SEND quickly when the server comes up.
# - Open but app not responding: relatively fast handshake re-check to recover blue->green promptly.
# - Open and ready: slower verification to detect power-off / reboot without hammering the server.
$PORT_DISCOVERY_INTERVAL_MS = $(if ($cfg.PSObject.Properties.Name -contains 'PORT_DISCOVERY_INTERVAL_MS') { [int]$cfg.PORT_DISCOVERY_INTERVAL_MS } else { 500 })
$OPEN_VERIFY_READY_INTERVAL_MS = $(if ($cfg.PSObject.Properties.Name -contains 'OPEN_VERIFY_READY_INTERVAL_MS') { [int]$cfg.OPEN_VERIFY_READY_INTERVAL_MS } else { 3500 })
$OPEN_VERIFY_NOTREADY_INTERVAL_MS = $(if ($cfg.PSObject.Properties.Name -contains 'OPEN_VERIFY_NOTREADY_INTERVAL_MS') { [int]$cfg.OPEN_VERIFY_NOTREADY_INTERVAL_MS } else { 1200 })
$PING_TIMEOUT_MS = $cfg.PING_TIMEOUT_MS

# UI / stats / caching
$STATS_UPDATE_INTERVAL_MS = $cfg.STATS_UPDATE_INTERVAL_MS
$FILE_CACHE_DURATION_MS = $cfg.FILE_CACHE_DURATION_MS

# Utility functions
function Is-NonEmpty([string]$s) { 
    return -not [string]::IsNullOrWhiteSpace($s) 
}

function Test-Ip([string]$ip) {
    [System.Net.IPAddress]$addr = $null
    return [System.Net.IPAddress]::TryParse($ip, [ref]$addr)
}

function Is-SnaExtension([string]$path) {
    if (-not (Is-NonEmpty $path)) { return $false }
    return ([System.IO.Path]::GetExtension($path) -ieq ".sna")
}

function Safe-TestPath([string]$path) {
    if (-not (Is-NonEmpty $path)) { return $false }
    return (Test-Path -LiteralPath $path)
}

function Safe-FileLength([string]$path) {
    if (-not (Safe-TestPath $path)) { return $null }
    try { return (Get-Item -LiteralPath $path).Length } catch { return $null }
}

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

function Is-ValidSnaFile([string]$path) {
    if (-not (Safe-TestPath $path)) { return $false }
    if (-not (Is-SnaExtension $path)) { return $false }
    return ($null -ne (Get-SnaKindBySize $path))
}

# Cache de archivos optimizado (menos operaciones de I/O)
function Refresh-SelectedFileCache {
    $path = $txtFile.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        $state.CachedFilePath = ""
        $state.CachedFileOk = $false
        $state.CachedSnaName = ""
        return
    }
    
    # Cache hit: misma ruta y caché reciente
    $nowTicks = [DateTime]::UtcNow.Ticks
    if ($state.CachedFilePath -eq $path -and 
        $state.CachedFileOk -ne $null -and 
        ($nowTicks - $state.FileCacheLastCheckTicks) -lt ($FILE_CACHE_DURATION_MS * 10000)) {
        return
    }
    
    # Cache miss: verificar archivo
    $state.CachedFilePath = $path
    $state.CachedFileOk = $false
    $state.CachedSnaName = ""
    $state.FileCacheLastCheckTicks = $nowTicks
    
    try {
        # Verificación rápida con FileInfo (una sola operación I/O)
        $fi = New-Object System.IO.FileInfo($path)
        if (-not $fi.Exists) { return }
        
        # Verificar extensión
        if (-not ($fi.Extension -ieq ".sna")) { return }
        
        # Verificar tamaño
        $len = $fi.Length
        if ($len -eq $SNA_48K_SIZE) {
            $state.CachedKind = "48K"
        } elseif ($len -eq $SNA_128K_SIZE) {
            $state.CachedKind = "128K"
        } else {
            $state.CachedKind = $null
            return
        }
        
        # Normalizar nombre
        $state.CachedSnaName = Normalize-SnaName $path
        $state.CachedFileOk = $true
        
    } catch {
        $state.CachedFileOk = $false
    }
}

function New-CircleBitmap([System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 14,14
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush $color
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 1
    $g.FillEllipse($brush, 1,1,11,11)
    $g.DrawEllipse($pen, 1,1,11,11)
    $g.Dispose(); $brush.Dispose(); $pen.Dispose()
    return $bmp
}

function Test-HostAlive([string]$ip) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            if (-not (Test-Ip $ip)) { return $false }
            try {
                $p = New-Object System.Net.NetworkInformation.Ping
                $r = $p.Send($ip, $PING_TIMEOUT_MS)
                return ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
            } catch {
                return $false
            }

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Test-LainServer([string]$ip) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            if (-not (Test-Ip $ip)) { return $false }
    
            $tcpClient = $null
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectResult = $tcpClient.BeginConnect($ip, $LAIN_PORT, $null, $null)
        
                $success = $connectResult.AsyncWaitHandle.WaitOne($CONNECTION_CHECK_TIMEOUT_MS, $false)
        
                if ($success) {
                    $tcpClient.EndConnect($connectResult)
                    return $true
                } else {
                    return $false
                }
            }
            catch {
                return $false
            }
            finally {
                try { 
                    if ($tcpClient -and $tcpClient.Connected) {
                        $tcpClient.Close() 
                    }
                    $tcpClient.Dispose()
                } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
            }

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Test-LainAppHandshake {
    param(
        [string]$Ip,
        [int]$Port = $LAIN_PORT,
        [string]$ProbeName = "PING",
        [int]$TimeoutMs = 800
    )

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect($Ip, $Port, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
            $client.EndConnect($iar) | Out-Null
            $client.NoDelay = $true

            $ns = $client.GetStream()
            $ns.ReadTimeout  = $TimeoutMs
            $ns.WriteTimeout = $TimeoutMs

            $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($ProbeName)
            if ($nameBytes.Length -gt 255) { $nameBytes = $nameBytes[0..254] }
            $nlen = [int]$nameBytes.Length

            $hdr = New-Object byte[] (11 + $nlen)
            # "LAIN"
            $hdr[0] = 0x4C; $hdr[1] = 0x41; $hdr[2] = 0x49; $hdr[3] = 0x4E
            # uint32 len = 0 (LE)
            $hdr[4] = 0; $hdr[5] = 0; $hdr[6] = 0; $hdr[7] = 0
            # "FN"
            $hdr[8] = 0x46; $hdr[9] = 0x4E
            # name len
            $hdr[10] = [byte]$nlen
            if ($nlen -gt 0) { [Array]::Copy($nameBytes, 0, $hdr, 11, $nlen) }

            $ns.Write($hdr, 0, $hdr.Length)
            $ns.Flush()

            $buf = New-Object byte[] 64
            $t0 = [Environment]::TickCount
            $acc = ""
            while ([Environment]::TickCount - $t0 -lt $TimeoutMs) {
                if (-not $ns.DataAvailable) {
                    # Sleep más largo para menos CPU
                    Start-Sleep -Milliseconds 30
                    continue
                }
                $r = $ns.Read($buf, 0, $buf.Length)
                if ($r -le 0) { break }

                # Búsqueda rápida en buffer
                for ($i = 0; $i -lt $r; $i++) {
                    if ($buf[$i] -eq 0x06) { return $true }
                }

                # Solo convertir a string si es necesario
                if ($r -lt 10) {
                    try { $acc += [System.Text.Encoding]::ASCII.GetString($buf, 0, $r) } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
                    if ($acc.Contains("OK`r`n") -or $acc.Contains("ACK")) { return $true }
                }
            }

            return $false
        } catch {
            return $false
        } finally {
            try { if ($client) { $client.Close(); $client.Dispose() } } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
        }

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Start-ConnectionCheck([string]$ip, [bool]$forcePortProbe = $false, [bool]$skipHandshake = $false) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            if ($state.Phase -ne "Idle" -or $state.TransferActive) { return }
    
            # Reutilizar caché de conexión si está fresca
            $now = [DateTime]::UtcNow
            if (-not $forcePortProbe -and $state.ConnCheckPhase -eq "Idle" -and 
                $state.LastConnectionCheckUtc -ne [DateTime]::MinValue -and
                ($now - $state.LastConnectionCheckUtc).TotalMilliseconds -lt 250) {
                return
            }
    
            if ($state.ConnCheckPhase -ne "Idle") {
                $state.ConnCheckForceProbe = ($state.ConnCheckForceProbe -or $forcePortProbe)
                return
            }

            if (-not (Test-Ip $ip)) {
                Apply-ConnIndicatorStable -Level "Gray" -TipText "Invalid IP address: $ip"
                $state.IpAlive = $false
                $state.PortStatus = "Unknown"
                Update-Buttons-State
                return
            }

            $state.IsCheckingConnection = $true
            $state.ConnCheckIp = $ip
            $state.ConnCheckForceProbe = $forcePortProbe
            $state.ConnCheckSkipHandshake = $skipHandshake
            $state.ConnCheckPhase = "Pinging"
            $state.ConnCheckStartUtc = $now
            $state.LastConnectionCheckUtc = $now
            $state.PingTask = $null


            # TCP-only reachability model: avoid ICMP ping (which can transiently fail during Wi-Fi initialization).
            $state.IpAlive = $true

            if ($connectionTimer.Interval -ne $CONNECTION_POLL_INTERVAL_MS) {
                $connectionTimer.Interval = $CONNECTION_POLL_INTERVAL_MS
            }

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}
function End-ConnectionCheck {
    $state.ConnCheckPhase = "Idle"
    $state.ConnCheckForceProbe = $false
    $state.ConnCheckSkipHandshake = $false
    $state.ConnCheckIp = $null
    $state.IsCheckingConnection = $false
    $state.PingTask = $null
    $state.ProbeTask = $null
    try { if ($state.ProbeClient) { $state.ProbeClient.Close(); $state.ProbeClient.Dispose() } } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    $state.ProbeClient = $null

    # Suspend automatic probing only when the TCP port is open AND the .snapzx app responds (server-friendly).
    if ($state.PSObject.Properties.Name -notcontains "AutoProbeSuspended") { $state | Add-Member -NotePropertyName AutoProbeSuspended -NotePropertyValue $false -Force }
    if ($state.PSObject.Properties.Name -notcontains "LastOpenVerifyUtc") { $state | Add-Member -NotePropertyName LastOpenVerifyUtc -NotePropertyValue ([DateTime]::MinValue) -Force }

    $state.AutoProbeSuspended = ($state.PortStatus -eq "Open" -and $state.AppStatus -eq "Ready")

    $nextMs = if ($state.PortStatus -ne "Open") { $PORT_DISCOVERY_INTERVAL_MS } elseif ($state.AppStatus -ne "Ready") { $OPEN_VERIFY_NOTREADY_INTERVAL_MS } else { $OPEN_VERIFY_READY_INTERVAL_MS }

    if ($connectionTimer.Interval -ne [int]$nextMs) {
        $connectionTimer.Interval = [int]$nextMs
    }

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

            # If the target IP changed, immediately resume probing (forced) so the UI/state updates quickly.
            if ($state.PSObject.Properties.Name -notcontains "LastAutoProbeIp") { $state | Add-Member -NotePropertyName LastAutoProbeIp -NotePropertyValue "" -Force }
            if ($ip -ne $state.LastAutoProbeIp) {
                $state.LastAutoProbeIp = $ip
                $state.AutoProbeSuspended = $false
                Start-ConnectionCheck -ip $ip -forcePortProbe:$true
                return
            }

            # When the port has been confirmed open, background probing is suspended to avoid interfering with the server.
            # However, we still perform a low-rate verification probe to detect power-off / Wi-Fi dropouts.
            if ($state.AutoProbeSuspended -and $state.PortStatus -eq "Open") {
                if ($state.LastOpenVerifyUtc -eq [DateTime]::MinValue -or (($now - $state.LastOpenVerifyUtc).TotalMilliseconds -ge $OPEN_VERIFY_READY_INTERVAL_MS)) {
                    $state.LastOpenVerifyUtc = $now
                    Start-ConnectionCheck -ip $ip -forcePortProbe:$true -skipHandshake:$false
                    return
                }
                $state.NextAutoConnCheckUtc = $now.AddMilliseconds($OPEN_VERIFY_READY_INTERVAL_MS)
                return
            }

            Start-ConnectionCheck -ip $ip -forcePortProbe:$false
            return
        }

        "Pinging" {
            if ($state.PingTask) {
                if (-not $state.PingTask.IsCompleted) { return }

                $alive = $false
                try {
                    if (-not ($state.PingTask.IsFaulted -or $state.PingTask.IsCanceled)) {
                        $reply = $state.PingTask.Result
                        $alive = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                    }
                } catch {
                    $alive = $false
                }

                $state.PingTask = $null
                $state.IpAlive = $alive
            }

            if (-not $state.IpAlive) {
                $state.PortStatus = "Unknown"
                Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable."
                End-ConnectionCheck
                return
            }

            $needProbe = $state.ConnCheckForceProbe -or $state.PortStatus -eq "Unknown" -or (($now - $state.LastPortProbeUtc).TotalMilliseconds -ge 1500)

            if (-not $needProbe) {
                if ($state.PortStatus -eq "Open") {
                    if ($state.AppStatus -eq "NotRunning") {
                        $picConn.Image = $bmpBlue
                        $toolTip.SetToolTip($picConn, "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable, but .lainzx not responding.")
                    } else {
                        Apply-ConnIndicatorStable -Level "Green" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable."
                    }
                } else {
                    Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable."
                }
                End-ConnectionCheck
                return
            }

            $state.LastPortProbeUtc = $now

            try {
                $state.ProbeClient = New-Object System.Net.Sockets.TcpClient

                if ($state.ProbeClient.PSObject.Methods.Name -contains "ConnectAsync") {
                    $state.ProbeTask = $state.ProbeClient.ConnectAsync($state.ConnCheckIp, $LAIN_PORT)
                } else {
                    $state.ProbeAR = $state.ProbeClient.BeginConnect($state.ConnCheckIp, $LAIN_PORT, $null, $null)
                    $state.ProbeTask = $null
                }

                $state.ProbeStartUtc = $now
                $state.ConnCheckPhase = "Probing"
            } catch {
                $state.PortStatus = "Closed"
                $state.AppStatus = "Unknown"
                Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable."
                End-ConnectionCheck
            }
            return
        }

        "Probing" {
            $elapsedMs = [int](($now - $state.ProbeStartUtc).TotalMilliseconds)

            if ($state.ProbeTask) {
                if (-not $state.ProbeTask.IsCompleted) {
                    if ($elapsedMs -gt $CONNECTION_CHECK_TIMEOUT_MS) {
                        $state.PortStatus = "Closed"
                        $state.AppStatus = "Unknown"
                        Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable (timeout)."
                        End-ConnectionCheck
                    }
                    return
                }

                $ok = $false
                try {
                    if (-not ($state.ProbeTask.IsFaulted -or $state.ProbeTask.IsCanceled)) {
                        $state.ProbeTask.GetAwaiter().GetResult()
                        $ok = $true
                    }
                } catch {
                    $ok = $false
                }

                $state.PortStatus = if ($ok) { "Open" } else { "Closed" }

                if ($state.PortStatus -eq "Open") {
                    if (-not $state.ConnCheckSkipHandshake) {
                    $hsOk = $false
                    try { $hsOk = Test-LainAppHandshake -Ip $state.ConnCheckIp -Port $LAIN_PORT -TimeoutMs 700 } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
                    $state.AppStatus = if ($hsOk) { "Ready" } else { "NotRunning" }
                    $state.LastHandshakeUtc = $now
                    }
                    else {
                        $state.AppStatus = "Unknown"
                    }
                } else {
                    $state.AppStatus = "Unknown"
                }

                if ($ok) {
                    if ($state.AppStatus -eq "NotRunning") {
                        $picConn.Image = $bmpBlue
                        $toolTip.SetToolTip($picConn, "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable, but .snapzx not responding.")
                    } else {
                        Apply-ConnIndicatorStable -Level "Green" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable."
                    }
                } else {
                    Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable."
                }

                End-ConnectionCheck
                return
            }

            if ($state.ProbeAR) {
                if ($state.ProbeAR.IsCompleted) {
                    $ok = $false
                    try {
                        $state.ProbeClient.EndConnect($state.ProbeAR)
                        $ok = $true
                    } catch { $ok = $false }

                    $state.PortStatus = if ($ok) { "Open" } else { "Closed" }

                    if ($state.PortStatus -eq "Open") {
                        $hsOk = $false
                        try { $hsOk = Test-LainAppHandshake -Ip $state.ConnCheckIp -Port $LAIN_PORT -TimeoutMs 700 } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
                        $state.AppStatus = if ($hsOk) { "Ready" } else { "NotRunning" }
                        $state.LastHandshakeUtc = $now
                    } else {
                        $state.AppStatus = "Unknown"
                    }

                    if ($ok) {
                        if ($state.AppStatus -eq "NotRunning") {
                            $picConn.Image = $bmpBlue
                            $toolTip.SetToolTip($picConn, "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable, but .snapzx not responding.")
                        } else {
                            Apply-ConnIndicatorStable -Level "Green" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} reachable."
                        }
                    } else {
                        Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable."
                    }

                    $state.ProbeAR = $null
                    End-ConnectionCheck
                    return
                }

                if ($elapsedMs -gt $CONNECTION_CHECK_TIMEOUT_MS) {
                    $state.PortStatus = "Closed"
                    $state.AppStatus = "Unknown"
                    Apply-ConnIndicatorStable -Level "Yellow" -TipText "Target: $($state.ConnCheckIp). Port ${LAIN_PORT} not reachable (timeout)."
                    $state.ProbeAR = $null
                    End-ConnectionCheck
                    return
                }

                return
            }

            End-ConnectionCheck
            return
        }
    }
}

function Invoke-PortProbe {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            if ($state.Phase -ne "Idle") { return }

            $ip = $txtIp.Text.Trim()
            if (-not (Test-Ip $ip)) {
                Apply-ConnIndicatorStable -Level "Gray" -TipText "Invalid IP address: $ip"
                $state.IpAlive = $false
                $state.PortStatus = "Unknown"
                Update-Buttons-State
                return
            }

            $picConn.Image = $bmpBlue
            $toolTip.SetToolTip($picConn, "Probing ${ip}:$LAIN_PORT ...")

            $state.AutoProbeSuspended = $false
            $state.LastAutoProbeIp = $ip
            Start-ConnectionCheck -ip $ip -forcePortProbe:$true
            Process-ConnectionCheckState

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

# Statistics functions
function Format-Bytes {
    param([long]$bytes)
    
    if ($bytes -lt 1024) {
        return "$bytes B"
    } elseif ($bytes -lt 1048576) {
        return "{0:F1} KB" -f ($bytes / 1024)
    } else {
        return "{0:F1} MB" -f ($bytes / 1048576)
    }
}

function Format-TimeSpan {
    param([TimeSpan]$ts)
    
    if ($ts.TotalHours -ge 1) {
        return $ts.ToString("hh\:mm\:ss")
    } elseif ($ts.TotalMinutes -ge 1) {
        return $ts.ToString("mm\:ss")
    } else {
        return "{0:F1}s" -f $ts.TotalSeconds
    }
}

function Update-Statistics {
    if ($state.Phase -ne "Sending" -or $state.TransferStartUtc -eq [DateTime]::MinValue) {
        return
    }

    $now = [DateTime]::UtcNow
    $elapsed = $now - $state.TransferStartUtc
    if ($elapsed.TotalSeconds -le 0) { return }

    $payloadTotal = if ($state.PayloadLen -is [int] -and $state.PayloadLen -gt 0) { [int]$state.PayloadLen } else { [int]$state.Total }
    $headerLen    = if ($state.HeaderLen -is [int] -and $state.HeaderLen -ge 0) { [int]$state.HeaderLen } else { 0 }
    $payloadSent  = [Math]::Max(0, $state.Sent - $headerLen)
    if ($payloadSent -gt $payloadTotal) { $payloadSent = $payloadTotal }

    $bytesPerSecond = $state.Sent / $elapsed.TotalSeconds
    $speedText = if ($bytesPerSecond -gt 0) {
        if ($bytesPerSecond -lt 1024) { "{0:F0} B/s" -f $bytesPerSecond }
        else { "{0:F1} KB/s" -f ($bytesPerSecond / 1024) }
    } else { "--" }

    $etaText = "--"
    if ($bytesPerSecond -gt 0 -and $payloadTotal -gt 0) {
        $remainingPayload = $payloadTotal - $payloadSent
        $etaSeconds = $remainingPayload / $bytesPerSecond
        if ($etaSeconds -gt 0) {
            $etaText = Format-TimeSpan ([TimeSpan]::FromSeconds($etaSeconds))
        }
    }

    $lblStats.Text = "Speed: $speedText | ETA: $etaText | Transferred: $(Format-Bytes $payloadSent)/$(Format-Bytes $payloadTotal)"

    $percent = if ($payloadTotal -gt 0) { [math]::Round(($payloadSent / [double]$payloadTotal) * 100, 1) } else { 0 }
    if ($percent -gt 100) { $percent = 100 }
    if ($percent -lt 0)   { $percent = 0 }

    $lblStatus.Text = "Status: Sending $($state.SnaName) ($($state.Kind))... $percent% complete"
}

function Update-Buttons-State {
    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{
            & $MyInvocation.MyCommand @PSBoundParameters
        })
        return
    }

    if ($state.Phase -ne "Idle") {
        $btnSelect.Enabled = $false
        $btnSend.Enabled = $false
        $btnCancel.Enabled = $true
        $txtIp.Enabled = $false
        $toolTip.SetToolTip($btnSend, "Transfer in progress")
        return
    }
    
    $btnSelect.Enabled = $true
    $btnCancel.Enabled = $false
    $txtIp.Enabled = $true
    
    Refresh-SelectedFileCache
    $ipOk = Test-Ip ($txtIp.Text.Trim())
    $fileOk = ($state.CachedFileOk -eq $true)

    if ($fileOk -and $ipOk -and $state.PortStatus -eq "Open" -and $state.AppStatus -eq "Ready") {
        $btnSend.Enabled = $true
        $btnSend.BackColor = [System.Drawing.SystemColors]::Control
        $btnSend.ForeColor = [System.Drawing.SystemColors]::ControlText
        $toolTip.SetToolTip($btnSend, "Click to send file to Spectrum")
    } else {
        $btnSend.Enabled = $false
        $btnSend.BackColor = [System.Drawing.SystemColors]::Control
        $btnSend.ForeColor = [System.Drawing.SystemColors]::GrayText

        if (-not $fileOk) {
            $toolTip.SetToolTip($btnSend, "Select a valid SNA file first")
        } elseif (-not $ipOk) {
            $toolTip.SetToolTip($btnSend, "Enter a valid IP address")
        } elseif ($state.PortStatus -eq "Closed") {
            $toolTip.SetToolTip($btnSend, "Port 6144 is closed. Click connection indicator to test")
        } elseif ($state.PortStatus -eq "Unknown") {
            $toolTip.SetToolTip($btnSend, "Port 6144 status unknown. Click connection indicator to test")
        } elseif ($state.PortStatus -eq "Open" -and $state.AppStatus -ne "Ready") {
            $toolTip.SetToolTip($btnSend, "Port is open, but .snapzx is not responding. Start .snapzx on the Spectrum.")
        } else {
            $toolTip.SetToolTip($btnSend, "Cannot send - check file and connection")
        }
    }
}

function Set-AppState {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NewPhase
    )

    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{
            & $MyInvocation.MyCommand @PSBoundParameters
        })
        return
    }
    # Centralize phase transitions and the UI enable/disable side-effects.
    # Do not override TransferActive here except when returning to Idle, to preserve existing semantics.
    $state.Phase = $NewPhase
    if ($NewPhase -eq "Idle") {
        $state.TransferActive = $false
        if (Get-Command Stop-TransferBlink -ErrorAction SilentlyContinue) { Stop-TransferBlink }
    }
    Update-Buttons-State
}

# ---------------- UI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "SnapZX SNA Uploader"
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.ClientSize = New-Object System.Drawing.Size(680, 320)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = "Spectrum IP:"
$lblIp.Location = New-Object System.Drawing.Point(12, 18)
$lblIp.AutoSize = $true

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Location = New-Object System.Drawing.Point(120, 14)
$txtIp.Size = New-Object System.Drawing.Size(240, 22)
$txtIp.Text = "192.168.0.205"

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Fixed port: 6144"
$lblPort.Location = New-Object System.Drawing.Point(374, 18)
$lblPort.AutoSize = $true

$bmpGreen = New-CircleBitmap ([System.Drawing.Color]::LimeGreen)
$bmpYellow = New-CircleBitmap ([System.Drawing.Color]::Yellow)
$bmpGray = New-CircleBitmap ([System.Drawing.Color]::Gray)
$bmpBlue = New-CircleBitmap ([System.Drawing.Color]::Blue)
$bmpRed  = New-CircleBitmap ([System.Drawing.Color]::Red)


function Ensure-ConnStabilityState {
    if (-not $state.PSObject.Properties.Match("ConnFailCount"))      { $state | Add-Member -NotePropertyName ConnFailCount -NotePropertyValue 0 -Force }
    if (-not $state.PSObject.Properties.Match("ConnFailThreshold")) { $state | Add-Member -NotePropertyName ConnFailThreshold -NotePropertyValue 2 -Force }
    if (-not $state.PSObject.Properties.Match("ConnGraceMs"))       { $state | Add-Member -NotePropertyName ConnGraceMs -NotePropertyValue $cfg.CONN_GRACE_MS -Force }
    if (-not $state.PSObject.Properties.Match("LastConnectedUtc"))  { $state | Add-Member -NotePropertyName LastConnectedUtc -NotePropertyValue ([DateTime]::MinValue) -Force }
}

function Apply-ConnIndicatorStable {
    param(
        [ValidateSet("Green","Blue","Yellow","Gray")]
        [string]$Level,
        [string]$TipText = "",
        [bool]$Force = $false
    )

    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{
            & $MyInvocation.MyCommand @PSBoundParameters
        })
        return
    }

    Ensure-ConnStabilityState
    $now = [DateTime]::UtcNow

    # "Blue" is a transient UI state (checking). Do not apply hysteresis.
    if ($Level -eq "Blue") {
        $picConn.Image = $bmpBlue
        if ($TipText) { $toolTip.SetToolTip($picConn, $TipText) }
        return
    }

    if ($Force) {
        if ($Level -eq "Green") {
            $state.ConnFailCount = 0
            $state.LastConnectedUtc = $now
            $picConn.Image = $bmpGreen
        } elseif ($Level -eq "Yellow") {
            $picConn.Image = $bmpYellow
        } else {
            $picConn.Image = $bmpGray
        }
        if ($TipText) { $toolTip.SetToolTip($picConn, $TipText) }
        return
    }

    if ($Level -eq "Green") {
        $state.ConnFailCount = 0
        $state.LastConnectedUtc = $now
        $picConn.Image = $bmpGreen
        if ($TipText) { $toolTip.SetToolTip($picConn, $TipText) }
        return
    }

    # Hysteresis: keep "connected" briefly after the last confirmed OK
    if ($state.LastConnectedUtc -ne [DateTime]::MinValue) {
        $ageMs = ($now - $state.LastConnectedUtc).TotalMilliseconds
        if ($ageMs -lt [double]$state.ConnGraceMs) {
            $picConn.Image = $bmpGreen
            if ($TipText) { $toolTip.SetToolTip($picConn, "Connected (recent). " + $TipText) }
            return
        }
    }

    # Require N consecutive failures before flipping to Yellow/Gray
    $state.ConnFailCount++
    if ($state.ConnFailCount -lt [int]$state.ConnFailThreshold -and $state.LastConnectedUtc -ne [DateTime]::MinValue) {
        $picConn.Image = $bmpGreen
        if ($TipText) { $toolTip.SetToolTip($picConn, "Connected (retrying). " + $TipText) }
        return
    }

    if ($Level -eq "Yellow") {
        $picConn.Image = $bmpYellow
    } else {
        $picConn.Image = $bmpGray
    }
    if ($TipText) { $toolTip.SetToolTip($picConn, $TipText) }
}

function Apply-ConnIndicator {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Green','Yellow','Gray','Blue','Red')][string]$Color,
        [string]$Tooltip = $null
    )
    Apply-ConnIndicatorStable -Color $Color -Tooltip $Tooltip
}


$picConn = New-Object System.Windows.Forms.PictureBox
$picConn.Location = New-Object System.Drawing.Point(548, 16)
$picConn.Size = New-Object System.Drawing.Size(14, 14)
$picConn.BackColor = [System.Drawing.Color]::Transparent
$picConn.Image = $bmpGray
$picConn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($picConn, "Connection: Gray=IP unreachable, Yellow=IP reachable (port unknown/closed), Green=port 6144 reachable. Click to probe port 6144.")

$picConn.Cursor = [System.Windows.Forms.Cursors]::Hand
$picConn.Add_Click({ Invoke-PortProbe })

$lblConn = New-Object System.Windows.Forms.Label
$lblConn.Text = "Connection"
$lblConn.Location = New-Object System.Drawing.Point(568, 15)
$lblConn.AutoSize = $true
$lblConn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

# --- Transfer blink indicator (circle + label) ---
$script:TransferBlinkTimer = New-Object System.Windows.Forms.Timer
$script:TransferBlinkTimer.Interval = 350
$script:TransferBlinkVisible = $true

$script:TransferBlinkTimer.Add_Tick({
    try {
        if (-not $state.TransferActive) {
            Stop-TransferBlink
            return
        }
        $script:TransferBlinkVisible = -not $script:TransferBlinkVisible
        $picConn.Visible = $script:TransferBlinkVisible
    } catch {
        $script:LastErrorRecord = $_
    }
})

function Start-TransferBlink {
    param(
        [string]$Text = "Transferring"
    )
    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{ Start-TransferBlink -Text $Text })
        return
    }
    if (-not $picConn -or -not $lblConn -or -not $script:TransferBlinkTimer) { return }
    $lblConn.Text = $Text
    $picConn.Visible = $true
    $script:TransferBlinkVisible = $true
    $script:TransferBlinkTimer.Start()
}

function Stop-TransferBlink {
    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{ Stop-TransferBlink })
        return
    }
    try { if ($script:TransferBlinkTimer) { $script:TransferBlinkTimer.Stop() } } catch {
        $script:LastErrorRecord = $_
    }
    if ($picConn) { $picConn.Visible = $true }
    if ($lblConn) { $lblConn.Text = "Connection" }
}



function Update-TransferPhaseUi {
    if ($script:form -and $script:form.InvokeRequired) {
        $null = $script:form.BeginInvoke([Action]{ Update-TransferPhaseUi })
        return
    }
    if (-not $progress -or -not $lblConn) { return }

    if (-not $state.TransferActive) {
        if (-not $progress.Visible) { $progress.Visible = $true }
        return
    }

    switch ($state.Phase) {
        "Connecting" { $lblConn.Text = "Connecting";   $progress.Visible = $true }
        "Sending"    { $lblConn.Text = "Transferring"; $progress.Visible = $true }
        "WaitingAck" { $lblConn.Text = "Waiting ACK";  $progress.Visible = $false }
        "Finalizing" { $lblConn.Text = "Finalizing";   $progress.Visible = $false }
        default      { $lblConn.Text = "Working";      $progress.Visible = $true }
    }
}

$lblFile = New-Object System.Windows.Forms.Label
$lblFile.Text = "Snapshot (.sna):"
$lblFile.Location = New-Object System.Drawing.Point(12, 58)
$lblFile.AutoSize = $true

$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Location = New-Object System.Drawing.Point(120, 54)
$txtFile.Size = New-Object System.Drawing.Size(430, 22)
$txtFile.ReadOnly = $true
$txtFile.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$btnSelect = New-Object System.Windows.Forms.Button
$btnSelect.Text = "Select file"
$btnSelect.Location = New-Object System.Drawing.Point(560, 52)
$btnSelect.Size = New-Object System.Drawing.Size(108, 26)
$btnSelect.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnSelect.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = "Send"
$btnSend.Location = New-Object System.Drawing.Point(442, 82)
$btnSend.Size = New-Object System.Drawing.Size(108, 26)
$btnSend.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
$btnSend.Enabled = $false
$btnSend.UseVisualStyleBackColor = $true

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(560, 82)
$btnCancel.Size = New-Object System.Drawing.Size(108, 26)
$btnCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCancel.Enabled = $false

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 120)
$progress.Size = New-Object System.Drawing.Size(656, 18)
$progress.Minimum = 0
$progress.Maximum = 1000
$progress.Value = 0
$progress.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblStats = New-Object System.Windows.Forms.Label
$lblStats.Location = New-Object System.Drawing.Point(12, 145)
$lblStats.AutoSize = $true
$lblStats.Text = "Speed: -- | ETA: -- | Transferred: --/--"
$lblStats.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(12, 170)
$lblStatus.AutoSize = $true
$lblStatus.MaximumSize = New-Object System.Drawing.Size(656, 0)
$lblStatus.Text = "Status: ready. 1) Run .snapzx on the Spectrum. 2) Select a .sna and Send (the Spectrum will save it in the current directory and run snapload)."
$lblStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lnkCredits = New-Object System.Windows.Forms.LinkLabel
$lnkCredits.Text = "(C) M. Ignacio Monge 2025"
$lnkCredits.AutoSize = $true
$lnkCredits.Location = New-Object System.Drawing.Point(12, 0)
$lnkCredits.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$lnkCredits.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
$lnkCredits.TabStop = $true
$lnkCredits.Add_LinkClicked({
    try { Start-Process "https://github.com/IgnacioMonge/lainZX" } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
})

$openDlg = New-Object System.Windows.Forms.OpenFileDialog
$openDlg.Filter = "SNA snapshots (*.sna)|*.sna|All files (*.*)|*.*"
$openDlg.Title = "Select a .sna snapshot"

$form.Controls.AddRange(@(
    $lblIp, $txtIp, $lblPort, $picConn, $lblConn,
    $lblFile, $txtFile, $btnSelect, $btnSend, $btnCancel,
    $progress, $lblStats, $lblStatus, $lnkCredits
))

$form.Add_Shown({
    $w = $form.ClientSize.Width
    $minY = $lblStatus.Bottom + 12
    $h = $minY + $lnkCredits.Height + 24
    $form.ClientSize = New-Object System.Drawing.Size($w, $h)
    
    $lnkCredits.Location = New-Object System.Drawing.Point(
        ($form.ClientSize.Width - $lnkCredits.Width - 12),
        ($form.ClientSize.Height - $lnkCredits.Height - 10)
    )
    
    Update-Buttons-State
})

# ---------------- State machine ----------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $TIMER_INTERVAL_MS

$connectionTimer = New-Object System.Windows.Forms.Timer
$connectionTimer.Interval = $PORT_DISCOVERY_INTERVAL_MS

$state = [pscustomobject]@{
    Phase = "Idle"
    Ip = $null
    Path = $null
    SnaName = ""
    Kind = $null
    Bytes = $null
    # Streaming transfer (avoid loading full file into RAM)
    HeaderBytes = $null
    HeaderSent = 0
    FileStream = $null
    SendBuf = $null
    SendBufOffset = 0
    SendBufCount = 0
    SendBufIsHeader = $false
    Total = 0
    HeaderLen = 0
    PayloadLen = 0
    Sent = 0
    Client = $null
    Sock = $null
    ConnectAR = $null
    ConnectStartUtc = [DateTime]::MinValue
    NextRetryUtc = [DateTime]::MinValue
    WaitStartUtc = [DateTime]::MinValue
    
    # Transfer statistics
    TransferStartUtc = [DateTime]::MinValue
    LastSendProgressUtc = [DateTime]::MinValue
    LastStatsUpdate = [DateTime]::UtcNow
    AverageSpeedBps = 0
    SpeedSamples = @()
    
    # Smoothed progress (0-100 range)
    ProgressStarted = $false
    UiProgress = 0.0
    TargetProgress = 0.0
    LastTickUtc = [DateTime]::UtcNow
    
    # Remote close confirmation
    CloseObservedUtc = [DateTime]::MinValue
    
    # ACK from Spectrum
    AckReceived = $false
    AckBuffer = ""
    
    # Cancellation flag
    Cancelled = $false
    
    # Connection monitoring state
    IsCheckingConnection = $false
    TransferActive = $false
    IpAlive = $false
    PortStatus = "Unknown"
    AppStatus = "Unknown"
    AutoProbeSuspended = $false
    LastAutoProbeIp = ""
    LastHandshakeUtc = [DateTime]::MinValue
    LastPortProbeUtc = [DateTime]::MinValue
    LastConnectionCheckUtc = [DateTime]::MinValue

    # Cached file state
    CachedFilePath = ""
    CachedFileOk = $null
    CachedKind = $null
    CachedSnaName = ""
    FileCacheLastCheckTicks = 0

    # Non-blocking connection checks
    ConnCheckPhase = "Idle"
    ConnCheckIp = $null
    ConnCheckForceProbe = $false
    ConnCheckSkipHandshake = $false
    LastOpenVerifyUtc = [DateTime]::MinValue
    ConnCheckStartUtc = [DateTime]::MinValue
    NextAutoConnCheckUtc = [DateTime]::MinValue
    PingTask = $null
    ProbeClient = $null
    ProbeTask = $null
    ProbeAR = $null
    ProbeStartUtc = [DateTime]::MinValue

    # Connection indicator stability (hysteresis)
    ConnFailCount = 0
    ConnFailThreshold = $cfg.CONN_FAIL_THRESHOLD      # consecutive failures required to mark "not connected"
    ConnGraceMs = $cfg.CONN_GRACE_MS         # keep "connected" for this long after last confirmed OK
    LastConnectedUtc = [DateTime]::MinValue

}


# =========================
# Concurrency: state lock
# =========================
$script:StateLock = New-Object object
function Invoke-WithStateLock {
    param([Parameter(Mandatory=$true)][scriptblock]$Action)
    [System.Threading.Monitor]::Enter($script:StateLock)
    try { & $Action }
    finally { [System.Threading.Monitor]::Exit($script:StateLock) }
}

# Grouped state views (to reduce coupling). The script still uses the existing flat $state.* fields
# for backwards compatibility; these grouped objects are maintained by helper setters where applicable.
if (-not ($state.PSObject.Properties.Name -contains 'Conn')) {
    $state | Add-Member -NotePropertyName Conn -NotePropertyValue ([pscustomobject]@{
    FailCount      = $state.ConnFailCount
    FailThreshold  = $state.ConnFailThreshold
    GraceMs        = $state.ConnGraceMs
    LastOkUtc      = $state.LastConnectedUtc
}) -Force
} else {
    $state.Conn = [pscustomobject]@{
    FailCount      = $state.ConnFailCount
    FailThreshold  = $state.ConnFailThreshold
    GraceMs        = $state.ConnGraceMs
    LastOkUtc      = $state.LastConnectedUtc
}
}

if (-not ($state.PSObject.Properties.Name -contains 'Transfer')) {
    $state | Add-Member -NotePropertyName Transfer -NotePropertyValue ([pscustomobject]@{
    Active   = $state.TransferActive
    Cancelled = $state.Cancelled
    Sent     = $state.Sent
    Total    = $state.Total
}) -Force
} else {
    $state.Transfer = [pscustomobject]@{
    Active   = $state.TransferActive
    Cancelled = $state.Cancelled
    Sent     = $state.Sent
    Total    = $state.Total
}
}

if (-not ($state.PSObject.Properties.Name -contains 'UI')) {
    $state | Add-Member -NotePropertyName UI -NotePropertyValue ([pscustomobject]@{
    Phase = $state.Phase
}) -Force
} else {
    $state.UI = [pscustomobject]@{
    Phase = $state.Phase
}
}

function Set-UiBusy([bool]$busy) {
    $form.UseWaitCursor = $busy
    Update-Buttons-State
}

function Cleanup-Connection {
    try { if ($state.Sock) { $state.Sock.Close(); $state.Sock.Dispose() } } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    try { if ($state.Client) { $state.Client.Close(); $state.Client.Dispose() } } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    $state.Client = $null
    $state.Sock = $null
    $state.ConnectAR = $null
}

function Cleanup-TransferResources {
    # File stream and send buffers (keep separate from network cleanup to allow connect retries)
    try { if ($state.FileStream) { $state.FileStream.Close(); $state.FileStream.Dispose() } } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    $state.FileStream = $null
    $state.HeaderBytes = $null
    $state.HeaderSent = 0
    $state.SendBuf = $null
    $state.SendBufOffset = 0
    $state.SendBufCount = 0
    $state.SendBufIsHeader = $false
}

function Reset-ToIdle([string]$statusText = $null) {
    $timer.Stop()
    Cleanup-TransferResources
    Cleanup-Connection
    Set-AppState "Idle"
    $state.Cancelled = $false
    $state.TransferActive = $false
    Set-UiBusy $false
    $progress.Value = 0
    $state.ProgressStarted = $false
    $state.UiProgress = 0.0
    $state.TargetProgress = 0.0
    $state.CloseObservedUtc = [DateTime]::MinValue
    $state.AckReceived = $false
    $state.AckBuffer = ""
    $state.TransferStartUtc = [DateTime]::MinValue
    $state.AverageSpeedBps = 0
    $state.SpeedSamples = @()
    
    $lblStats.Text = "Speed: -- | ETA: -- | Transferred: --/--"
    
    $connectionTimer.Start()
    
    if ($statusText) {
        $lblStatus.Text = $statusText
    } else {
        $lblStatus.Text = "Status: ready. 1) Run .snapzx on the Spectrum. 2) Select a .sna and Send (the Spectrum will save it as /TMP/<name> and run snapload)."
    }
    
    Update-Buttons-State
}

function Cancel-Transfer {
    if ($state.Phase -in @("Connecting", "Sending", "WaitingAck", "Finalizing")) {
        $state.Cancelled = $true
    Set-AppState "Finalizing"
        $state.CloseObservedUtc = [DateTime]::UtcNow.AddMilliseconds(-$CLOSE_GRACE_DELAY_MS)
        $lblStatus.Text = "Status: Cancelling transfer..."
        $picConn.Image = $bmpYellow
    }
}

function Fail-AndReset([string]$message, [string]$detail = $null) {
    Reset-ToIdle "Status: ready. Try again when .snapzx is waiting for a connection."
    $text = $message
    if ($detail) { $text += "`r`n`r`n$detail" }
    [System.Windows.Forms.MessageBox]::Show(
        $form, $text, "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Finish-Send([bool]$timedOut = $false, [bool]$cancelled = $false) {
    $timer.Stop()
    Cleanup-Connection
    
    if ($cancelled) {
        Reset-ToIdle "Status: Transfer cancelled."
        [System.Windows.Forms.MessageBox]::Show(
            $form, "Transfer was cancelled.", "Cancelled",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }
    Set-AppState "Idle"
    $state.TransferActive = $false
    Set-UiBusy $false
    
    if (-not $timedOut -and -not $cancelled) {
        $state.TargetProgress = 0
        $state.UiProgress = 0
        $progress.Value = 0
    } else {
        $progress.Value = $progress.Maximum
    }
    
    $totalTime = if ($state.TransferStartUtc -ne [DateTime]::MinValue) {
        ([DateTime]::UtcNow - $state.TransferStartUtc).TotalSeconds
    } else { 0 }
    
    $ackTxt = if ($state.AckReceived) { "ACK" } else { "no ACK" }
    
    if ($timedOut) {
        $lblStatus.Text = "Status: completed (ACK timeout; $ackTxt) in {0:F1}s." -f $totalTime
    } else {
        $lblStatus.Text = "Status: completed ($ackTxt) in {0:F1}s." -f $totalTime
    }
    
    $avgSpeed = if ($totalTime -gt 0) { $state.Total / $totalTime } else { 0 }
    $speedText = if ($avgSpeed -ge 1024) { "{0:F1} KB/s" -f ($avgSpeed / 1024) } else { "{0:F0} B/s" -f $avgSpeed }
    $lblStats.Text = "Avg Speed: $speedText | Total: $(Format-Bytes $state.Total) | Time: {0:F1}s" -f $totalTime
    
    $txtFile.Text = ""
    
    $connectionTimer.Start()
    
    Update-Buttons-State
}

function Start-ConnectAttempt {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            Cleanup-Connection
            $state.Client = New-Object System.Net.Sockets.TcpClient
            $state.Client.SendTimeout = 8000
            $state.Client.ReceiveTimeout = 500
            $state.ConnectAR = $state.Client.BeginConnect($state.Ip, $LAIN_PORT, $null, $null)

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Set-TargetProgress([double]$p) {
    if ($p -lt 0) { $p = 0 }
    if ($p -gt 100) { $p = 100 }
    $state.TargetProgress = $p
}

function Apply-SmoothedProgress {
    $now = [DateTime]::UtcNow
    $dt = ($now - $state.LastTickUtc).TotalSeconds
    if ($dt -lt 0) { $dt = 0 }
    $state.LastTickUtc = $now
    
    $diff = $state.TargetProgress - $state.UiProgress
    $state.UiProgress += $diff * $PROGRESS_SMOOTHING_FACTOR
    
    if ($state.UiProgress -lt 0) { $state.UiProgress = 0 }
    if ($state.UiProgress -gt 100) { $state.UiProgress = 100 }
    
    $progressValue = [int][Math]::Floor($state.UiProgress * 10)
    if ($progressValue -lt 0) { $progressValue = 0 }
    if ($progressValue -gt 1000) { $progressValue = 1000 }
    
    if ($progress.Value -ne $progressValue) {
        $progress.Value = $progressValue
        # Llamar DoEvents con menos frecuencia
        if ($state.Phase -eq "Sending" -and ($progressValue % 50) -eq 0) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Start-SendWorkflow {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {

            if ($state.Phase -ne "Idle") { return }
    
            if ($state.PortStatus -ne "Open") {
                [System.Windows.Forms.MessageBox]::Show(
                    "Port 6144 is not open. Please check that the Spectrum is running .snapzx and the connection is available.",
                    "Port Not Open",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }
    
            $ip = $txtIp.Text.Trim()
            $path = $txtFile.Text
    
            Refresh-SelectedFileCache

            if (-not (Test-LainAppHandshake -Ip $ip -Port $LAIN_PORT -TimeoutMs 800)) {
                $state.AppStatus = "NotRunning"
                $state.LastHandshakeUtc = [DateTime]::UtcNow
                Update-Buttons-State
                [System.Windows.Forms.MessageBox]::Show(
                    "Port 6144 is open, but .snapzx is not responding. Please start .snapzx on the Spectrum and try again.",
                    ".snapzx Not Running",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }

            Refresh-SelectedFileCache
            if (-not (Test-Ip $ip)) { return }
            if (-not ($state.CachedFileOk -eq $true)) { return }
    
    
        $connectionTimer.Stop()

            try {
                # Stream payload from disk to avoid loading the whole file into RAM (supports generic/bigger files)
                $fileInfo = Get-Item -LiteralPath $path
                $plen64 = [int64]$fileInfo.Length
                if ($plen64 -lt 0 -or $plen64 -gt [UInt32]::MaxValue) {
                    throw "File too large for LAIN protocol (max 4 GiB - 1)."
                }
                if ($plen64 -gt [int64][int]::MaxValue) {
                    throw "File too large for this sender implementation (payload > 2 GiB)."
                }
                $plen = [int]$plen64

                $snaName = $state.CachedSnaName
                $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($snaName)
                $nlen = [int]$nameBytes.Length

                if ($nlen -lt 0 -or $nlen -gt 255) {
                    throw "Invalid filename length"
                }

                $headerSize = 11 + $nlen
                $headerBytes = New-Object byte[] $headerSize

                # 'LAIN'
                $headerBytes[0] = 0x4C
                $headerBytes[1] = 0x41
                $headerBytes[2] = 0x49
                $headerBytes[3] = 0x4E

                # uint32 payload length (little-endian)
                $lenBytes = [System.BitConverter]::GetBytes([UInt32]$plen)
                [Array]::Copy($lenBytes, 0, $headerBytes, 4, 4)

                # marker 'FN'
                $headerBytes[8]  = 0x46
                $headerBytes[9]  = 0x4E
                $headerBytes[10] = [byte]$nlen

                if ($nlen -gt 0) {
                    [Array]::Copy($nameBytes, 0, $headerBytes, 11, $nlen)
                }

                # Open file stream for streaming payload
                $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)

                $kind = $state.CachedKind
                $state.Ip = $ip
                $state.Path = $path
                $state.Kind = $kind
                $state.SnaName = $snaName
                $state.Bytes = $null
                $state.HeaderBytes = $headerBytes
                $state.HeaderSent = 0
                $state.FileStream = $fs
                if ($null -eq $state.SendBuf -or $state.SendBuf.Length -ne $CHUNK_SIZE) {
                    $state.SendBuf = New-Object byte[] $CHUNK_SIZE
                }
                $state.SendBufOffset = 0
                $state.SendBufCount = 0
                $state.SendBufIsHeader = $false
                $state.Total = ($headerSize + $plen)
                $state.HeaderLen = $headerSize
                $state.PayloadLen = $plen
                $state.Sent = 0
                $state.ConnectAR = $null
                $state.ConnectStartUtc = [DateTime]::UtcNow
                $state.TransferStartUtc = [DateTime]::UtcNow
                $state.LastSendProgressUtc = [DateTime]::UtcNow
                $state.NextRetryUtc = [DateTime]::UtcNow
            Set-AppState "Connecting"
                $state.WaitStartUtc = [DateTime]::MinValue
                $state.ProgressStarted = $false
                $state.UiProgress = 0.0
                $state.TargetProgress = 0.0
                $state.LastTickUtc = [DateTime]::UtcNow
                $state.CloseObservedUtc = [DateTime]::MinValue
                $state.AckReceived = $false
                $state.AckBuffer = ""
                $state.Cancelled = $false
                $state.TransferActive = $true
                $state.AverageSpeedBps = 0
                $state.SpeedSamples = @()
        
                $progress.Value = 0
                $picConn.Image = $bmpBlue
                Set-UiBusy $true
                Start-TransferBlink -Text "Connecting"
        
                $lblStatus.Text = ("Status: ready to send {0} ({1}) to {2}:{3}." -f $snaName, $kind, $ip, $LAIN_PORT)
                $lblStats.Text = "Speed: -- | ETA: -- | Transferred: --/$(Format-Bytes $state.Total)"
        
                $timer.Start()
            } catch {
                $connectionTimer.Start()
                Fail-AndReset "Could not read the file." $_.Exception.ToString()
            }

    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

$connectionTimer.Add_Tick({
    Invoke-WithStateLock {
        if ($state.Phase -ne "Idle" -or $state.TransferActive) { return }
        Process-ConnectionCheckState
    }
})


function Transfer-EngineTick {
    # Core transfer/connection state machine step.
    # This function must NOT touch WinForms controls directly.
    $ui = [ordered]@{
        StatusText = $null
        ConnIndicator = $null   # 'Green' | 'Red' | 'Grey'
        ConnectionTimerAction = $null  # 'Start' | $null
        NeedButtons = $false
        ApplyProgress = $false
        RequestFail = $false
        FailMessage = $null
        FailDetail = $null
    }

    try {
        switch ($state.Phase) {
                    "Connecting" {
                        $elapsedMs = [int](([DateTime]::UtcNow - $state.ConnectStartUtc).TotalMilliseconds)
                        if ($elapsedMs -gt $CONNECT_TOTAL_TIMEOUT_MS) {
                            $ui.ConnectionTimerAction = 'Start'
                            $ui.RequestFail = $true; $ui.FailMessage = ("Could not connect to {0}:{1} (timeout); $ui.FailDetail = $null; return [pscustomobject]$ui. Is .snapzx waiting for a connection?" -f $state.Ip, $LAIN_PORT)
                            break
                        }
                
                        Set-TargetProgress 0
                        $ui.ApplyProgress = $true
                
                        if ([DateTime]::UtcNow -lt $state.NextRetryUtc) {
                            $ui.StatusText = ("Status: waiting for .snapzx (retrying TCP {0}:{1})..." -f $state.Ip, $LAIN_PORT)
                            break
                        }
                
                        if ($null -eq $state.ConnectAR) {
                            Start-ConnectAttempt
                            $state.NextRetryUtc = [DateTime]::UtcNow.AddMilliseconds($CONNECT_RETRY_EVERY_MS)
                            $ui.StatusText = ("Status: trying to connect TCP {0}:{1}..." -f $state.Ip, $LAIN_PORT)
                            break
                        }
                
                        if (-not $state.ConnectAR.IsCompleted) {
                            $ui.StatusText = ("Status: connecting TCP {0}:{1}..." -f $state.Ip, $LAIN_PORT)
                            break
                        }
                
                        try {
                            $state.Client.EndConnect($state.ConnectAR)
                            $state.Sock = $state.Client.Client
                            $state.Sock.NoDelay = $true
                            $state.Sock.Blocking = $false
                            $state.Sock.SendBufferSize = $cfg.SOCKET_BUFFER_SIZE
                            $state.Sock.ReceiveBufferSize = $cfg.SOCKET_BUFFER_SIZE
                            $state.ConnectAR = $null
                    
                            $ui.ConnIndicator = 'Green'
            $state.Phase = "Sending"; $ui.NeedButtons = $true; if ("Sending" -eq "Idle") { $state.TransferActive = $false }
                            $ui.StatusText = ("Status: connection established ({0})." -f $state.Kind)
                            $state.ProgressStarted = $false
                            Set-TargetProgress 0
                            $ui.ApplyProgress = $true
                        } catch {
                            $state.ConnectAR = $null
                            Cleanup-Connection
                            $state.NextRetryUtc = [DateTime]::UtcNow.AddMilliseconds($CONNECT_RETRY_EVERY_MS)
                            $ui.StatusText = ("Status: .snapzx not ready yet (retrying)...")
                        }
                    }
            
                    "Sending" {
                        if ($state.Cancelled) {
                            Finish-Send -cancelled $true
                            break
                        }
                
                        if ($state.Sent -ge $state.Total) {
            $state.Phase = "WaitingAck"; $ui.NeedButtons = $true; if ("WaitingAck" -eq "Idle") { $state.TransferActive = $false }
                            $state.WaitStartUtc = [DateTime]::UtcNow
                            $state.AckReceived = $false
                            $state.AckBuffer = ""
                            Set-TargetProgress $SEND_PROGRESS_MAX_PCT
                            $ui.ApplyProgress = $true
                            $ui.StatusText = "Status: send complete. Waiting for ACK from Spectrum..."
                            break
                        }
                
                        $bytesThisTick = 0
        while ($state.Sent -lt $state.Total -and $bytesThisTick -lt $MAX_BYTES_PER_TICK) {
            $remaining = $state.Total - $state.Sent
            $budget = $MAX_BYTES_PER_TICK - $bytesThisTick
            if ($budget -le 0) { break }

            # Fill send buffer (header first, then payload streamed from disk)
            if ($state.SendBufCount -le 0) {
                if ($state.HeaderSent -lt $state.HeaderLen) {
                    $hRem = $state.HeaderLen - $state.HeaderSent
                    $fill = [int][Math]::Min($CHUNK_SIZE, $hRem)
                    if ($fill -le 0) { break }

                    [Array]::Copy($state.HeaderBytes, $state.HeaderSent, $state.SendBuf, 0, $fill)
                    $state.SendBufOffset = 0
                    $state.SendBufCount = $fill
                    $state.SendBufIsHeader = $true
                } else {
                    if ($null -eq $state.FileStream) { throw "Internal error: File stream not available." }
                    $read = $state.FileStream.Read($state.SendBuf, 0, $CHUNK_SIZE)
                    if ($read -le 0) {
                        if ($state.Sent -lt $state.Total) { throw "Unexpected end of file during send." }
                        break
                    }
                    $state.SendBufOffset = 0
                    $state.SendBufCount = $read
                    $state.SendBufIsHeader = $false
                }
            }

            $toSend = [int][Math]::Min($state.SendBufCount, $budget)
            if ($toSend -le 0) { break }

            try {
                if (-not $state.Sock.Poll(0, [System.Net.Sockets.SelectMode]::SelectWrite)) { break }
                $n = $state.Sock.Send($state.SendBuf, $state.SendBufOffset, $toSend, [System.Net.Sockets.SocketFlags]::None)
                if ($n -le 0) { throw "Connection closed during send." }

                $state.Sent += $n
                $bytesThisTick += $n
                $state.SendBufOffset += $n
                $state.SendBufCount -= $n
                if ($state.SendBufIsHeader) { $state.HeaderSent += $n }
            } catch [System.Net.Sockets.SocketException] {
                if ($_.Exception.NativeErrorCode -eq 10035) { break }
                throw
            }
        }

        $threshold =
                        # Stall detection: if we cannot make forward progress for a while, auto-cancel
                        $now = [DateTime]::UtcNow
                        if ($bytesThisTick -gt 0) {
                            $state.LastSendProgressUtc = $now
                        } else {
                            if ($state.LastSendProgressUtc -ne [DateTime]::MinValue) {
                                $stallMs = ($now - $state.LastSendProgressUtc).TotalMilliseconds
                                if ($stallMs -ge $cfg.SEND_STALL_TIMEOUT_MS) {
                                    $ui.StatusText = ("Status: stalled (no send progress for {0} ms). Cancelling..." -f [int]$stallMs)
                                    $state.Cancelled = $true
                                    Finish-Send -cancelled $true
                                    break
                                }
                            }
                        }

                        $threshold = [Math]::Max($SEND_START_THRESHOLD_BYTES_MIN, [int][Math]::Ceiling($state.Total * $SEND_START_THRESHOLD_FRACTION))
                        if (-not $state.ProgressStarted) {
                            if ($state.Sent -ge $threshold) {
                                $state.ProgressStarted = $true
                                if ($state.UiProgress -lt $P_BASE_AFTER_SEND_START) { 
                                    $state.UiProgress = [double]$P_BASE_AFTER_SEND_STart 
                                }
                            } else {
                                Set-TargetProgress 0
                                $ui.ApplyProgress = $true
                                $ui.StatusText = ("Status: connection established. Starting transfer... ({0}/{1} bytes)" -f $state.Sent, $state.Total)
                                break
                            }
                        }
                
                        $payloadTotal = if ($state.PayloadLen -is [int] -and $state.PayloadLen -gt 0) { [int]$state.PayloadLen } else { [int]($state.Total) }
                        $headerLen    = if ($state.HeaderLen -is [int] -and $state.HeaderLen -ge 0) { [int]$state.HeaderLen } else { 0 }
                        $payloadSent  = [Math]::Max(0, $state.Sent - $headerLen)
                        if ($payloadSent -gt $payloadTotal) { $payloadSent = $payloadTotal }

                        $pp = if ($payloadTotal -gt 0) { ($payloadSent / [double]$payloadTotal) * 100.0 } else { 0.0 }
                        if ($pp -lt 0) { $pp = 0.0 }
                        if ($pp -gt 100) { $pp = 100.0 }

                        Set-TargetProgress $pp
                        $ui.ApplyProgress = $true
                
                        $now = [DateTime]::UtcNow
                        if (($now - $state.LastStatsUpdate).TotalMilliseconds -ge $STATS_UPDATE_INTERVAL_MS) {
                            $state.LastStatsUpdate = $now
                            Update-Statistics
                        }
                    }
            
                    "WaitingAck" {
                        if ($state.Cancelled) {
                            Finish-Send -cancelled $true
                            break
                        }
                
                        $waitMs = [int](([DateTime]::UtcNow - $state.WaitStartUtc).TotalMilliseconds)
                        if ($waitMs -gt $WAIT_ACK_TIMEOUT_MS) {
                            Finish-Send $true
                            break
                        }
                
                        $tSec = ([DateTime]::UtcNow - $state.WaitStartUtc).TotalSeconds
                        if ($tSec -lt 0) { $tSec = 0 }
                        $p = $SEND_PROGRESS_MAX_PCT + (($WAIT_PROGRESS_MAX_BEFORE_ACK - $SEND_PROGRESS_MAX_PCT) * (1.0 - [Math]::Exp(-$tSec / $WAIT_PROGRESS_EASE_TAU_SEC)))
                        if ($p -gt $WAIT_PROGRESS_MAX_BEFORE_ACK) { $p = $WAIT_PROGRESS_MAX_BEFORE_ACK }
                        Set-TargetProgress $p
                        $ui.ApplyProgress = $true
                
                        $ui.StatusText = "Status: waiting for ACK from Spectrum..."
                        $buf = New-Object byte[] 256
                        try {
                            if ($state.Sock -and $state.Sock.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead)) {
                                $r = $state.Sock.Receive($buf, 0, $buf.Length, [System.Net.Sockets.SocketFlags]::None)
                                if ($r -eq 0) {
                                    $state.AckReceived = $false
            $state.Phase = "Finalizing"; $ui.NeedButtons = $true; if ("Finalizing" -eq "Idle") { $state.TransferActive = $false }
                                    $state.CloseObservedUtc = [DateTime]::UtcNow
                                    $ui.StatusText = "Status: peer closed (no ACK). Finalizing..."
                                    break
                                }
                        
                                if ($r -gt 0) {
                                    $gotAck = $false
                                    for ($i = 0; $i -lt $r; $i++) {
                                        if ($buf[$i] -eq 0x06) { $gotAck = $true; break }
                                    }

                                    if (-not $gotAck) {
                                        try {
                                            $txt = [System.Text.Encoding]::ASCII.GetString($buf, 0, $r)
                                            $state.AckBuffer += $txt
                                        } catch {
            $script:LastErrorRecord = $_
            Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
        }

                                        if ($state.AckBuffer.Contains("OK`r`n") -or $state.AckBuffer.Contains("ACK")) {
                                            $gotAck = $true
                                        }
                                    }

                                    if ($gotAck) {
                                        $state.AckReceived = $true
            $state.Phase = "Finalizing"; $ui.NeedButtons = $true; if ("Finalizing" -eq "Idle") { $state.TransferActive = $false }
                                        $state.CloseObservedUtc = [DateTime]::UtcNow
                                        $ui.StatusText = "Status: ACK received. Finalizing..."
                                        break
                                    }
                                }
                            }
                        } catch {
                            $state.AckReceived = $false
            $state.Phase = "Finalizing"; $ui.NeedButtons = $true; if ("Finalizing" -eq "Idle") { $state.TransferActive = $false }
                            $state.CloseObservedUtc = [DateTime]::UtcNow
                            $ui.StatusText = "Status: connection ended (no ACK). Finalizing..."
                            break
                        }
                    }
            
                    "Finalizing" {
                        if ($state.Cancelled) {
                            Finish-Send -cancelled $true
                            break
                        }
                
                        $elapsed = ([DateTime]::UtcNow - $state.CloseObservedUtc).TotalMilliseconds
                        if ($elapsed -lt 0) { $elapsed = 0 }
                
                        $f = [Math]::Min(1.0, $elapsed / [double]$CLOSE_GRACE_DELAY_MS)
                        $p = 95.0 + (4.9 * $f)
                        if ($p -gt 99.9) { $p = 99.9 }
                        Set-TargetProgress $p
                        $ui.ApplyProgress = $true
                
                        if ($state.AckReceived) {
                            $ui.StatusText = "Status: ACK received. Finalizing..."
                        } else {
                            $ui.StatusText = "Status: finalizing..."
                        }
                
                        if ($elapsed -ge $CLOSE_GRACE_DELAY_MS) {
                            Finish-Send $false
                            break
                        }
                    }
                }
        } catch {
        $ui.RequestFail = $true
        # Special-case connection loss (e.g., Wi-Fi drop) to avoid a verbose stack trace.
        $ex = $_.Exception
        $sockEx = $null
        while ($ex -and -not $sockEx) {
            if ($ex -is [System.Net.Sockets.SocketException]) { $sockEx = $ex; break }
            $ex = $ex.InnerException
        }
        if ($sockEx -and ($sockEx.NativeErrorCode -in @(10054,10053,10051,10050,10052))) {
            $ui.FailMessage = "Connection lost during transfer."
            $ui.FailDetail  = ("Socket error {0}: {1}" -f $sockEx.NativeErrorCode, $sockEx.Message)
        } else {
            $ui.FailMessage = "Transfer failed."
            $ui.FailDetail  = $_.Exception.ToString()
        }
    }

    return [pscustomobject]$ui
}

$timer.Add_Tick({
    try {
        $ui = Transfer-EngineTick

        if ($ui.ConnIndicator) {
            switch ($ui.ConnIndicator) {
                "Green" { $picConn.Image = $bmpGreen }
                "Red"   { $picConn.Image = $bmpRed }
                default { $picConn.Image = $bmpGrey }
            }
        }

        if ($ui.StatusText) {
            $lblStatus.Text = $ui.StatusText
        }

        if ($ui.ConnectionTimerAction -eq "Start") {
            # Never probe in the background while a transfer is active (or while not in Idle),
            # to avoid any chance of interfering with the active TCP session.
            if (-not $state.TransferActive -and $state.Phase -eq "Idle") {
                $connectionTimer.Start()
            }
        }

        if ($ui.NeedButtons) {
            Update-Buttons-State
        }

        if ($ui.ApplyProgress) {
            Apply-SmoothedProgress
        }


        Update-TransferPhaseUi
        if ($ui.RequestFail) {
            Fail-AndReset $ui.FailMessage $ui.FailDetail
        }
    } catch {
        $connectionTimer.Start()
        Fail-AndReset "Transfer failed." $_.Exception.ToString()
    }
})

$btnSelect.Add_Click({
    if ($state.Phase -ne "Idle") { return }
    
    if ($openDlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtFile.Text = $openDlg.FileName
        
        $lblStats.Text = "Speed: -- | ETA: -- | Transferred: --/--"
        $state.TransferStartUtc = [DateTime]::MinValue
        $state.Sent = 0
        $state.Total = 0
        $state.TargetProgress = 0
        $state.UiProgress = 0
        $progress.Value = 0

        Refresh-SelectedFileCache
        $k = $state.CachedKind
        
        if ($k) {
            $len = Safe-FileLength $openDlg.FileName
            $lblStatus.Text = ("Status: valid SNA file: {0} ({1} bytes)." -f $k, $len)
        } else {
            $len = Safe-FileLength $openDlg.FileName
            if ($null -ne $len) {
                $lblStatus.Text = ("Status: invalid .sna size ({0} bytes). Expected {1} or {2}." -f $len, $SNA_48K_SIZE, $SNA_128K_SIZE)
            } else {
                $lblStatus.Text = "Status: file not accessible."
            }
        }
        
        Update-Buttons-State
    }
})

$btnSend.Add_Click({
    Start-SendWorkflow
})

$btnCancel.Add_Click({ 
    Cancel-Transfer 
})

$txtIp.Add_TextChanged({
    if ($state.Phase -ne "Idle") { return }

    try { End-ConnectionCheck } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}

    $state.ServerListening = $false
    $state.IpAlive = $false
    $state.PortStatus = "Unknown"
    $state.AppStatus = "Unknown"
    $state.NextAutoConnCheckUtc = [DateTime]::MinValue

    Apply-ConnIndicatorStable -Level "Gray" -TipText "Connection status: Checking new IP..."
    Update-Buttons-State
})

$txtFile.Add_TextChanged({
    if ($state.Phase -ne "Idle") { return }
    Refresh-SelectedFileCache
    Update-Buttons-State
})

$form.Add_FormClosing({
    try { $timer.Stop() } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    try { $connectionTimer.Stop() } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
    try { Cleanup-Connection } catch {
    $script:LastErrorRecord = $_
    Write-Verbose ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
}
})

Apply-ConnIndicatorStable -Level "Gray" -TipText "Connection: Gray=IP unreachable, Yellow=IP reachable (port unknown/closed), Green=port reachable. Click to probe immediately."
$state.IpAlive = $false
$state.PortStatus = "Unknown"
$state.NextAutoConnCheckUtc = [DateTime]::UtcNow

Update-Buttons-State

$connectionTimer.Interval = $CONNECTION_POLL_INTERVAL_MS
$connectionTimer.Start()
Process-ConnectionCheckState

[void]$form.ShowDialog()
