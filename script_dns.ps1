. .\Validaciones.ps1

# Importamos el modulo por si el rol ya estaba instalado desde antes
Import-Module DnsServer -ErrorAction SilentlyContinue

do {
    Clear-Host
    Write-Host "=== ADMIN DNS WINDOWS ===" -ForegroundColor Cyan
    Write-Host "1. Estado | 2. Instalar | 3. Nueva Zona | 4. Forwarders | 5. Eliminar | 6. Consultar | 7. Salir"
    $op = Read-Host "`nSeleccione una opcion"

    switch ($op) {
        "1" { 
            Clear-Host
            Write-Host "=== ESTADO DEL SERVICIO ===" -ForegroundColor Cyan
            $srv = Get-Service DNS -ErrorAction SilentlyContinue
            if ($null -eq $srv) { 
                Write-Host "DNS no instalado o servicio apagado." -ForegroundColor Red 
            } else { 
                Write-Host "Estado: $($srv.Status)" -ForegroundColor Green 
                
                Import-Module DnsServer -ErrorAction SilentlyContinue
                $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue | Where-Object { $_.ZoneName -notlike "*arpa" -and $_.ZoneName -ne "TrustAnchors" }
                if ($zonas) {
                    Write-Host "`nZonas configuradas:" -ForegroundColor Yellow
                    $zonas | Select-Object ZoneName | Format-Table -HideTableHeaders
                } else {
                    Write-Host "`n(No hay zonas configuradas)" -ForegroundColor Gray
                }
            }
            Pause 
        }

        "2" {
            Clear-Host
            Write-Host "=== INSTALACION DE ROL DNS ===" -ForegroundColor Cyan
            
            $check = Get-WindowsFeature DNS -ErrorAction SilentlyContinue
            if ($check.Installed) {
                Write-Host "[i] El rol DNS ya se encuentra instalado en este servidor." -ForegroundColor Yellow
            } else {
                Write-Host "Instalando rol DNS, por favor espere..." -ForegroundColor Yellow
                
                # Sin el silenciador para poder ver la barra de progreso
                Install-WindowsFeature DNS -IncludeManagementTools
                Write-Host "`nConfigurando el entorno..." -ForegroundColor Gray
            }

            # TRUCO VITAL: Obligamos a cargar el "diccionario" de DNS en esta ventana
            Import-Module DnsServer -ErrorAction SilentlyContinue
            
            # Forzamos el encendido del servicio
            Start-Service DNS -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            
            # Verificacion automatica
            $srv = Get-Service DNS -ErrorAction SilentlyContinue
            if ($srv -and $srv.Status -eq 'Running') {
                Write-Host "[+] Instalacion completada. Servicio DNS en ejecucion." -ForegroundColor Green
            } else {
                Write-Host "[!] El rol se instalo, pero el servicio no arranco automaticamente." -ForegroundColor Red
            }
            Pause
        }

        "3" {
            Clear-Host
            Write-Host "=== CONFIGURACION DE ZONA ===" -ForegroundColor Cyan
            
            # Aseguramos que los comandos existan antes de preguntar
            Import-Module DnsServer -ErrorAction SilentlyContinue

            $dom = Read-Host "Nombre del dominio (ej. local.com)"
            $ip  = Read-Host "IP Destino"

            if ($dom -and $ip) {
                Write-Host "`n[i] Creando registros..." -ForegroundColor Gray
                
                # Obtiene la IP actual del servidor en la Ethernet1 para el NS1
                $srvIP = (Get-NetIPAddress -InterfaceAlias "Ethernet1" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress[0]

                try {
                    if (!(Get-DnsServerZone -Name $dom -ErrorAction SilentlyContinue)) {
                        Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction Stop
                        if ($srvIP) { Add-DnsServerResourceRecordA -ZoneName $dom -Name "ns1" -IPv4Address $srvIP -ErrorAction SilentlyContinue | Out-Null }
                    }
                    
                    Add-DnsServerResourceRecordA -ZoneName $dom -Name "@" -IPv4Address $ip -ErrorAction SilentlyContinue | Out-Null
                    Add-DnsServerResourceRecordA -ZoneName $dom -Name "www" -IPv4Address $ip -ErrorAction SilentlyContinue | Out-Null

                    Restart-Service DNS -Force -WarningAction SilentlyContinue
                    Write-Host "[+] Dominio $dom configurado correctamente apuntando a $ip." -ForegroundColor Green
                } catch {
                    Write-Host "[!] Error al crear la zona. Verifica que el rol este instalado (Opcion 2)." -ForegroundColor Red
                }
            } else {
                Write-Host "[!] Faltan datos para crear la zona." -ForegroundColor Red
            }
            Pause
        }

        "4" {
            Clear-Host
            Write-Host "=== CONFIGURACION DE FORWARDERS ===" -ForegroundColor Cyan
            Import-Module DnsServer -ErrorAction SilentlyContinue

            $fwd = Read-Host "IP del Reenviador (ej. 8.8.8.8)"
            
            if ($fwd) {
                Write-Host "`n[i] Aplicando reenviador..." -ForegroundColor Gray
                try {
                    Set-DnsServerForwarder -IPAddress $fwd -PassThru -ErrorAction Stop | Out-Null
                    Restart-Service DNS -Force -WarningAction SilentlyContinue
                    Write-Host "[+] Forwarder $fwd configurado correctamente." -ForegroundColor Green
                } catch {
                    Write-Host "[!] Error al configurar el reenviador." -ForegroundColor Red
                }
            }
            Pause
        }

        "5" { 
            Clear-Host
            Write-Host "=== ELIMINAR ZONA ===" -ForegroundColor Cyan
            Import-Module DnsServer -ErrorAction SilentlyContinue

            $dom = Read-Host "Nombre del dominio a eliminar"
            
            if ($dom) {
                try {
                    Remove-DnsServerZone -Name $dom -Force -ErrorAction Stop
                    Write-Host "`n[+] Zona $dom eliminada del sistema." -ForegroundColor Green
                } catch {
                    Write-Host "`n[!] No se pudo eliminar la zona. Verifica que exista el dominio." -ForegroundColor Red
                }
            }
            Pause 
        }

        "6" { 
            Clear-Host
            Write-Host "=== PRUEBA DE RESOLUCION MASIVA ===" -ForegroundColor Cyan
            Import-Module DnsServer -ErrorAction SilentlyContinue

            # Filtramos las zonas para omitir las reservadas del sistema
            $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue | Where-Object { $_.ZoneName -notlike "*arpa" -and $_.ZoneName -ne "TrustAnchors" }
            
            if ($zonas) {
                Write-Host "Consultando todos los dominios registrados localmente...`n" -ForegroundColor Yellow
                
                foreach ($zona in $zonas) {
                    Write-Host ">>> Resolviendo: $($zona.ZoneName)" -ForegroundColor Green
                    Resolve-DnsName $zona.ZoneName -ErrorAction SilentlyContinue | Format-Table -AutoSize
                }
            } else {
                Write-Host "[i] No hay dominios registrados en el servidor para consultar." -ForegroundColor Gray
            }
            Pause 
        }
    }
} while ($op -ne "7") 

Clear-Host
Write-Host "[+] Saliendo del sistema DNS..." -ForegroundColor Green
Start-Sleep 2
