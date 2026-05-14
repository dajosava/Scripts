#!/bin/bash

# Colores ANSI - no requieren instalacion
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BGBLUE='\033[44m'
BGRED='\033[41m'
BGYELLOW='\033[43m'
BOLD='\033[1m'
NC='\033[0m'

titulo() {
    echo ""
    echo -e "${BGBLUE}${WHITE}${BOLD}  $1  ${NC}"
    echo -e "${CYAN}$(printf '%.0s─' {1..50})${NC}"
}

subtitulo() {
    echo -e "${YELLOW}${BOLD}▸ $1${NC}"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

alerta() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ─────────────────────────────────────────
# CABECERA
# ─────────────────────────────────────────
clear
echo -e "${BGBLUE}${WHITE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗  "
echo "  ║         DIAGNOSTICO DEL SERVIDOR                ║  "
echo "  ╚══════════════════════════════════════════════════╝  "
echo -e "${NC}"
echo -e "  ${BOLD}Servidor:${NC} $(hostname)"
echo -e "  ${BOLD}Fecha:${NC}    $(date)"
echo -e "  ${BOLD}Uptime:${NC}   $(uptime -p)"
echo ""

# ─────────────────────────────────────────
titulo "1. ULTIMO REINICIO"
# ─────────────────────────────────────────
last reboot | head -10
echo ""

# ─────────────────────────────────────────
titulo "2. ULTIMO APAGADO"
# ─────────────────────────────────────────
last -x shutdown | head -10
echo ""

# ─────────────────────────────────────────
titulo "3. OOM KILLER - FALTA DE MEMORIA"
# ─────────────────────────────────────────
OOM=$(journalctl -k --no-pager -S "7 days ago" 2>/dev/null | grep -i "oom\|killed process\|out of memory" | tail -20)
if [ -z "$OOM" ]; then
    ok "Sin eventos OOM en los ultimos 7 dias"
else
    error "OOM KILLER ACTIVO - procesos matados por falta de RAM"
    echo -e "${RED}$OOM${NC}"
fi
echo ""

# ─────────────────────────────────────────
titulo "4. ERRORES CRITICOS DEL KERNEL"
# ─────────────────────────────────────────
KERR=$(journalctl -k --no-pager -p err -S "7 days ago" 2>/dev/null | tail -30)
if echo "$KERR" | grep -q "No entries"; then
    ok "Sin errores criticos del kernel"
else
    echo -e "${RED}$KERR${NC}"
fi
echo ""

# ─────────────────────────────────────────
titulo "5. ERRORES CRITICOS DEL SISTEMA"
# ─────────────────────────────────────────
SERR=$(journalctl --no-pager -p crit -S "48 hours ago" 2>/dev/null | tail -30)
if echo "$SERR" | grep -q "No entries"; then
    ok "Sin errores criticos del sistema en 48h"
else
    echo -e "${RED}$SERR${NC}"
fi
echo ""

# ─────────────────────────────────────────
titulo "6. EVENTOS DE APAGADO EN JOURNAL"
# ─────────────────────────────────────────
journalctl -k --no-pager --since "7 days ago" -q 2>/dev/null | grep -iE "shutdown|reboot|poweroff" | tail -20 || ok "Sin eventos de apagado detectados"
echo ""

# ─────────────────────────────────────────
titulo "7. DISCO"
# ─────────────────────────────────────────
subtitulo "Uso de disco:"
df -h | awk -v red="${RED}" -v yellow="${YELLOW}" -v green="${GREEN}" -v nc="${NC}" '
NR==1 { print; next }
/tmpfs|overlay/ { next }
{
    pct = $5
    gsub(/%/, "", pct)
    if (pct+0 >= 90) color = red
    else if (pct+0 >= 75) color = yellow
    else color = green
    printf "%s%s%s\n", color, $0, nc
}'
echo ""
subtitulo "Inodes:"
df -i | grep -v tmpfs
echo ""

# ─────────────────────────────────────────
titulo "8. MEMORIA Y SWAP"
# ─────────────────────────────────────────
free -h
echo ""
SWAP=$(swapon --show 2>/dev/null)
if [ -z "$SWAP" ]; then
    alerta "SIN SWAP configurado - riesgo de OOM en picos de RAM"
    echo -e "  ${YELLOW}Solucion: fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile${NC}"
else
    ok "Swap activo:"
    echo "$SWAP"
fi
echo ""

# ─────────────────────────────────────────
titulo "9. DOCKER - CONTENEDORES"
# ─────────────────────────────────────────
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | awk -v green="${GREEN}" -v red="${RED}" -v yellow="${YELLOW}" -v nc="${NC}" '
NR==1 { print; next }
/Up/ { printf "%s%s%s\n", green, $0, nc; next }
/Exited/ { printf "%s%s%s\n", red, $0, nc; next }
/Created/ { printf "%s%s%s\n", yellow, $0, nc; next }
{ print }'
echo ""

# ─────────────────────────────────────────
titulo "10. DOCKER - EVENTOS ULTIMAS 48H"
# ─────────────────────────────────────────
docker events --since 48h --until now --filter type=container 2>/dev/null | tail -20 || ok "Sin eventos recientes"
echo ""

# ─────────────────────────────────────────
titulo "11. DOCKER DAEMON ERRORES"
# ─────────────────────────────────────────
DERR=$(journalctl -u docker --no-pager -S "48 hours ago" 2>/dev/null | grep -iE "error|warn|fatal" | tail -20)
if [ -z "$DERR" ]; then
    ok "Sin errores en el daemon de Docker"
else
    echo -e "${YELLOW}$DERR${NC}"
fi
echo ""

# ─────────────────────────────────────────
titulo "12. LOGS n8n-n8n-1"
# ─────────────────────────────────────────
docker logs --tail 30 n8n-n8n-1 2>&1 | grep -iE "error|warn" | tail -20 | awk -v red="${RED}" -v yellow="${YELLOW}" -v nc="${NC}" '
/error/i { printf "%s%s%s\n", red, $0, nc; next }
/warn/i  { printf "%s%s%s\n", yellow, $0, nc; next }
{ print }'
echo ""

# ─────────────────────────────────────────
titulo "13. LOGS evo-api-1"
# ─────────────────────────────────────────
docker logs --tail 30 evo-api-1 2>&1 | grep -iE "error|warn" | tail -20 | awk -v red="${RED}" -v yellow="${YELLOW}" -v nc="${NC}" '
/error/i { printf "%s%s%s\n", red, $0, nc; next }
/warn/i  { printf "%s%s%s\n", yellow, $0, nc; next }
{ print }'
echo ""

# ─────────────────────────────────────────
titulo "14. SERVICIOS SYSTEMD FALLIDOS"
# ─────────────────────────────────────────
FAILED=$(systemctl --failed --no-pager 2>/dev/null | grep "loaded units listed")
if echo "$FAILED" | grep -q "^0"; then
    ok "Ningun servicio systemd fallido"
else
    systemctl --failed --no-pager | awk -v red="${RED}" -v nc="${NC}" '/failed/ { printf "%s%s%s\n", red, $0, nc; next } { print }'
fi
echo ""

# ─────────────────────────────────────────
titulo "15. PROCESOS POR RAM"
# ─────────────────────────────────────────
ps aux --sort=-%mem | head -15 | awk -v red="${RED}" -v yellow="${YELLOW}" -v green="${GREEN}" -v nc="${NC}" '
NR==1 { printf "%-12s %6s %6s %s\n", "USER", "%CPU", "%MEM", "COMANDO"; next }
{
    mem = $4
    if (mem+0 >= 10) color = red
    else if (mem+0 >= 5) color = yellow
    else color = green
    printf "%s%-12s %6s %6s %s%s\n", color, $1, $3, $4, $11, nc
}'
echo ""

# ─────────────────────────────────────────
# PIE
# ─────────────────────────────────────────
echo -e "${BGBLUE}${WHITE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗  "
echo "  ║              FIN DEL DIAGNOSTICO                ║  "
echo "  ╚══════════════════════════════════════════════════╝  "
echo -e "${NC}"
