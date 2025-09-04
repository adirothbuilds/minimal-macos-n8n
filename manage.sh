#!/bin/zsh

set -e

# Define variables
SCRIPT_VERSION="0.1.0"
COMPOSE_FILE=$(ls ./docker-compose.y* 2>/dev/null | head -n 1)
ENV_FILE="./.env"
COLIMA_CPU=2
COLIMA_MEM=4
COLIMA_DISK=30
COLIMA_ARCH="aarch64"
COLIMA_VM_TYPE="vz"
COLIMA_MOUNT_TYPE="virtiofs"
SKIP_TUNNEL=false
ACTION="start"
START_TIME=$(date +%s)

# ANSI color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

intro() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${GREEN}   Minimal n8n on macOS with Colima v${SCRIPT_VERSION} ${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
}

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

help() {
  echo "Usage: $0 [action] [options]"
  echo ""
  echo "Actions:"
  echo "  start           Start services (default)"
  echo "  stop            Stop services and Colima"
  echo ""
  echo "Options:"
  echo "  --skip-tunnel   Skip the creation of the Cloudflare tunnel (only for start)"
  echo "  -h, --help      Show this help message"
}

parse_args() {
  if [[ "$1" == "start" || "$1" == "stop" ]]; then
    ACTION=$1
    shift
  fi

  for arg in "$@"; do
    case $arg in
      --version)
        info "Minimal n8n on macOS with Colima v${SCRIPT_VERSION}"
        ;;
      --skip-tunnel)
        SKIP_TUNNEL=true
        ;;
      -h|--help)
        help
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        help
        exit 1
        ;;
    esac
  done
}

check_ws() {
  if [ -z "$COMPOSE_FILE" ]; then
    error "Error: docker-compose.yml or docker-compose.yaml not found."
    return 1
  fi
  if [ ! -f "$ENV_FILE" ]; then
    error "Error: .env file is missing."
    return 1
  fi
  COMPOSE_FILE=$(realpath "$COMPOSE_FILE" 2>/dev/null || greadlink -f "$COMPOSE_FILE" 2>/dev/null || echo "$COMPOSE_FILE")
  ENV_FILE=$(realpath "$ENV_FILE" 2>/dev/null || greadlink -f "$ENV_FILE" 2>/dev/null || echo "$ENV_FILE")
  info "Workspace check passed."
  return 0
}

check_sudo() {
  if [ "$EUID" -eq 0 ]; then
    error "Please do not run as root or with sudo."
    return 1
  fi
  return 0
}

install_deps() {
  if ! command -v colima &>/dev/null; then
    info "Installing colima..."
    brew install colima || return 1
  fi
  if ! command -v docker &>/dev/null; then
    info "Installing Docker CLI..."
    brew install docker || return 1
  fi
  if ! command -v docker-compose &>/dev/null; then
    info "Installing Docker Compose CLI..."
    brew install docker-compose || return 1
  fi
  return 0
}

run_colima() {
  if colima status | grep -q "stopped"; then
    info "Starting existing Colima VM..."
    colima start
  elif ! colima status &>/dev/null; then
    info "Creating new Colima VM..."
    colima start \
      --cpu $COLIMA_CPU \
      --memory $COLIMA_MEM \
      --disk $COLIMA_DISK \
      --arch $COLIMA_ARCH \
      --vm-type $COLIMA_VM_TYPE \
      --mount-type $COLIMA_MOUNT_TYPE
  else
    info "Colima is already running."
  fi
}

ping_docker() {
  info "Pinging Docker..."
  { docker info &>/dev/null; info "Docker is running"; return 0; } \
  || { error "Docker is not running"; return 1; }
}

write_tunnel_token_to_env() {
  info "Writing tunnel token to .env file..."
  if [ -z "$1" ]; then
    error "Error: Tunnel token is empty."
    return 1
  fi
  if [ ! -f $ENV_FILE ]; then
    error "Error: $ENV_FILE file does not exist."
    return 1
  fi
  grep -q '^CLOUDFLARE_TUNNEL_TOKEN=' $ENV_FILE \
  && sed -i.bak "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$1|" $ENV_FILE \
  && rm $ENV_FILE.bak \
  || echo "CLOUDFLARE_TUNNEL_TOKEN=$1" >> $ENV_FILE
  return 0
}

check_if_tunnel_exists() {
  if ! command -v cloudflared &>/dev/null; then
    error "Cloudflared is not installed."
    return 1
  fi
  if ! cloudflared tunnel list --output json | grep -q "\"$1\""; then
    error "Cloudflare tunnel $1 does not exist."
    return 1
  fi
  return 0
}

