# Importar el módulo de Active Directory
Import-Module ActiveDirectory

# Configuración del dominio y rutas
$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName
$csvPath = "C:\ruta\a\usuarios.csv" # Esta ruta debería actualizarse al ejecutar en el servidor

# Función para asegurar que una OU exista
function Ensure-OUExists {
    param (
        [string]$Name,
        [string]$Path
    )
    $ouDistinguishedName = "OU=$Name,$Path"
    try {
        Get-ADOrganizationalUnit -Identity $ouDistinguishedName -ErrorAction Stop | Out-Null
        Write-Host "La OU '$Name' ya existe."
    } catch {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false
        Write-Host "OU '$Name' creada exitosamente."
    }
}

# 1. Crear las OUs principales: Cuates y No Cuates
Write-Host "Creando OUs..."
Ensure-OUExists -Name "Cuates" -Path $domainDN
Ensure-OUExists -Name "No Cuates" -Path $domainDN

# Función para crear grupos de seguridad si no existen
function Ensure-GroupExists {
    param (
        [string]$GroupName,
        [string]$Path
    )
    try {
        Get-ADGroup -Identity $GroupName -ErrorAction Stop | Out-Null
        Write-Host "El grupo '$GroupName' ya existe."
    } catch {
        New-ADGroup -Name $GroupName -GroupScope Global -Path $Path
        Write-Host "Grupo '$GroupName' creado exitosamente."
    }
}

# Crear grupos para facilitar directivas (opcional, pero buena práctica)
Ensure-GroupExists -GroupName "GrupoCuates" -Path "OU=Cuates,$domainDN"
Ensure-GroupExists -GroupName "GrupoNoCuates" -Path "OU=No Cuates,$domainDN"

