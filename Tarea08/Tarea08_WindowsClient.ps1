# Script para unir Windows al dominio

$domainName = "tu.dominio.local" # Cambiar por el nombre del dominio real
$domainCredential = Get-Credential -Message "Ingrese las credenciales del administrador del dominio"

Write-Host "Iniciando proceso de unión al dominio $domainName..."

try {
    Add-Computer -DomainName $domainName -Credential $domainCredential -Restart -Force
    Write-Host "Equipo unido al dominio exitosamente. Reiniciando..."
} catch {
    Write-Warning "Ocurrió un error al intentar unir el equipo al dominio: $($_.Exception.Message)"
}
