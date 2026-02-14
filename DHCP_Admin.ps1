. .\Validaciones.ps1

do {
    Clear-Host
    Write-Host "=== ADMIN DHCP WINDOWS ===" -ForegroundColor Cyan
    Write-Host "1. Estado | 2. Instalar | 3. Ambito | 4. Monitoreo | 5. Detener | 6. Limpiar | 7. Salir"
    $op = Read-Host "`nSeleccione una opcion"

    switch ($op) {
        "1" { 
            Clear-Host
            Write-Host "=== ESTADO DEL SERVICIO ===" -ForegroundColor Cyan
            $srv = Get-Service dhcpserver -ErrorAction SilentlyContinue
            if ($null -eq $srv) { 
                Write-Host "DHCP no instalado." -ForegroundColor Red 
            } else { 
                Write-Host "Estado: $($srv.Status)" -ForegroundColor Green 
            }
            Pause 
        }

        "2" {
            Clear-Host
            Write-Host "Instalando rol DHCP..." -ForegroundColor Yellow
            Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
            Write-Host "[+] Instalacion completada." -ForegroundColor Green
            Pause
        }

        "3" {
            Clear-Host
            Write-Host "=== CONFIGURACION DE AMBITO ===" -ForegroundColor Cyan
            $ini = Read-Host "IP Inicial"
            $fin = Read-Host "IP Final"
            $gw  = Read-Host "Gateway"
            $dns = Read-Host "DNS"

            
            $octetos = $ini.Split('.')
            if ([int]$octetos[3] -lt 3) {
                $ini = "$($octetos[0]).$($octetos[1]).$($octetos[2]).3"
                Write-Host "[i] Ajustando rango para estabilidad..." -ForegroundColor Gray
            }

            if (Test-EntradaValida $ini $fin $gw $dns) {
                $seg = $ini.Substring(0, $ini.LastIndexOf('.'))
                $srvIP = "$seg.2"

                Remove-NetIPAddress -InterfaceAlias "Ethernet1" -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceAlias "Ethernet1" -IPAddress $srvIP -PrefixLength 24 | Out-Null

                Restart-Service dhcpserver -Force -WarningAction SilentlyContinue
                Start-Sleep 3

                $netId = "$seg.0"
                Add-DhcpServerv4Scope -Name "Dinamico" -StartRange $ini -EndRange $fin -SubnetMask 255.255.255.0 -ErrorAction SilentlyContinue
                
                if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $netId -OptionId 3 -Value $gw -ErrorAction SilentlyContinue }
                
                # Se usa -Force para que acepte DNS externo sin errores
                if ($dns) { 
                    Set-DhcpServerv4OptionValue -ScopeId $netId -OptionId 6 -Value $dns -Force -ErrorAction SilentlyContinue 
                }
                
                Write-Host "`n[+] Ambito $netId configurado correctamente." -ForegroundColor Green
            }
            Pause
        }

        "4" {
            Clear-Host
            Write-Host "=== CONCESIONES ACTUALES ===" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | ForEach-Object {
                $leases = Get-DhcpServerv4Lease -ScopeId $_.ScopeId -ErrorAction SilentlyContinue
                if ($null -ne $leases) {
                    Write-Host "`n[ Red: $($_.ScopeId) ]" -ForegroundColor Green
                    $leases | Select-Object IPAddress, HostName, AddressState | Format-Table -AutoSize
                }
            }
            Read-Host "`nPresione Enter para volver al menu..."
        }

        "5" { 
            Clear-Host
            Write-Host "=== DETENER SERVICIO DHCP ===" -ForegroundColor Cyan
            Stop-Service dhcpserver -Force -ErrorAction SilentlyContinue
            Write-Host "[+] El servicio se ha detenido correctamente." -ForegroundColor Green
            Pause 
        }

        "6" { 
            Clear-Host
            Write-Host "Iniciando limpieza total..." -ForegroundColor Yellow
            Stop-Service dhcpserver -Force -ErrorAction SilentlyContinue
            Uninstall-WindowsFeature DHCP | Out-Null
            if (Test-Path "C:\Windows\System32\dhcp") { 
                Remove-Item "C:\Windows\System32\dhcp\*" -Recurse -Force 
            }
            Write-Host "Sistema limpio (Base de datos borrada)." -ForegroundColor Green
            Pause 
        }
    }
} while ($op -ne "7") 

Clear-Host
Write-Host "Restableciendo configuracion original de red..." -ForegroundColor Yellow

# 1. Limpieza profunda: quitamos todas las IPs y Gateways de la tarjeta
Remove-NetIPAddress -InterfaceAlias "Ethernet1" -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias "Ethernet1" -NextHop "10.0.5.1" -Confirm:$false -ErrorAction SilentlyContinue

# 2. Se aplica la configuración original sin conflictos
New-NetIPAddress -InterfaceAlias "Ethernet1" -IPAddress "10.0.5.20" -PrefixLength 24 -DefaultGateway "10.0.5.1" | Out-Null

Write-Host "[+] Red restablecida exitosamente." -ForegroundColor Green
Write-Host "[+] Saliendo del sistema..." -ForegroundColor Green
Start-Sleep 2