# 2. Leer CSV y crear usuarios dinámicamente
Write-Host "Leyendo usuarios desde CSV y creándolos..."
if (Test-Path $csvPath) {
    $users = Import-Csv -Path $csvPath

    foreach ($user in $users) {
        $firstName = $user.Nombre
        $lastName = $user.Apellido
        $samAccountName = $user.Usuario
        $password = ConvertTo-SecureString $user.Password -AsPlainText -Force
        $department = $user.Departamento

        $ouPath = "OU=$department,$domainDN"

        try {
            Get-ADUser -Identity $samAccountName -ErrorAction Stop | Out-Null
            Write-Host "El usuario '$samAccountName' ya existe."
        } catch {
            New-ADUser -Name "$firstName $lastName" `
                       -GivenName $firstName `
                       -Surname $lastName `
                       -SamAccountName $samAccountName `
                       -UserPrincipalName "$samAccountName@$($domain.Name)" `
                       -Path $ouPath `
                       -AccountPassword $password `
                       -Enabled $true `
                       -Department $department `
                       -PasswordNeverExpires $true

            Write-Host "Usuario '$samAccountName' creado exitosamente en OU '$department'."

            # Agregar al grupo correspondiente
            if ($department -eq "Cuates") {
                Add-ADGroupMember -Identity "GrupoCuates" -Members $samAccountName
            } elseif ($department -eq "No Cuates") {
                Add-ADGroupMember -Identity "GrupoNoCuates" -Members $samAccountName
            }
        }
    }
} else {
    Write-Warning "El archivo CSV no fue encontrado en la ruta especificada: $csvPath"
}

# 3. Control de Acceso Temporal (Logon Hours)
Write-Host "Configurando Logon Hours..."

# Función para convertir arreglo de booleanos a bytes para LogonHours
function ConvertTo-LogonHours {
    param([bool[]]$Hours)
    $bytes = New-Object byte[] 21
    for ($i = 0; $i -lt 21; $i++) {
        $byteValue = 0
        for ($j = 0; $j -lt 8; $j++) {
            $index = $i * 8 + $j
            if ($index -lt 168 -and $Hours[$index]) {
                $byteValue += [math]::Pow(2, $j)
            }
        }
        $bytes[$i] = [byte]$byteValue
    }
    return $bytes
}

# Inicializar horarios: Falso en todas las 168 horas (7 días * 24 horas)
$hoursCuates = New-Object bool[] 168
$hoursNoCuates = New-Object bool[] 168

# Horario en AD: Empieza Domingo a las 00:00. AD usa UTC.
# Asumiendo zona horaria UTC para simplicidad en este script.
# Cuates (8:00 AM - 3:00 PM) -> 8 a 15 horas
# No Cuates (3:00 PM - 2:00 AM del día siguiente) -> 15 a 23 horas y 0 a 2 horas

for ($day = 0; $day -lt 7; $day++) {
    for ($hour = 0; $hour -lt 24; $hour++) {
        $index = $day * 24 + $hour

        # Horario Cuates: 08:00 a 14:59 (8-15 excluyendo la 15)
        if ($hour -ge 8 -and $hour -lt 15) {
            $hoursCuates[$index] = $true
        }

        # Horario No Cuates: 15:00 a 01:59 (15-23 y 0-1)
        if ($hour -ge 15 -or $hour -lt 2) {
            $hoursNoCuates[$index] = $true
        }
    }
}

$logonBytesCuates = ConvertTo-LogonHours -Hours $hoursCuates
$logonBytesNoCuates = ConvertTo-LogonHours -Hours $hoursNoCuates

# Aplicar logon hours a los usuarios
if (Test-Path $csvPath) {
    $users = Import-Csv -Path $csvPath
    foreach ($user in $users) {
        $samAccountName = $user.Usuario
        $department = $user.Departamento

        try {
            if ($department -eq "Cuates") {
                Set-ADUser -Identity $samAccountName -Replace @{logonhours=$logonBytesCuates}
            } elseif ($department -eq "No Cuates") {
                Set-ADUser -Identity $samAccountName -Replace @{logonhours=$logonBytesNoCuates}
            }
            Write-Host "Logon hours configurados para $samAccountName."
        } catch {
            Write-Warning "No se pudo configurar Logon Hours para $samAccountName: $($_.Exception.Message)"
        }
    }
}

# 4. GPO: Desconectar al expirar el tiempo de inicio de sesión
Write-Host "Configurando GPO de desconexión por límite de tiempo..."
Import-Module GroupPolicy

$gpoName = "GPO_ForceLogoff_LogonHours"
try {
    Get-GPO -Name $gpoName -ErrorAction Stop | Out-Null
    Write-Host "La GPO '$gpoName' ya existe."
} catch {
    $gpo = New-GPO -Name $gpoName
    Write-Host "GPO '$gpoName' creada exitosamente."

    # Enlazar la GPO al dominio
    New-GPLink -Name $gpoName -Target $domainDN -LinkEnabled Yes | Out-Null
    Write-Host "GPO enlazada al dominio."

    # Configurar la directiva "Seguridad de red: cerrar la sesión de los usuarios cuando expire el tiempo de inicio de sesión"
    # Esta directiva se mapea a un registro en Políticas de seguridad local.
    # Como es complejo hacerlo directamente con Set-GPRegistryValue, comúnmente se requiere una plantilla de seguridad o configurarlo en el controlador de dominio.
    # Aquí simulamos la configuración de la política de seguridad a través de un script secpol.

    $infPath = "$env:TEMP\secpol.inf"
    @"
[Unicode]
Unicode=yes
[System Access]
ForceLogoffWhenHourExpire = 1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@ | Out-File -FilePath $infPath -Encoding Unicode

    # Aplicar la configuración de seguridad local al servidor actual (Controlador de Dominio)
    try {
        secedit.exe /configure /db $env:windir\security\local.sdb /cfg $infPath /areas USER_RIGHTS SECURITYPOLICY
        Write-Host "Se ha configurado la política local de seguridad para forzar el logoff."
    } catch {
        Write-Warning "Ocurrió un error al intentar aplicar la política con secedit: $($_.Exception.Message)"
    }
}

# 5. Gestión de Almacenamiento Estricto (FSRM)
Write-Host "Configurando FSRM (Cuotas y Filtrado de archivos)..."
# Asegurar que FSRM esté instalado
try {
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools | Out-Null
} catch {
    Write-Warning "No se pudo instalar la característica FSRM o ya estaba instalada."
}

Import-Module FileServerResourceManager

$baseFolder = "C:\CarpetasPersonales"
if (-not (Test-Path $baseFolder)) {
    New-Item -ItemType Directory -Path $baseFolder | Out-Null
    Write-Host "Directorio base $baseFolder creado."
}

# Crear carpetas personales y aplicar cuotas
if (Test-Path $csvPath) {
    $users = Import-Csv -Path $csvPath
    foreach ($user in $users) {
        $samAccountName = $user.Usuario
        $department = $user.Departamento
        $userFolder = Join-Path $baseFolder $samAccountName

        if (-not (Test-Path $userFolder)) {
            New-Item -ItemType Directory -Path $userFolder | Out-Null
        }

        # Determinar tamaño de cuota
        if ($department -eq "Cuates") {
            $quotaSize = 10MB
        } else {
            $quotaSize = 5MB
        }

        try {
            $existingQuota = Get-FsrmQuota -Path $userFolder -ErrorAction SilentlyContinue
            if (-not $existingQuota) {
                New-FsrmQuota -Path $userFolder -Size $quotaSize -Description "Cuota para $samAccountName" -SoftLimit:$false
                Write-Host "Cuota de $quotaSize configurada para $samAccountName en $userFolder."
            } else {
                Set-FsrmQuota -Path $userFolder -Size $quotaSize
                Write-Host "Cuota de $quotaSize actualizada para $samAccountName en $userFolder."
            }
        } catch {
            Write-Warning "Error al configurar cuota para $samAccountName: $($_.Exception.Message)"
        }
    }
}

# Configurar Apantallamiento de Archivos (Active Screening)
$fileGroupName = "Archivos Bloqueados Tarea08"
try {
    Get-FsrmFileGroup -Name $fileGroupName -ErrorAction Stop | Out-Null
    Write-Host "Grupo de archivos '$fileGroupName' ya existe."
} catch {
    New-FsrmFileGroup -Name $fileGroupName -IncludePattern @("*.mp3", "*.mp4", "*.exe", "*.msi")
    Write-Host "Grupo de archivos '$fileGroupName' creado."
}

# Aplicar el filtro a la carpeta base (se hereda a las subcarpetas)
try {
    $existingScreen = Get-FsrmFileScreen -Path $baseFolder -ErrorAction SilentlyContinue
    if (-not $existingScreen) {
        New-FsrmFileScreen -Path $baseFolder -IncludeGroup $fileGroupName -Active:$true
        Write-Host "Filtro de archivos aplicado en $baseFolder bloqueando mp3, mp4, exe, msi."
    } else {
        Write-Host "El filtro de archivos ya está aplicado en $baseFolder."
    }
} catch {
    Write-Warning "Error al aplicar filtro de archivos: $($_.Exception.Message)"
}

# 6. Control de Ejecución con AppLocker
Write-Host "Configurando AppLocker..."
Import-Module AppLocker

# Ruta del bloc de notas
$notepadPath = "C:\Windows\System32\notepad.exe"

# Obtener información del archivo (incluye el hash)
$notepadInfo = Get-AppLockerFileInformation -Path $notepadPath

# Crear regla de Permitir para "Cuates" (Usamos el grupo de seguridad)
$ruleCuates = New-AppLockerPolicy -RuleType Hash -User "GrupoCuates" -Action Allow -FileInformation $notepadInfo

# Crear regla de Bloquear para "No Cuates" (Usamos el grupo de seguridad)
$ruleNoCuates = New-AppLockerPolicy -RuleType Hash -User "GrupoNoCuates" -Action Deny -FileInformation $notepadInfo

# Obtener una GPO para AppLocker
$appLockerGPOName = "GPO_AppLocker_Notepad"
$gpo = $null
try {
    $gpo = Get-GPO -Name $appLockerGPOName -ErrorAction Stop
} catch {
    $gpo = New-GPO -Name $appLockerGPOName
    New-GPLink -Name $appLockerGPOName -Target $domainDN -LinkEnabled Yes | Out-Null
}

# Obtener la ruta LDAP de la GPO
$gpoLdapPath = "LDAP://$($domain.Name)/CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"

try {
    # Combinar reglas en una política de memoria
    $combinedPolicy = Set-AppLockerPolicy -PolicyObject $ruleCuates -Merge -PassThru
    # Como -Merge acepta otro objeto de política, fusionamos la de NoCuates con la combinada actual temporalmente, o aplicamos ambas a la GPO una a una

    # Aplicar la regla de Cuates a la GPO
    Set-AppLockerPolicy -Ldap $gpoLdapPath -PolicyObject $ruleCuates -Merge
    # Aplicar la regla de No Cuates a la GPO (fusionando con lo que ya tiene la GPO)
    Set-AppLockerPolicy -Ldap $gpoLdapPath -PolicyObject $ruleNoCuates -Merge

    Write-Host "Reglas de AppLocker configuradas en GPO '$appLockerGPOName' para Notepad."
} catch {
    Write-Warning "Ocurrió un error al aplicar las reglas de AppLocker en la GPO: $($_.Exception.Message)"
}

Write-Host "Script de Servidor completado."
