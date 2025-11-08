# Sistema de Backup Incremental Automático

Sistema de copias de seguridad automáticas para Linux usando rsync y systemd con estrategia incremental semanal.

## Características

- Backup completo semanal (domingos)
- Backups incrementales diarios (lunes a sábado)
- Ejecución automatizada a las 01:00 AM
- Restauración automática con detección de tipo
- Ahorro de espacio del 80-90%
- Rotación automática de backups antiguos
- Verificación de integridad con checksums SHA256

## Estrategia

```
DOMINGO: Backup COMPLETO (base)
LUNES-SÁBADO: Backups INCREMENTALES (solo cambios)
```

## Requisitos

- Linux con systemd
- Permisos root/sudo
- Mínimo 30GB en /backup
- rsync (instalación automática)

## Instalación

```bash
# Crear directorios
sudo mkdir -p /backup/{completo,incremental}
sudo mkdir -p /usr/local/bin

# Instalar scripts
sudo cp backup.sh restore.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/{backup,restore}.sh

# Configurar systemd
sudo cp backup.service backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer

# Crear primer backup completo
sudo bash -c 'DIA_SEMANA=7 /usr/local/bin/backup.sh'
```

## Directorios Respaldados

- /etc - Configuración del sistema
- /home - Directorios de usuarios
- /var - Datos variables
- /root - Directorio root
- /usr/local - Software local
- /opt - Aplicaciones opcionales
- /srv - Datos de servicios
- /boot - Configuración de arranque
- Paquetería instalada (dpkg)

## Uso

### Verificación

```bash
# Estado del timer
sudo systemctl status backup.timer
sudo systemctl list-timers backup.timer

# Ver backups
ls -lh /backup/completo/
ls -lh /backup/incremental/

# Ver logs
sudo journalctl -u backup.service -n 50
tail -f /backup/backup.log
```

### Ejecución Manual

```bash
# Backup según día actual
sudo systemctl start backup.service

# Forzar completo
sudo bash -c 'DIA_SEMANA=7 /usr/local/bin/backup.sh'

# Forzar incremental
sudo bash -c 'DIA_SEMANA=1 /usr/local/bin/backup.sh'
```

## Restauración

```bash
# Ejecutar script de restauración
sudo /usr/local/bin/restore.sh

# Seleccionar backup de la lista mostrada
# El script detecta automáticamente si es completo o incremental
# Para incrementales, restaura primero la base y luego los cambios
```

## Estructura de Archivos

```
/usr/local/bin/
├── backup.sh          # Script principal de backup
└── restore.sh         # Script de restauración

/etc/systemd/system/
├── backup.service     # Servicio de systemd
└── backup.timer       # Timer de ejecución

/backup/
├── completo/          # Backups completos semanales
├── incremental/       # Backups incrementales diarios
└── backup.log         # Log de operaciones
```

## Política de Retención

- Backups completos: 4 semanas
- Backups incrementales: semana actual
- Limpieza automática de backups antiguos

## Configuración del Timer

El servicio se ejecuta diariamente a las 01:00 AM. Para modificar:

```bash
sudo nano /etc/systemd/system/backup.timer
# Cambiar: OnCalendar=*-*-* 01:00:00
sudo systemctl daemon-reload
sudo systemctl restart backup.timer
```

## Solución de Problemas

### El backup falla con "No existe backup completo previo"

```bash
# Crear backup completo inicial
sudo bash -c 'DIA_SEMANA=7 /usr/local/bin/backup.sh'
```

### Ver errores detallados

```bash
sudo journalctl -u backup.service -n 100
cat /backup/backup.log
```

### Verificar espacio en disco

```bash
df -h /backup
du -sh /backup/*
```

## Autor

Ángel de la Vega

## Licencia

MIT License
