#!/bin/bash

# --- VARIABLES GLOBALES ---
LOG_HISTORIAL="/var/log/dhcp_gestion_acciones.log"
INTERFAZ="ens192"  # Adaptador 2 detectado en image_e72446
CONF_FILE="/etc/dhcp/dhcpd.conf"
LEASES_FILE="/var/lib/dhcpd/dhcpd.leases"

# --- FUNCIONES DE APOYO ---
registrar_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_HISTORIAL" > /dev/null
}

validar_ip() {
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
}

# --- LÓGICA DE OPCIONES ---

while true; do
    clear
    # Menú con el formato exacto de Windows
    echo -e "\e[36m=== ADMIN DHCP FEDORA (Versión Corregida) ===\e[0m"
    echo "1. Estado | 2. Instalar | 3. Ambito | 4. Monitoreo | 5. Detener | 6. Limpiar | 7. Salir"
    read -p "$(echo -e "\nSeleccione una opcion: ")" op

    case $op in
        1) # ESTADO
            clear
            echo -e "\e[36m=== ESTADO DEL SERVICIO ===\e[0m"
            if rpm -q dhcp-server &> /dev/null; then
                systemctl is-active dhcpd --quiet && echo -e "\e[32mEstado: Activo\e[0m" || echo -e "\e[31mEstado: Inactivo\e[0m"
                echo -e "\n--- Configuración de Red ---"
                ip addr show $INTERFAZ | grep "inet " || echo "Interfaz $INTERFAZ sin IP"
                echo -e "\n--- Configuración DHCP ---"
                [ -f "$CONF_FILE" ] && cat "$CONF_FILE" || echo "Sin configuración"
            else
                echo -e "\e[31mDHCP no instalado.\e[0m"
            fi
            read -p "Presione Enter para continuar..." ;;

        2) # INSTALAR
            clear
            echo -e "\e[33mInstalando rol DHCP...\e[0m"
            sudo dnf install -y dhcp-server
            
            # Configurar firewall
            echo -e "\e[33mConfigurando firewall...\e[0m"
            sudo firewall-cmd --permanent --add-service=dhcp 2>/dev/null
            sudo firewall-cmd --reload 2>/dev/null
            
            echo -e "\e[32m[+] Instalacion completada.\e[0m"
            registrar_log "Servidor instalado"
            read -p "Presione Enter para continuar..." ;;

        3) # AMBITO (Corregido)
            clear
            echo -e "\e[36m=== CONFIGURACION DE AMBITO ===\e[0m"
            read -p "IP Inicial (ej. 192.168.20.0): " ini
            read -p "IP Final: " fin
            read -p "Gateway: " gw
            read -p "DNS (Opcional, default 8.8.8.8): " dns
            [[ -z "$dns" ]] && dns="8.8.8.8"

            # Lógica de sumatoria automática para evitar error .0
            ultimo=$(echo $ini | cut -d. -f4)
            if [ "$ultimo" -lt 3 ]; then
                IPI_POOL="$(echo $ini | cut -d. -f1-3).3"
                echo -e "\e[90m[i] Ajustando inicio de rango a .3 para estabilidad...\e[0m"
            else
                IPI_POOL=$ini
            fi

            if validar_ip $ini && validar_ip $fin; then
                seg_base=$(echo $ini | cut -d. -f1-3)
                srvIP="$seg_base.2"

                # CORREGIDO: Obtener nombre de la conexión
                CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep "$INTERFAZ" | cut -d: -f1 | head -1)
                
                if [ -z "$CONN_NAME" ]; then
                    echo -e "\e[33mCreando nueva conexión para $INTERFAZ...\e[0m"
                    CONN_NAME="dhcp-server-$INTERFAZ"
                    sudo nmcli connection add type ethernet con-name "$CONN_NAME" ifname "$INTERFAZ" \
                        ipv4.addresses "$srvIP/24" ipv4.method manual
                else
                    echo -e "\e[33mModificando conexión existente: $CONN_NAME...\e[0m"
                    sudo nmcli connection modify "$CONN_NAME" ipv4.addresses "$srvIP/24" ipv4.method manual
                fi
                
                sudo nmcli connection up "$CONN_NAME" 2>/dev/null
                sleep 2
                
                # Configurar Escucha
                echo "DHCPDARGS=\"$INTERFAZ\"" | sudo tee /etc/sysconfig/dhcpd > /dev/null

                # CORREGIDO: Generar dhcpd.conf con todos los parámetros necesarios
                {
                    echo "# Configuración DHCP generada automáticamente"
                    echo "default-lease-time 600;"
                    echo "max-lease-time 7200;"
                    echo "authoritative;"
                    echo ""
                    echo "subnet $seg_base.0 netmask 255.255.255.0 {"
                    echo "  range $IPI_POOL $fin;"
                    [[ -n "$gw" ]] && echo "  option routers $gw;"
                    echo "  option subnet-mask 255.255.255.0;"
                    echo "  option broadcast-address $seg_base.255;"
                    echo "  option domain-name-servers $dns;"
                    echo "}"
                } | sudo tee $CONF_FILE > /dev/null

                # Crear archivo de leases si no existe
                sudo touch $LEASES_FILE
                sudo chown dhcpd:dhcpd $LEASES_FILE 2>/dev/null
                
                # Reiniciar servicio
                echo -e "\e[33mReiniciando servicio DHCP...\e[0m"
                sudo systemctl enable dhcpd 2>/dev/null
                sudo systemctl restart dhcpd
                sleep 2
                
                # Verificar estado
                if systemctl is-active --quiet dhcpd; then
                    echo -e "\e[32m✓ Ambito $seg_base.0 creado exitosamente.\e[0m"
                    echo -e "\e[32m✓ Servidor DHCP: $srvIP\e[0m"
                    echo -e "\e[32m✓ Rango: $IPI_POOL - $fin\e[0m"
                    registrar_log "Ambito creado: $seg_base.0"
                else
                    echo -e "\e[31m✗ Error al iniciar el servicio.\e[0m"
                    echo -e "\e[33mRevisando logs...\e[0m"
                    sudo journalctl -u dhcpd -n 20 --no-pager
                fi
            else
                echo -e "\e[31mIP inválida.\e[0m"
            fi
            read -p "Presione Enter para continuar..." ;;

        4) # MONITOREO (Tiempo real)
            clear
            echo -e "\e[36m=== CONCESIONES ACTUALES ===\e[0m"
            echo -e "Presione Ctrl+C para volver al menú\n"
            
            while true; do
                clear
                echo -e "\e[36m=== CONCESIONES ACTUALES (Actualizando cada 3s) ===\e[0m\n"
                
                if [ -s "$LEASES_FILE" ]; then
                    # Mostrar leases activos
                    echo -e "\e[33m%-16s %-18s %-20s %s\e[0m" "IP" "MAC" "Hostname" "Estado"
                    echo "-------------------------------------------------------------------------------"
                    
                    sudo awk '
                    /^lease/ { ip = $2 }
                    /hardware ethernet/ { mac = $3; gsub(";", "", mac) }
                    /client-hostname/ { host = $2; gsub("[;\"]", "", host) }
                    /binding state/ { state = $3; gsub(";", "", state) }
                    /}/ && ip { 
                        printf "%-16s %-18s %-20s %s\n", ip, mac, host, state
                        ip = mac = host = state = ""
                    }
                    ' "$LEASES_FILE" | tail -n 20
                    
                    echo -e "\n\e[32mTotal de concesiones: $(grep -c "^lease" "$LEASES_FILE")\e[0m"
                else
                    echo -e "\e[33mEsperando clientes...\e[0m"
                fi
                
                echo -e "\n\e[90m[i] Estado del servicio:\e[0m"
                systemctl is-active dhcpd --quiet && echo -e "\e[32m● Activo\e[0m" || echo -e "\e[31m● Inactivo\e[0m"
                
                sleep 3
            done ;;

        5) # DETENER
            clear
            echo -e "\e[36m=== DETENER SERVICIO DHCP ===\e[0m"
            sudo systemctl stop dhcpd
            echo -e "\e[32m[+] El servicio se ha detenido correctamente.\e[0m"
            registrar_log "Servicio detenido manualmente"
            read -p "Presione Enter para continuar..." ;;

        6) # LIMPIAR (Desinstalar completamente)
            clear
            echo -e "\e[33mIniciando limpieza total del servicio DHCP...\e[0m"
            
            # Detener y deshabilitar servicio
            sudo systemctl stop dhcpd &> /dev/null
            sudo systemctl disable dhcpd &> /dev/null
            
            # Eliminar archivos de configuración
            sudo rm -f $CONF_FILE
            sudo rm -f $LEASES_FILE
            sudo rm -f /etc/sysconfig/dhcpd
            
            # Desinstalar el paquete
            echo -e "\e[33mDesinstalando paquete dhcp-server...\e[0m"
            sudo dnf remove -y dhcp-server &> /dev/null
            
            # Eliminar regla de firewall
            sudo firewall-cmd --permanent --remove-service=dhcp 2>/dev/null
            sudo firewall-cmd --reload 2>/dev/null
            
            echo -e "\e[32m[+] Servicio DHCP completamente eliminado.\e[0m"
            registrar_log "Limpieza total: servicio desinstalado"
            read -p "Presione Enter para continuar..." ;;

        7) # SALIR (Restablecer 10.0.5.10)
            clear
            echo -e "\e[33mRestableciendo configuracion original de red...\e[0m"
            
            # Buscar la conexión existente
            CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep "$INTERFAZ" | cut -d: -f1 | head -1)
            
            if [ -n "$CONN_NAME" ]; then
                sudo nmcli connection modify "$CONN_NAME" ipv4.addresses "10.0.5.10/24" \
                    ipv4.gateway "10.0.5.1" ipv4.method manual
                sudo nmcli connection up "$CONN_NAME" &> /dev/null
            fi
            
            echo -e "\e[32m[+] Red restablecida exitosamente.\e[0m"
            echo -e "\e[32m[+] Saliendo del sistema...\e[0m"
            sleep 2
            exit 0 ;;
            
        *)
            echo -e "\e[31mOpcion invalida.\e[0m"
            sleep 1 ;;
    esac
done
