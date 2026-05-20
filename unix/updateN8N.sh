#!/bin/bash
# ============================================================
#  n8n Stack Updater — Docker Swarm
#  Uso: ./n8n-update.sh <version>
#  Ejemplo: ./n8n-update.sh 2.20.12
# ============================================================

set -euo pipefail

# ── Colores ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Config ───────────────────────────────────────────────────
STACK_NAME="n8n"
SERVICES=("n8n_n8n_editor" "n8n_n8n_worker" "n8n_n8n_webhook")
IMAGE_BASE="n8nio/n8n"
DB_SERVICE="n8n_n8n-db"
DB_USER="postgres"
DB_NAME="n8n"
BACKUP_DIR="/home/docker/n8n/backups"
YAML_PATH="/home/docker/n8n/docker-compose.yml"

# ── Funciones de UI ──────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║        n8n Docker Swarm Updater              ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "\n${CYAN}${BOLD}▶ $1${NC}"
}

print_ok() {
  echo -e "  ${GREEN}✔ $1${NC}"
}

print_warn() {
  echo -e "  ${YELLOW}⚠ $1${NC}"
}

print_err() {
  echo -e "  ${RED}✖ $1${NC}"
}

print_info() {
  echo -e "  ${DIM}$1${NC}"
}

spinner() {
  local pid=$1
  local msg=$2
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 10 ))
    printf "\r  ${CYAN}${spin:$i:1}${NC}  ${DIM}%s...${NC}" "$msg"
    sleep 0.1
  done
  printf "\r  \033[2K"
}

# ── Validaciones ─────────────────────────────────────────────
validate_version() {
  if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_err "Versión inválida: '$1'. Formato esperado: X.Y.Z (ej: 2.20.12)"
    exit 1
  fi
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    print_err "Docker no está instalado o no está en PATH"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    print_err "No se puede conectar al daemon de Docker"
    exit 1
  fi
}

check_swarm() {
  local role
  role=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
  if [[ "$role" != "active" ]]; then
    print_err "Este nodo no está en un Swarm activo"
    exit 1
  fi
}

# ── Obtener versión actual ────────────────────────────────────
get_current_version() {
  local service=$1
  docker service inspect "$service" \
    --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null \
    | grep -oP '(?<=:)[^@]+' || echo "desconocida"
}

# ── Backup de base de datos ───────────────────────────────────
do_backup() {
  print_step "Respaldo de base de datos"
  mkdir -p "$BACKUP_DIR"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="$BACKUP_DIR/n8n_backup_${timestamp}.sql"

  # Buscar el container de la DB
  local db_container
  db_container=$(docker ps -q -f "name=${DB_SERVICE}" 2>/dev/null | head -1)

  if [[ -z "$db_container" ]]; then
    print_warn "No se encontró el container de DB '${DB_SERVICE}' — omitiendo backup"
    return 0
  fi

  print_info "Container DB: $db_container"
  print_info "Destino: $backup_file"

  (docker exec "$db_container" pg_dump -U "$DB_USER" "$DB_NAME" > "$backup_file" 2>/dev/null) &
  local pid=$!
  spinner $pid "Generando backup"
  wait $pid
  local exit_code=$?

  if [[ $exit_code -eq 0 && -s "$backup_file" ]]; then
    local size
    size=$(du -sh "$backup_file" | cut -f1)
    print_ok "Backup creado: $backup_file ($size)"
  else
    print_warn "El backup falló o está vacío — continuando de todas formas"
    rm -f "$backup_file"
  fi
}

# ── Actualizar YAML si existe ─────────────────────────────────
update_yaml() {
  local new_version=$1
  print_step "Actualizando archivo YAML"

  if [[ ! -f "$YAML_PATH" ]]; then
    print_warn "No se encontró YAML en $YAML_PATH — se omite este paso"
    print_info "Tip: si tu stack viene de Portainer, actualiza desde la UI también"
    return 0
  fi

  # Backup del yaml
  cp "$YAML_PATH" "${YAML_PATH}.bak"
  print_ok "Backup YAML: ${YAML_PATH}.bak"

  # Reemplazar versión de imagen n8n
  local count
  count=$(grep -c "${IMAGE_BASE}:" "$YAML_PATH" || true)
  sed -i "s|${IMAGE_BASE}:[^[:space:]@\"']*|${IMAGE_BASE}:${new_version}|g" "$YAML_PATH"

  if [[ "$count" -gt 0 ]]; then
    print_ok "Imagen actualizada en YAML ($count ocurrencia/s)"
  else
    print_warn "No se encontraron referencias a '${IMAGE_BASE}:' en el YAML"
  fi
}

