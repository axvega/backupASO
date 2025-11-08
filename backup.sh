#!/bin/bash


set -e  


BACKUP_BASE="/backup"
BACKUP_COMPLETO="$BACKUP_BASE/completo"
BACKUP_INCREMENTAL="$BACKUP_BASE/incremental"
FECHA=$(date +%Y-%m-%d_%H-%M-%S)
DIA_SEMANA=$(date +%u)  
LOG_FILE="$BACKUP_BASE/backup.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_COMPLETO" "$BACKUP_INCREMENTAL"

log "=== INICIANDO BACKUP ==="

if ! which rsync > /dev/null 2>&1; then
    log "ERROR: rsync no está instalado"
    if [ "$(id -u)" -eq 0 ]; then
        log "Instalando rsync..."
        apt update && apt install -y rsync
    else
        log "Ejecuta: sudo apt install rsync"
        exit 1
    fi
fi

log "rsync versión: $(rsync --version | head -n1)"

if [ "$DIA_SEMANA" -eq 7 ]; then
    TIPO="COMPLETO"
    DESTINO="$BACKUP_COMPLETO/backup_completo_$FECHA"
    LINK_DEST=""
    
    log "=== BACKUP COMPLETO (Semanal) ==="
    log "Se creará una nueva copia base completa"
    
else
    TIPO="INCREMENTAL"
    DESTINO="$BACKUP_INCREMENTAL/backup_incremental_$FECHA"
    
    ULTIMO_COMPLETO=$(ls -td "$BACKUP_COMPLETO"/backup_completo_* 2>/dev/null | head -n1)
    
    if [ -z "$ULTIMO_COMPLETO" ]; then
        log "ERROR: No existe backup completo previo"
        log "Ejecuta primero un backup completo o espera al domingo"
        exit 1
    fi
    
    LINK_DEST="--link-dest=$ULTIMO_COMPLETO"
    
    log "=== BACKUP INCREMENTAL (Diario) ==="
    log "Basado en: $ULTIMO_COMPLETO"
    log "Solo se copiarán archivos nuevos o modificados"
fi

log "Destino: $DESTINO"

mkdir -p "$DESTINO"

DIRECTORIOS=("/etc" "/home" "/var" "/root" "/usr/local" "/opt" "/srv" "/boot")

log "Iniciando copias con rsync..."

for dir in "${DIRECTORIOS[@]}"; do
    if [ -d "$dir" ]; then
        log "Copiando $dir..."
        nombre_destino=$(echo "$dir" | sed 's/^\/*//' | tr '/' '_')
        
        rsync -aAX --delete \
              --exclude='/var/tmp/*' \
              --exclude='/var/cache/*' \
              --exclude='/var/log/*.log' \
              $LINK_DEST \
              "$dir"/ "$DESTINO/$nombre_destino" 2>&1 | tee -a "$LOG_FILE"
        
        log "$dir completado"
    else
        log "ADVERTENCIA: $dir no existe"
    fi
done

log "Guardando configuración del sistema..."
mkdir -p "$DESTINO/archivos_importantes"

cp -r /etc/apt/sources.list* "$DESTINO/archivos_importantes/" 2>/dev/null || true
cp /boot/grub/grub.cfg "$DESTINO/archivos_importantes/" 2>/dev/null || true

dpkg --get-selections > "$DESTINO/paquetes_instalados.txt"
apt-mark showauto > "$DESTINO/paquetes_automaticos.txt"
apt-mark showmanual > "$DESTINO/paquetes_manuales.txt"

uname -a > "$DESTINO/info_sistema.txt"
df -h >> "$DESTINO/info_sistema.txt"
cat /etc/os-release >> "$DESTINO/info_sistema.txt"

cat > "$DESTINO/metadata.txt" << EOF
Tipo de Backup: $TIPO
Fecha: $FECHA
Día de la semana: $DIA_SEMANA
Backup Completo Base: $ULTIMO_COMPLETO
Sistema: $(uname -s) $(uname -r)
Hostname: $(hostname)
EOF

log "Generando checksums..."
cd "$DESTINO"
find . -type f -exec sha256sum {} \; > checksums.txt 2>/dev/null

log "Aplicando política de retención..."

cd "$BACKUP_COMPLETO"
ls -td backup_completo_* 2>/dev/null | tail -n +5 | xargs -r rm -rf
COMPLETOS_RESTANTES=$(ls -d backup_completo_* 2>/dev/null | wc -l)
log "Backups completos mantenidos: $COMPLETOS_RESTANTES/4"

if [ -n "$ULTIMO_COMPLETO" ]; then
    FECHA_ULTIMO_COMPLETO=$(stat -c %Y "$ULTIMO_COMPLETO")
    cd "$BACKUP_INCREMENTAL"
    
    for incremental in backup_incremental_*; do
        if [ -d "$incremental" ]; then
            FECHA_INCREMENTAL=$(stat -c %Y "$incremental")
            if [ "$FECHA_INCREMENTAL" -lt "$FECHA_ULTIMO_COMPLETO" ]; then
                log "Eliminando incremental antiguo: $incremental"
                rm -rf "$incremental"
            fi
        fi
    done
fi

INCREMENTALES_RESTANTES=$(ls -d "$BACKUP_INCREMENTAL"/backup_incremental_* 2>/dev/null | wc -l)
log "Backups incrementales de esta semana: $INCREMENTALES_RESTANTES"

TAMANO_BACKUP=$(du -sh "$DESTINO" | cut -f1)
TAMANO_TOTAL=$(du -sh "$BACKUP_BASE" | cut -f1)

if [ "$TIPO" = "INCREMENTAL" ] && [ -n "$ULTIMO_COMPLETO" ]; then
    TAMANO_COMPLETO=$(du -sb "$ULTIMO_COMPLETO" | cut -f1)
    TAMANO_INCREMENTAL=$(du -sb "$DESTINO" | cut -f1)
    ESPACIO_AHORRADO=$(( (TAMANO_COMPLETO - TAMANO_INCREMENTAL) * 100 / TAMANO_COMPLETO ))
    
    log "=== ESTADÍSTICAS DE ESPACIO ==="
    log "Backup completo base: $(du -sh "$ULTIMO_COMPLETO" | cut -f1)"
    log "Backup incremental actual: $TAMANO_BACKUP"
    log "Espacio ahorrado: ~${ESPACIO_AHORRADO}%"
fi

ln -sfn "$DESTINO" "$BACKUP_BASE/ultimo_backup"
if [ "$TIPO" = "COMPLETO" ]; then
    ln -sfn "$DESTINO" "$BACKUP_BASE/ultimo_completo"
else
    ln -sfn "$DESTINO" "$BACKUP_BASE/ultimo_incremental"
fi

log "=== BACKUP $TIPO COMPLETADO ==="
log "Ubicación: $DESTINO"
log "Tamaño del backup: $TAMANO_BACKUP"
log "Tamaño total usado: $TAMANO_TOTAL"
log "Enlaces simbólicos actualizados en $BACKUP_BASE/"

exit 0




