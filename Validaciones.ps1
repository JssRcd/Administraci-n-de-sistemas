function Test-IPUsable {
    param([string]$IP)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $true }
    
    # Validar formato de IP
    if ($IP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        Write-Host "[!] ERROR: '$IP' no es un formato de IP valido." -ForegroundColor Red
        return $false
    }

    # Bloqueo de Localhost (127.x.x.x)
    if ($IP -like "127.*") {
        Write-Host "[!] ERROR: No se permite el uso de Localhost." -ForegroundColor Red
        return $false
    }

    # Bloqueo de Broadcast (255)
    if ($IP.EndsWith(".255")) {
        Write-Host "[!] ERROR: La IP $IP es de broadcast y no es usable." -ForegroundColor Red
        return $false
    }
    return $true
}

function Test-EntradaValida {
    param([string]$Ini, [string]$Fin, [string]$Gw, [string]$Dns)
    foreach ($ip in @($Ini, $Fin, $Gw, $Dns)) {
        if (-not (Test-IPUsable $ip)) { return $false }
    }
    return $true
}