# ── Actualizar servicios ──────────────────────────────────────
update_services() {
  local new_version=$1
  local new_image="${IMAGE_BASE}:${new_version}"
  local failed=0

  print_step "Actualizando servicios en Docker Swarm"

  for service in "${SERVICES[@]}"; do
    local current_version
    current_version=$(get_current_version "$service")

    printf "  ${DIM}%-30s${NC} ${YELLOW}%s${NC} → ${GREEN}%s${NC}\n" \
      "$service" "$current_version" "$new_version"

    # Verificar que el servicio existe
    if ! docker service inspect "$service" &>/dev/null; then
      print_warn "Servicio '$service' no encontrado — omitiendo"
      continue
    fi

    (docker service update --image "$new_image" "$service" > /tmp/n8n_update_${service}.log 2>&1) &
    local pid=$!
    spinner $pid "Actualizando $service"
    wait $pid
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      print_ok "$service actualizado"
    else
      print_err "$service FALLÓ — ver: /tmp/n8n_update_${service}.log"
      cat "/tmp/n8n_update_${service}.log" | sed 's/^/    /'
      ((failed++))
    fi
  done

  return $failed
}

# ── Verificar resultado ───────────────────────────────────────
verify_services() {
  local expected_version=$1
  print_step "Verificando estado final"

  local all_ok=true
  printf "\n  %-35s %-15s %-8s %s\n" "SERVICIO" "VERSIÓN" "RÉPLICAS" "ESTADO"
  printf "  %-35s %-15s %-8s %s\n" "-------" "-------" "--------" "------"

  for service in "${SERVICES[@]}"; do
    local actual_version
    actual_version=$(get_current_version "$service")

    local replicas
    replicas=$(docker service ls --filter "name=${service}" --format "{{.Replicas}}" 2>/dev/null || echo "?")

    local status_icon
    if [[ "$actual_version" == "$expected_version" ]]; then
      status_icon="${GREEN}✔ OK${NC}"
    else
      status_icon="${RED}✖ MISMATCH${NC}"
      all_ok=false
    fi

    printf "  %-35s ${CYAN}%-15s${NC} %-8s " "$service" "$actual_version" "$replicas"
    echo -e "$status_icon"
  done

  echo ""
  if $all_ok; then
    echo -e "${GREEN}${BOLD}  ✔ Todos los servicios actualizados correctamente a ${expected_version}${NC}"
  else
    echo -e "${RED}${BOLD}  ✖ Algunos servicios no se actualizaron correctamente${NC}"
    return 1
  fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
  print_header

  # Argumento requerido
  if [[ $# -lt 1 ]]; then
    echo -e "${RED}Uso: $0 <version>${NC}"
    echo -e "${DIM}Ejemplo: $0 2.20.12${NC}"
    exit 1
  fi

  local NEW_VERSION="$1"

  # Checks previos
  print_step "Validaciones previas"
  validate_version "$NEW_VERSION"
  print_ok "Versión válida: $NEW_VERSION"

  check_docker
  print_ok "Docker disponible"

  check_swarm
  print_ok "Swarm activo"

  # Mostrar estado actual
  print_step "Estado actual"
  for svc in "${SERVICES[@]}"; do
    local v
    v=$(get_current_version "$svc")
    printf "  %-35s ${YELLOW}%s${NC}\n" "$svc" "$v"
  done

  # Confirmación
  echo ""
  echo -e "${YELLOW}${BOLD}  ¿Actualizar a ${NEW_VERSION}? [s/N]:${NC} " && read -r confirm
  if [[ ! "$confirm" =~ ^[sS]$ ]]; then
    echo -e "${DIM}  Cancelado.${NC}"
    exit 0
  fi

  # Ejecutar pasos
  do_backup
  update_yaml "$NEW_VERSION"
  update_services "$NEW_VERSION"
  local update_result=$?

  # Resultado final
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${NC}"
  verify_services "$NEW_VERSION"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${NC}"

  if [[ $update_result -ne 0 ]]; then
    echo -e "\n${RED}  Algunos servicios fallaron. Revisa los logs en /tmp/n8n_update_*.log${NC}"
    exit 1
  fi

  echo -e "\n${DIM}  Backups guardados en: $BACKUP_DIR${NC}"
  echo -e "${DIM}  Logs de update en:    /tmp/n8n_update_*.log${NC}\n"
}

main "$@"
