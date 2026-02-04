#!/bin/bash
# Script de diagnóstico - Nodo Linux (Fedora)
echo "=========================================="
echo "  DIAGNÓSTICO: $(hostname)"
echo "=========================================="

# Extrae la IP de la interfaz de red interna
IP_INT=$(ip -4 addr show ens192 | grep inet | awk '{print $2}' | cut -d/ -f1)
echo "Dirección IP Interna:  ${IP_INT:-'No detectada'}"

# Muestra el espacio disponible en la raíz
DISK=$(df -h / | awk 'NR==2 {print $4}')
echo "Espacio en Disco:      $DISK disponible"

echo "=========================================="
