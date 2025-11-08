#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR: Este script debe ejecutarse como root${NC}"
    echo "Ejecuta: sudo $0"
    exit 1
fi

BACKUP_BASE="/backup"
BACKUP_COMPLETO="$BACKUP_BASE/completo"
BACKUP_INCREMENTAL="$BACKUP_BASE/incremental"

listar_backups() {
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         BACKUPS DISPONIBLES PARA RESTAURAR             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Backups completos
    if [ -d "$BACKUP_COMPLETO" ] && [ "$(ls -A $BACKUP_COMPLETO 2>/dev/null)" ]; then
        echo -e "${YELLOW}═══ BACKUPS COMPLETOS (Semanales - Domingos) ═══${NC}"
        contador=1
        for backup in $(ls -td "$BACKUP_COMPLETO"/backup_completo_* 2>/dev/null); do
            tamano=$(du -sh "$backup" | cut -f1)
            fecha_backup=$(basename "$backup" | sed 's/backup_completo_//')
            echo -e "${BLUE}[$contador]${NC} Completo - $fecha_backup (${GREEN}$tamano${NC})"
            echo "    Ruta: $backup"
            contador=$((contador + 1))
        done
        echo ""
    fi
    
    # Backups incrementales
    if [ -d "$BACKUP_INCREMENTAL" ] && [ "$(ls -A $BACKUP_INCREMENTAL 2>/dev/null)" ]; then
        echo -e "${YELLOW}═══ BACKUPS INCREMENTALES (Diarios - Lun-Sáb) ═══${NC}"
        
        ULTIMO_COMPLETO=$(ls -td "$BACKUP_COMPLETO"/backup_completo_* 2>/dev/null | head -n1)
        if [ -n "$ULTIMO_COMPLETO" ]; then
            echo -e "${BLUE}Basados en:${NC} $(basename "$ULTIMO_COMPLETO")"
        fi
        
        contador=1
        for backup in $(ls -td "$BACKUP_INCREMENTAL"/backup_incremental_* 2>/dev/null); do
            tamano=$(du -sh "$backup" | cut -f1)
            fecha_backup=$(basename "$backup" | sed 's/backup_incremental_//')
            echo -e "${BLUE}[$contador]${NC} Incremental - $fecha_backup (${GREEN}$tamano${NC})"
            echo "    Ruta: $backup"
            contador=$((contador + 1))
        done
        echo ""
    fi
    
    if [ ! -d "$BACKUP_COMPLETO" ] || [ -z "$(ls -A $BACKUP_COMPLETO 2>/dev/null)" ]; then
        echo -e "${RED}No hay backups disponibles${NC}"
        exit 1
    fi
}

listar_backups

echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║           SELECCIÓN DE BACKUP A RESTAURAR              ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Introduce la ruta completa del backup a restaurar:${NC}"
echo "(Ejemplo: /backup/completo/backup_completo_2025-11-08_22-30-45)"
echo "(O: /backup/incremental/backup_incremental_2025-11-08_23-15-30)"
echo ""
read -r BACKUP_SELECCIONADO

if [ ! -d "$BACKUP_SELECCIONADO" ]; then
    echo -e "${RED}ERROR: El directorio $BACKUP_SELECCIONADO no existe${NC}"
    exit 1
fi

if [ ! -f "$BACKUP_SELECCIONADO/paquetes_instalados.txt" ]; then
    echo -e "${RED}ERROR: Backup incompleto. Falta paquetes_instalados.txt${NC}"
    exit 1
fi

# Determinar si es incremental
TIPO_BACKUP="COMPLETO"
if [[ "$BACKUP_SELECCIONADO" == *"incremental"* ]]; then
    TIPO_BACKUP="INCREMENTAL"
    
    if [ -f "$BACKUP_SELECCIONADO/metadata.txt" ]; then
        COMPLETO_BASE=$(grep "Backup Completo Base:" "$BACKUP_SELECCIONADO/metadata.txt" | cut -d: -f2- | xargs)
        
        if [ -z "$COMPLETO_BASE" ] || [ ! -d "$COMPLETO_BASE" ]; then
            echo -e "${RED}ERROR: No se encuentra el backup completo base${NC}"
            echo "Este backup incremental necesita: $COMPLETO_BASE"
            exit 1
        fi
        
        echo -e "${YELLOW}NOTA: Este es un backup INCREMENTAL${NC}"
        echo -e "Se restaurará primero el completo base: ${GREEN}$(basename "$COMPLETO_BASE")${NC}"
        echo -e "Y luego los cambios del incremental: ${GREEN}$(basename "$BACKUP_SELECCIONADO")${NC}"
        echo ""
    fi
