#!/bin/bash

set -e

# Colores para salida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar ejecución como root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR: Ejecutar como root${NC}"
    exit 1
fi

# Verificar rsync
if ! command -v rsync &> /dev/null; then
    echo "Instalando rsync..."
    apt update && apt install -y rsync
fi

# Configuración
BACKUP_BASE="/backup"
BACKUP_COMPLETO="$BACKUP_BASE/completo"
BACKUP_INCREMENTAL="$BACKUP_BASE/incremental"
FECHA=$(date +%Y-%m-%d_%H-%M-%S)
DIA_SEMANA=$(date +%u)  # 1=Lunes, 7=Domingo
LOG_FILE="$BACKUP_BASE/backup.log"

# Directorios a respaldar
DIRECTORIOS=("etc" "home" "var" "root" "usr_local" "opt" "srv" "boot")

# Determinar tipo de backup
if [ "$DIA_SEMANA" -eq 7 ]; then
    TIPO="COMPLETO"
    DESTINO="$BACKUP_COMPLETO/backup_completo_$FECHA"
    echo " DOMINGO: Realizando backup COMPLETO"
else
    TIPO="INCREMENTAL"
    DESTINO="$BACKUP_INCREMENTAL/backup_incremental_$FECHA"
    
    # Buscar último completo
    ULTIMO_COMPLETO=$(ls -td "$BACKUP_COMPLETO"/backup_completo_* 2>/dev/null | head -n1)
    
    if [ -z "$ULTIMO_COMPLETO" ]; then
        echo " ERROR: No hay backup completo base"
        exit 1
    fi
    
    echo " $(date +%A): Realizando backup INCREMENTAL"
    echo "   Base: $(basename "$ULTIMO_COMPLETO")"
fi

# Crear directorio destino
mkdir -p "$DESTINO"
cd "$DESTINO"

# Realizar backup según tipo
echo "Copiando directorios del sistema..."
for dir_orig in "${DIRECTORIOS[@]}"; do
    dir_sistema="/${dir_orig//_//}"
    
    if [ -d "$dir_sistema" ]; then
        echo "  → $dir_sistema"
        
        if [ "$TIPO" = "COMPLETO" ]; then
            rsync -aAX "$dir_sistema"/ "$dir_orig"/
        else
            # Incremental: comparar con último completo
            rsync -aAX --compare-dest="$ULTIMO_COMPLETO/$dir_orig/" \
                  "$dir_sistema"/ "$dir_orig"/
        fi
    fi
done

# Guardar archivos específicos
mkdir -p archivos_importantes
cp /etc/apt/sources.list* archivos_importantes/ 2>/dev/null || true
cp /boot/grub/grub.cfg archivos_importantes/ 2>/dev/null || true

# Guardar paquetería
dpkg --get-selections > paquetes_instalados.txt
apt-mark showmanual > paquetes_manuales.txt

# Metadata
cat > metadata.txt <<EOF
Tipo de Backup: $TIPO
Fecha: $FECHA
Día de la semana: $(date +%A)
EOF

if [ "$TIPO" = "INCREMENTAL" ]; then
    echo "Backup Completo Base: $ULTIMO_COMPLETO" >> metadata.txt
fi

# Checksums
find . -type f -exec sha256sum {} \; > checksums.txt

# Enlaces simbólicos
ln -sf "$DESTINO" "$BACKUP_BASE/ultimo_$TIPO"

# Limpieza: Eliminar incrementales antiguos si es domingo
if [ "$TIPO" = "COMPLETO" ] && [ -d "$BACKUP_INCREMENTAL" ]; then
    echo "Limpiando incrementales antiguos..."
    rm -rf "$BACKUP_INCREMENTAL"/backup_incremental_*
fi

# Resumen
TAMANO=$(du -sh "$DESTINO" | cut -f1)
echo ""
echo " BACKUP $TIPO COMPLETADO"
echo "   Ubicación: $DESTINO"
echo "   Tamaño: $TAMANO"

# Log
echo "[$(date)] Backup $TIPO completado - $TAMANO" >> "$LOG_FILE"

exit 0

