#!/bin/bash

# Variables
DOMAIN="tu.dominio.local" # Cambiar por tu dominio real
ADMIN_USER="Administrador" # O el usuario admin de tu dominio

# Comprobación de root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root."
  # quit
fi

echo "Instalando paquetes necesarios: realmd, sssd, adcli..."
# Detectar gestor de paquetes (apt para debian/ubuntu, dnf/yum para RHEL/CentOS)
if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y realmd sssd sssd-tools adcli krb5-user packagekit sudo libnss-sss libpam-sss
elif command -v dnf &> /dev/null; then
    dnf install -y realmd sssd adcli krb5-workstation oddjob oddjob-mkhomedir samba-common-tools
elif command -v yum &> /dev/null; then
    yum install -y realmd sssd adcli krb5-workstation oddjob oddjob-mkhomedir samba-common-tools
else
    echo "No se pudo detectar el gestor de paquetes. Por favor instala realmd, sssd y adcli manualmente."
    # quit
fi

echo "Uniendo el equipo al dominio $DOMAIN..."
realm discover $DOMAIN
realm join -U $ADMIN_USER $DOMAIN

if [ $? -ne 0 ]; then
    echo "Error al unir al dominio. Comprueba las credenciales o la conectividad."
    # quit
fi
echo "Equipo unido exitosamente al dominio."

# Configurar sssd.conf
SSSD_CONF="/etc/sssd/sssd.conf"
echo "Configurando $SSSD_CONF para el fallback_homedir..."

# Asegurar que el archivo exista antes de modificar
if [ -f "$SSSD_CONF" ]; then
    # Reemplazar cualquier fallback_homedir existente o agregarlo en la sección del dominio
    if grep -q "fallback_homedir" "$SSSD_CONF"; then
        sed -i "s|fallback_homedir = .*|fallback_homedir = /home/%u@%d|g" "$SSSD_CONF"
    else
        sed -i "/\[domain\/$DOMAIN\]/a fallback_homedir = /home/%u@%d" "$SSSD_CONF"
    fi

    # Reiniciar sssd para aplicar cambios
    systemctl restart sssd
    echo "sssd.conf configurado y servicio reiniciado."
else
    echo "Advertencia: No se encontró $SSSD_CONF. Verifica la instalación de sssd."
fi

# Permisos de sudo
SUDOERS_FILE="/etc/sudoers.d/ad-admins"
echo "Configurando permisos de sudo para los administradores del dominio en $SUDOERS_FILE..."
echo "%domain\ admins@$DOMAIN ALL=(ALL) ALL" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

echo "Configuración de cliente Linux finalizada."
