# n8n Docker Swarm Updater

Script para actualizar n8n en Docker Swarm de forma segura: hace backup, actualiza el YAML y los servicios, y verifica el resultado.

---

## Uso

```bash
# 1. Subir el script a tu servidor
scp n8n-update.sh root@tu-servidor:/home/docker/n8n/

# 2. Darle permisos
chmod +x /home/docker/n8n/n8n-update.sh

# 3. Ejecutar con la versión deseada
./n8n-update.sh 2.20.12
```

---

## Qué hace el script automáticamente

| Paso | Acción |
|------|--------|
| ✅ Validación | Verifica formato de versión, Docker y Swarm activo |
| 📋 Estado actual | Muestra la versión corriendo en cada servicio |
| 💾 Backup | Hace `pg_dump` de la DB antes de tocar nada |
| 📝 YAML | Actualiza el `docker-compose.yml` si existe (con backup `.bak`) |
| 🚀 Update | Actualiza los 3 servicios: `editor`, `worker`, `webhook` |
| 🔍 Verificación | Muestra tabla final con versión y réplicas de cada servicio |

---

## Output que verás en pantalla

```
╔══════════════════════════════════════════════╗
║        n8n Docker Swarm Updater              ║
╚══════════════════════════════════════════════╝

▶ Estado actual
  n8n_n8n_editor     2.14.2
  n8n_n8n_worker     2.14.2
  n8n_n8n_webhook    2.14.2

  ¿Actualizar a 2.20.12? [s/N]:
```

> **Nota:** Si tu stack viene de Portainer (sin YAML local), el script omite el paso del YAML con un aviso y continúa con el `docker service update` directamente.
