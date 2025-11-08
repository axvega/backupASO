#!/bin/bash
# Script de restauración del sistema

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root"
    echo "Ejecuta: sudo $0"
    exit 1
fi

BACKUP_BASE="/backup"
BACKUP_DAILY="$BACKUP_BASE/daily"
BACKUP_WEEKLY="$BACKUP_BASE/weekly" 
BACKUP_MONTHLY="$BACKUP_BASE/monthly"

listar_backups() {
    echo ""
    echo "BACKUPS DISPONIBLES PARA RESTAURAR"
    echo "=================================="
    
    if [ -d "$BACKUP_DAILY" ] && [ "$(ls -A $BACKUP_DAILY 2>/dev/null)" ]; then
        echo ""
        echo "BACKUPS DIARIOS:"
        ls -la "$BACKUP_DAILY"
    fi
    
    if [ -d "$BACKUP_WEEKLY" ] && [ "$(ls -A $BACKUP_WEEKLY 2>/dev/null)" ]; then
        echo ""
        echo "BACKUPS SEMANALES:"
        ls -la "$BACKUP_WEEKLY"
    fi
    
    if [ -d "$BACKUP_MONTHLY" ] && [ "$(ls -A $BACKUP_MONTHLY 2>/dev/null)" ]; then
        echo ""
        echo "BACKUPS MENSUALES:"
        ls -la "$BACKUP_MONTHLY"
    fi
    
    if [ ! -d "$BACKUP_DAILY" ] && [ ! -d "$BACKUP_WEEKLY" ] && [ ! -d "$BACKUP_MONTHLY" ]; then
        echo "No hay backups disponibles"
        exit 1
    fi
}

listar_backups

echo ""
echo "SELECCION DE BACKUP A RESTAURAR"
echo "==============================="
echo ""
echo "Introduce la ruta completa del backup a restaurar:"
echo "(Ejemplo: /backup/daily/backup_2025-10-16_01-00-00)"
echo ""
read -r BACKUP_SELECCIONADO

if [ ! -d "$BACKUP_SELECCIONADO" ]; then
    echo "ERROR: El directorio $BACKUP_SELECCIONADO no existe"
    exit 1
fi

if [ ! -f "$BACKUP_SELECCIONADO/paquetes_instalados.txt" ]; then
    echo "ERROR: Backup incompleto. Falta paquetes_instalados.txt"
    exit 1
fi

echo ""
echo "ADVERTENCIA: Estás a punto de restaurar el sistema desde:"
echo "$BACKUP_SELECCIONADO"
echo ""
echo "Esto sobrescribirá archivos actuales del sistema."
echo "Se recomienda hacer un backup del estado actual primero."
echo ""
read -p "¿Deseas continuar? (escribe 'SI' en mayúsculas): " confirmacion

if [ "$confirmacion" != "SI" ]; then
    echo "Restauración cancelada."
    exit 0
fi

LOG_FILE="/var/log/restauracion_$(date +%Y%m%d_%H%M%S).log"
echo "Creando log en: $LOG_FILE"
echo ""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "INICIANDO RESTAURACION DEL SISTEMA"
log "Origen: $BACKUP_SELECCIONADO"

DIRECTORIOS=("etc" "home" "var" "root" "usr_local" "opt" "srv" "boot")

log "Restaurando directorios del sistema..."

for dir_backup in "${DIRECTORIOS[@]}"; do
    dir_sistema="/${dir_backup//_//}"
    
    if [ -d "$BACKUP_SELECCIONADO/$dir_backup" ]; then
        log "Restaurando $dir_sistema..."
        rsync -aAX --delete "$BACKUP_SELECCIONADO/$dir_backup"/ "$dir_sistema"/ 2>&1 | tee -a "$LOG_FILE"
        log "  $dir_sistema completado"
    else
        log "  ADVERTENCIA: $dir_backup no encontrado en backup"
    fi
done

log "Restaurando archivos de configuracion especificos..."

if [ -d "$BACKUP_SELECCIONADO/archivos_importantes" ]; then
    cp -r "$BACKUP_SELECCIONADO/archivos_importantes/sources.list"* /etc/apt/ 2>/dev/null || true
    cp "$BACKUP_SELECCIONADO/archivos_importantes/grub.cfg" /boot/grub/ 2>/dev/null || true
    log "  Archivos de configuracion restaurados"
fi

log "Restaurando paqueteria del sistema..."

if [ -f "$BACKUP_SELECCIONADO/paquetes_instalados.txt" ]; then
    log "  Actualizando lista de paquetes..."
    apt update 2>&1 | tee -a "$LOG_FILE"
    
    log "  Instalando paquetes desde backup..."
    dpkg --clear-selections
    dpkg --set-selections < "$BACKUP_SELECCIONADO/paquetes_instalados.txt"
    apt-get dselect-upgrade -y 2>&1 | tee -a "$LOG_FILE"
    
    if [ -f "$BACKUP_SELECCIONADO/paquetes_manuales.txt" ]; then
        log "  Restaurando paquetes instalados manualmente..."
        xargs apt-mark manual < "$BACKUP_SELECCIONADO/paquetes_manuales.txt" 2>&1 | tee -a "$LOG_FILE" || true
    fi
    log "  Paquetes restaurados"
fi

if [ -f "$BACKUP_SELECCIONADO/checksums.txt" ]; then
    log "Verificando integridad de archivos restaurados..."
    cd "$BACKUP_SELECCIONADO"
    sha256sum -c checksums.txt > /tmp/checksum_errors.txt 2>&1 || true
    errores=$(grep -c "FAILED" /tmp/checksum_errors.txt 2>/dev/null || echo 0)
    log "  Archivos con errores de checksum: $errores"
fi

log "Actualizando GRUB..."
update-grub 2>&1 | tee -a "$LOG_FILE" || log "  ADVERTENCIA: Error actualizando GRUB"

log "RESTAURACION COMPLETADA"
log "Log guardado en: $LOG_FILE"
log ""
log "PASOS SIGUIENTES:"
log "1. Revisar el log: $LOG_FILE"
log "2. Verificar servicios criticos"
log "3. Reiniciar el sistema: sudo reboot"
log ""

echo ""
echo "RESTAURACION COMPLETADA"
echo ""
read -p "¿Deseas reiniciar ahora? (s/n): " reiniciar

if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    log "Reiniciando sistema..."
    reboot
else
    echo "Recuerda reiniciar el sistema mas tarde con: sudo reboot"
fi

exit 0