fi

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                        ADVERTENCIA                     ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
echo -e "${RED}Estás a punto de restaurar el sistema desde:${NC}"
echo -e "${YELLOW}$BACKUP_SELECCIONADO${NC}"
echo ""
echo -e "${RED}Esto sobrescribirá archivos actuales del sistema.${NC}"
echo -e "${RED}Se recomienda hacer un backup del estado actual primero.${NC}"
echo ""
read -p "$(echo -e ${YELLOW}"¿Deseas continuar? (escribe 'SI' en mayúsculas): "${NC})" confirmacion

if [ "$confirmacion" != "SI" ]; then
    echo "Restauración cancelada."
    exit 0
fi

LOG_FILE="/var/log/restauracion_$(date +%Y%m%d_%H%M%S).log"
echo -e "${GREEN}Creando log en: $LOG_FILE${NC}"
echo ""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== INICIANDO RESTAURACIÓN DEL SISTEMA ==="
log "Tipo de backup: $TIPO_BACKUP"
log "Origen: $BACKUP_SELECCIONADO"

DIRECTORIOS=("etc" "home" "var" "root" "usr_local" "opt" "srv" "boot")

# Si es incremental, restaurar primero el completo
if [ "$TIPO_BACKUP" = "INCREMENTAL" ] && [ -n "$COMPLETO_BASE" ]; then
    log "=== PASO 1: Restaurando backup COMPLETO base ==="
    log "Origen: $COMPLETO_BASE"
    
    for dir_backup in "${DIRECTORIOS[@]}"; do
        dir_sistema="/${dir_backup//_//}"
        
        if [ -d "$COMPLETO_BASE/$dir_backup" ]; then
            log "Restaurando $dir_sistema desde backup completo..."
            rsync -aAX --delete "$COMPLETO_BASE/$dir_backup"/ "$dir_sistema"/ 2>&1 | tee -a "$LOG_FILE"
            log "  ✓ $dir_sistema restaurado desde completo"
        fi
    done
    
    log "=== PASO 2: Aplicando cambios INCREMENTALES ==="
    log "Origen: $BACKUP_SELECCIONADO"
fi

# Restaurar directorios
log "Restaurando directorios del sistema..."

for dir_backup in "${DIRECTORIOS[@]}"; do
    dir_sistema="/${dir_backup//_//}"
    
    if [ -d "$BACKUP_SELECCIONADO/$dir_backup" ]; then
        if [ "$TIPO_BACKUP" = "INCREMENTAL" ]; then
            log "Aplicando cambios incrementales a $dir_sistema..."
        else
            log "Restaurando $dir_sistema..."
        fi
        
        rsync -aAX --delete "$BACKUP_SELECCIONADO/$dir_backup"/ "$dir_sistema"/ 2>&1 | tee -a "$LOG_FILE"
        log "  ✓ $dir_sistema completado"
    else
        log "  ⚠ ADVERTENCIA: $dir_backup no encontrado en backup"
    fi
done

# Restaurar archivos específicos
log "Restaurando archivos de configuración específicos..."

if [ -d "$BACKUP_SELECCIONADO/archivos_importantes" ]; then
    cp -r "$BACKUP_SELECCIONADO/archivos_importantes/sources.list"* /etc/apt/ 2>/dev/null || true
    cp "$BACKUP_SELECCIONADO/archivos_importantes/grub.cfg" /boot/grub/ 2>/dev/null || true
    log "  ✓ Archivos de configuración restaurados"
fi

log "Restaurando paquetería del sistema..."

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
    log "  ✓ Paquetes restaurados"
fi

if [ -f "$BACKUP_SELECCIONADO/checksums.txt" ]; then
    log "Verificando integridad de archivos restaurados..."
    cd "$BACKUP_SELECCIONADO"
    sha256sum -c checksums.txt > /tmp/checksum_errors.txt 2>&1 || true
    errores=$(grep -c "FAILED" /tmp/checksum_errors.txt 2>/dev/null || echo 0)
    log "  Archivos con errores de checksum: $errores"
fi

log "Actualizando GRUB..."
update-grub 2>&1 | tee -a "$LOG_FILE" || log "  ⚠ ADVERTENCIA: Error actualizando GRUB"

# Resumen
log "=== RESTAURACIÓN COMPLETADA ==="
log "Tipo: $TIPO_BACKUP"
log "Log guardado en: $LOG_FILE"
log ""
log "PASOS SIGUIENTES:"
log "1. Revisar el log: $LOG_FILE"
log "2. Verificar servicios críticos"
log "3. Reiniciar el sistema: sudo reboot"
log ""

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             RESTAURACIÓN COMPLETADA                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Se recomienda reiniciar el sistema.${NC}"
read -p "$(echo -e ${BLUE}"¿Deseas reiniciar ahora? (s/n): "${NC})" reiniciar

if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    log "Reiniciando sistema..."
    reboot
else
    echo "Recuerda reiniciar el sistema más tarde con: sudo reboot"
fi

exit 0