create_cloudflare_tunnel() {
  if [ "$SKIP_TUNNEL" = true ]; then
    info "Skipping Cloudflare tunnel creation."
    return 0
  fi

  info "Checking Cloudflare tunnel..."
  if ! command -v cloudflared &>/dev/null; then
    info "Installing Cloudflared..."
    brew install cloudflared
  fi
  info "Logging in to Cloudflare..."
  cloudflared tunnel login || return 1

  read -p "Enter a name for your tunnel: " tunnel_name
  read -p "Enter a hostname for your tunnel: " tunnel_hostname
  if [ -z "$tunnel_name" ] || [ -z "$tunnel_hostname" ]; then
    error "Error: Tunnel name and hostname cannot be empty."
    return 1
  fi
  if check_if_tunnel_exists "$tunnel_name"; then
    info "Tunnel $tunnel_name already exists. Skipping creation."
  else
    cloudflared tunnel create "$tunnel_name" || return 1
    cloudflared tunnel route dns "$tunnel_name" "$tunnel_hostname" || return 1
    info "Cloudflare tunnel $tunnel_name created with hostname $tunnel_hostname."
  fi

  info "Extracting tunnel token..."
  TMP_TUNNEL_TOKEN=$(cloudflared tunnel token "$tunnel_name")
  if [ -z "$TMP_TUNNEL_TOKEN" ]; then
    error "Error: Failed to extract tunnel token."
    return 1
  fi
  info "Tunnel token extracted."

  write_tunnel_token_to_env "$TMP_TUNNEL_TOKEN"

  return 0
}

update_env_var() {
  key=$1
  placeholder=$2
  prompt=$3

  current=$(awk -F= -v key="$key" '$1==key {print $2}' "$ENV_FILE")

  if [ -z "$current" ] || [ "$current" = "$placeholder" ]; then
    read -p "$prompt: " new_value
    if [ -z "$new_value" ]; then
      info "No value entered. Keeping placeholder: $placeholder"
      new_value=$placeholder
    fi
  else
    read -p "$prompt [$current]: " new_value
    if [ -z "$new_value" ]; then
      new_value=$current
    fi
  fi

  if grep -q "^$key=" "$ENV_FILE"; then
    sed -i.bak "s|^$key=.*|$key=$new_value|" "$ENV_FILE" && rm "$ENV_FILE.bak"
  else
    echo "$key=$new_value" >> "$ENV_FILE"
  fi

  export $key=$new_value
}

print_url() {
  SUBDOMAIN=$(awk -F= '/^SUBDOMAIN=/ {print $2}' $ENV_FILE)
  DOMAIN_NAME=$(awk -F= '/^DOMAIN_NAME=/ {print $2}' $ENV_FILE)
  info "Your n8n instance should be available at: https://$SUBDOMAIN.$DOMAIN_NAME/"
}

deploy() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  else
    COMPOSE_CMD="docker compose"
  fi
  if ! $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE ps &>/dev/null; then
    info "Docker Compose is not running, starting it now..."
    $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE up -d || return 1
    info "Deployment finished!"
    print_url
  else
    info "Docker Compose is already running."
    read -p "Do you want to restart it? (y/n) " choice
    if [[ "$choice" =~ ^([yY]|[yY][eE][sS])$ ]]; then
      $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE down || return 1
      $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE up -d || return 1
      info "Deployment finished!"
      print_url
    fi
  fi
  return 0
}

stop_services() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  else
    COMPOSE_CMD="docker compose"
  fi

  info "Stopping n8n services..."
  $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE down || true
  info "n8n services stopped."

  info "Stopping Colima..."
  colima stop || true
  info "Colima stopped."

  info "All services and Colima have been stopped successfully."
}

tail_logs() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  else
    COMPOSE_CMD="docker compose"
  fi

  info "Tailing logs..."
  $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE logs -f || return 1
  return 0
}

get_status() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  else
    COMPOSE_CMD="docker compose"
  fi

  info "Getting status..."
  info "Current status of Colima:"
  colima status || return 1
  info "Current status of n8n services:"
  $COMPOSE_CMD --env-file $ENV_FILE -f $COMPOSE_FILE ps || return 1

  return 0
}

parse_args "$@"
intro
if [ "$ACTION" = "start" ]; then
  check_ws || exit 1
  check_sudo || exit 1
  install_deps || exit 1
  run_colima || exit 1
  ping_docker || exit 1
  create_cloudflare_tunnel || exit 1
  update_env_var "N8N_USER_EMAIL" "your_email@example.com" "Enter N8N admin email"
  update_env_var "N8N_USER_PASSWORD" "your_password" "Enter N8N admin password"
  update_env_var "SUBDOMAIN" "subdomain" "Enter subdomain"
  update_env_var "DOMAIN_NAME" "example.com" "Enter domain name"
  update_env_var "DB_POSTGRESDB_PASSWORD" "your_password" "Enter DB password"
  deploy || exit 1
  END_TIME=$(date +%s)
  ELAPSED_TIME=$((END_TIME - START_TIME))
  info "Total elapsed time: ${ELAPSED_TIME} seconds"
elif [ "$ACTION" = "stop" ]; then
  stop_services
  END_TIME=$(date +%s)
  ELAPSED_TIME=$((END_TIME - START_TIME))
  info "Total elapsed time: ${ELAPSED_TIME} seconds"
elif [ "$ACTION" = "logs" ]; then
  tail_logs || exit 1
elif [ "$ACTION" = "status" ]; then
  get_status || exit 1
else
  help
  exit 1
fi
