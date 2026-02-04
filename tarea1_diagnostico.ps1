# Script de diagnóstico - Nodos Windows
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  DIAGNÓSTICO: $env:COMPUTERNAME"
Write-Host "=========================================="

# Filtra la IP del segmento 10.0.5.x definido en la práctica
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "10.0.5.*" }).IPAddress
Write-Host "Dirección IP Interna:  $($ip -join ', ')"

# Calcula el espacio libre en GB redondeado
$disco = Get-PSDrive C | Select-Object @{n='LibreGB';e={[math]::Round($_.Free/1GB,2)}}
Write-Host "Espacio Libre en C:    $($disco.LibreGB) GB"

Write-Host "=========================================="
