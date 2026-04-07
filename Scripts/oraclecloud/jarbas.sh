#!/usr/bin/env bash
# =============================================================================
#  JARBAS — Gerenciador Foundry VTT para Oracle Cloud
#  Repositório Original: https://github.com/brunocalado/mestre-digital
#  Repositório Refatorado:  https://github.com/mukasc/mestre-digital
#  Ajuda:       https://www.mestredigital.online
#  Refatorado por:  https://github.com/mukasc
# =============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# VERSÃO E CAMINHOS
# ------------------------------------------------------------------------------
VERSION="v3.0"
BASE_DIR="/home/ubuntu"
RUN_USER="ubuntu"
FOUNDRY_DIR="${BASE_DIR}/foundry"
DATA_DIR="${BASE_DIR}/.local/share/FoundryVTT"
CONF_FILE="${BASE_DIR}/.jarbas.conf"
JARBAS_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ------------------------------------------------------------------------------
# CORES ANSI
# ------------------------------------------------------------------------------
C_RESET="\033[0m"
C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[0;34m"
C_CYAN="\033[0;36m"
C_BOLD="\033[1m"

# ------------------------------------------------------------------------------
# HELPERS DE LOG
# ------------------------------------------------------------------------------
fn_log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET}  $*"; }
fn_log_ok()    { echo -e "${C_GREEN}[  OK]${C_RESET}  $*"; }
fn_log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*"; }
fn_log_error() { echo -e "${C_RED}[ERRO]${C_RESET}  $*" >&2; }
fn_separator() { echo -e "${C_CYAN}────────────────────────────────────────────────${C_RESET}"; }

fn_header() {
  echo -e "${C_CYAN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║          JARBAS ${VERSION} — Foundry VTT          ║"
  echo "  ║    https://www.mestredigital.online          ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${C_RESET}"
}

# ------------------------------------------------------------------------------
# CARREGAR / SALVAR CONFIGURAÇÃO PERSISTENTE
# ------------------------------------------------------------------------------
fn_load_conf() {
  if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
  fi
}

fn_save_conf() {
  {
    echo "# Jarbas Config — gerado automaticamente"
    echo "JARBAS_DOMAIN=\"${JARBAS_DOMAIN:-}\""
    echo "JARBAS_FOUNDRY_DIR=\"${FOUNDRY_DIR}\""
    echo "JARBAS_DATA_DIR=\"${DATA_DIR}\""
    echo "JARBAS_RUN_USER=\"${RUN_USER}\""
  } > "$CONF_FILE"
  fn_log_ok "Configuração salva em ${CONF_FILE}"
}

# Tenta carregar config ao iniciar
fn_load_conf 2>/dev/null || true

# ------------------------------------------------------------------------------
# VERIFICAÇÕES DE DEPENDÊNCIAS
# ------------------------------------------------------------------------------
fn_check_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    fn_log_error "Comando não encontrado: '${cmd}'. Execute './jarbas setup' primeiro."
    exit 1
  fi
}

fn_check_foundry() {
  if [[ ! -f "${FOUNDRY_DIR}/main.js" ]]; then
    fn_log_error "Foundry VTT não encontrado em ${FOUNDRY_DIR}/main.js"
    fn_log_info  "Use './jarbas admin instalar' para instalar o Foundry VTT."
    exit 1
  fi
}

fn_check_port() {
  local port="${1:-30000}"
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
     netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    fn_log_warn "A porta ${port} já está em uso. O servidor pode já estar rodando."
  fi
}

fn_fix_permissions() {
  fn_log_info "Corrigindo permissões de arquivos..."
  sudo chown -R "${RUN_USER}:${RUN_USER}" "${DATA_DIR}/" 2>/dev/null || true
  sudo chown -R "${RUN_USER}:${RUN_USER}" "${FOUNDRY_DIR}/" 2>/dev/null || true
  fn_log_ok "Permissões corrigidas."
}

# ------------------------------------------------------------------------------
# FUNÇÕES: GERENCIAR O FOUNDRY VTT
# ------------------------------------------------------------------------------
fn_start() {
  fn_log_info "Iniciando o Foundry VTT..."
  fn_stop 2>/dev/null || true
  fn_check_cmd node
  fn_check_cmd pm2
  fn_check_foundry
  fn_fix_permissions
  fn_check_port 30000

  pm2 start "${FOUNDRY_DIR}/main.js" \
    --name foundry \
    -- --dataPath="${DATA_DIR}"
  pm2 save
  fn_log_ok "Foundry VTT iniciado! Acesse: http://$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'SEU-IP'):30000"
}

fn_stop() {
  fn_log_info "Encerrando o Foundry VTT..."
  # Para silenciosamente mesmo que pm2 nao esteja instalado ou foundry nao esteja rodando
  if command -v pm2 &>/dev/null; then
    pm2 stop foundry 2>/dev/null || true
    pm2 delete foundry 2>/dev/null || true
  fi
  fn_log_ok "Foundry VTT encerrado."
}

fn_status() {
  fn_check_cmd pm2
  fn_separator
  fn_log_info "Status do processo Foundry VTT:"
  pm2 list
  fn_separator
}

fn_restart() {
  fn_start
}

# ------------------------------------------------------------------------------
# FUNÇÕES: INFORMAÇÕES DO SISTEMA
# ------------------------------------------------------------------------------
fn_versions() {
  fn_separator
  echo -e "${C_BOLD}Versões Instaladas${C_RESET}"
  fn_separator
  local node_v npm_v pm2_v so_v foundry_v
  node_v=$(node --version 2>/dev/null || echo "não instalado")
  npm_v=$(npm --version 2>/dev/null || echo "não instalado")
  pm2_v=$(pm2 --version 2>/dev/null || echo "não instalado")
  so_v=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "desconhecido")
  foundry_v=$(grep '"version"' "${FOUNDRY_DIR}/package.json" 2>/dev/null | head -1 | awk -F'"' '{print $4}' || echo "não encontrado")

  echo -e "  Node.js    : ${C_GREEN}${node_v}${C_RESET}"
  echo -e "  NPM        : ${C_GREEN}${npm_v}${C_RESET}"
  echo -e "  PM2        : ${C_GREEN}${pm2_v}${C_RESET}"
  echo -e "  Sistema Op.: ${C_GREEN}${so_v}${C_RESET}"
  echo -e "  Foundry VTT: ${C_GREEN}${foundry_v}${C_RESET}"
  echo -e "  Jarbas     : ${C_GREEN}${VERSION}${C_RESET}"
  fn_separator
}

fn_hardware() {
  fn_separator
  echo -e "${C_BOLD}Informações de Hardware${C_RESET}"
  fn_separator
  echo -e "${C_BOLD}[ Espaço em Disco ]${C_RESET}"
  df -h /
  echo
  echo -e "${C_BOLD}[ Memória RAM ]${C_RESET}"
  free -mh
  echo
  echo -e "${C_BOLD}[ Processador(es) ]${C_RESET}"
  lscpu | grep -E 'Model name|Socket|Thread|NUMA|CPU\(s\)'
  fn_separator
}

fn_support() {
  fn_separator
  echo -e "${C_BOLD}Dados de Suporte${C_RESET}"
  fn_separator

  local my_ip domain opts_json
  my_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "não detectado")
  opts_json="${DATA_DIR}/Config/options.json"
  domain=""
  if [[ -f "$opts_json" ]]; then
    if command -v jq &>/dev/null; then
      domain=$(jq -r '.hostname // "não configurado"' "$opts_json" 2>/dev/null)
    else
      domain=$(grep '"hostname"' "$opts_json" | awk -F'"' '{print $4}' 2>/dev/null || echo "não configurado")
    fi
  fi

  echo -e "  Usuário  : $(whoami)"
  echo -e "  Máquina  : $(hostname)"
  echo -e "  IP       : ${C_GREEN}${my_ip}${C_RESET}"
  echo -e "  Domínio  : ${C_GREEN}${domain}${C_RESET}"
  echo

  # Verificação do Foundry
  if [[ -f "${FOUNDRY_DIR}/main.js" ]]; then
    fn_log_ok "Foundry VTT está instalado em ${FOUNDRY_DIR}"
  else
    fn_log_error "Foundry VTT NÃO encontrado. Reinstale com './jarbas admin instalar'."
  fi
  echo

  # Teste de portas
  fn_separator
  echo -e "${C_BOLD}[ Teste de Portas ]${C_RESET}"
  fn_log_info "Testando conectividade nas portas principais..."
  for porta in 80 443 30000; do
    if timeout 2 bash -c "< /dev/tcp/${my_ip}/${porta}" &>/dev/null; then
      fn_log_ok "Porta ${porta}: ABERTA"
    else
      fn_log_warn "Porta ${porta}: FECHADA ou inacessível"
    fi
  done

  echo
  fn_separator
  echo -e "${C_BOLD}[ Firewall (ufw) ]${C_RESET}"
  sudo ufw status | grep -E "Status|ALLOW" || true

  echo
  fn_separator
  echo -e "${C_BOLD}[ Dicas de Solução de Problemas ]${C_RESET}"
  echo "  1. Reinicie a VM no painel da Oracle Cloud."
  echo "  2. Reinicie o Foundry: ./jarbas reiniciar"
  if [[ -n "$domain" ]]; then
    echo "  3. Acesse pelo domínio : https://${domain}"
  fi
  echo "  4. Acesse pelo IP     : http://${my_ip}:30000"
  echo "  5. Se o IP funcionar mas o domínio não: verifique o apontamento DNS."
  echo
  echo -e "  Mais ajuda: ${C_CYAN}https://www.mestredigital.online/post/guia-de-instalacao-do-foundry-vtt-na-oracle-cloud${C_RESET}"
  fn_separator
}

fn_fix_time() {
  fn_log_info "Configurando fuso horário para America/Sao_Paulo..."
  fn_separator
  echo "  Para escolher outro fuso horário, use: sudo dpkg-reconfigure tzdata"
  echo
  echo "America/Sao_Paulo" | sudo tee /etc/timezone
  sudo dpkg-reconfigure --frontend noninteractive tzdata
  fn_log_ok "Fuso horário configurado."
}

# ------------------------------------------------------------------------------
# FUNÇÕES: LOGS
# ------------------------------------------------------------------------------
fn_logs() {
  fn_check_cmd pm2
  case "${1:-}" in
    exportar)
      local outfile="${BASE_DIR}/jarbas-log-$(date +%Y%m%d-%H%M%S).txt"
      fn_log_info "Exportando últimas 500 linhas para ${outfile}..."
      pm2 logs foundry --nostream --lines 500 2>/dev/null > "$outfile" || true
      fn_log_ok "Log exportado: ${outfile}"
      ;;
    *)
      fn_log_info "Exibindo logs em tempo real. Pressione Ctrl+C para sair."
      pm2 logs foundry
      ;;
  esac
}

# ------------------------------------------------------------------------------
# FUNÇÕES: UPDATE
# ------------------------------------------------------------------------------
fn_update_jarbas() {
  fn_separator
  fn_log_info "Atualizando o Jarbas..."
  local tmp_file
  tmp_file=$(mktemp)
  if curl -fsSL --retry 3 \
    -H 'Cache-Control: no-cache' \
    -o "$tmp_file" \
    "https://raw.githubusercontent.com/mukasc/mestre-digital/refs/heads/master/Scripts/oraclecloud/jarbas.sh?$(date +%s)"; then
    mv "$tmp_file" "$JARBAS_SELF"
    chmod +x "$JARBAS_SELF"
    local new_version
    new_version=$(grep -m1 'VERSION=' "$JARBAS_SELF" | cut -d'"' -f2)
    fn_log_ok "Jarbas atualizado para: ${new_version}"
  else
    fn_log_error "Falha ao baixar o Jarbas. Verifique sua conexão."
    rm -f "$tmp_file"
    exit 1
  fi
  fn_separator
}

# ------------------------------------------------------------------------------
# FUNÇÕES: NODE.JS
# ------------------------------------------------------------------------------
fn_install_node() {
  fn_separator
  fn_log_info "Atualizando Node.js para a versão 22 (recomendada para Foundry VTT V13+)..."
  fn_separator

  # Verificar versão atual
  local current_node
  current_node=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1 || echo "0")
  if [[ "$current_node" == "22" ]]; then
    fn_log_warn "Node.js 22 já está instalado. Deseja forçar a reinstalação? (s/N)"
    read -r resposta
    if [[ ! "$resposta" =~ ^[Ss]$ ]]; then
      fn_log_info "Atualização cancelada."
      return 0
    fi
  fi

  read -r -p "$(echo -e "${C_YELLOW}Pressione Enter para continuar ou Ctrl+C para cancelar.${C_RESET}")"

  fn_stop 2>/dev/null || true
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl libssl-dev

  fn_log_info "Baixando e configurando repositório do Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
  sudo -E bash /tmp/nodesource_setup.sh
  rm -f /tmp/nodesource_setup.sh

  sudo apt-get update -qq
  sudo apt-get install -y -qq nodejs
  sudo apt-get -y -qq upgrade

  fn_log_ok "Node.js $(node --version) instalado com sucesso."
  fn_separator

  # Reinstalar pm2 globalmente após atualização do node
  fn_log_info "Reinstalando PM2 com a nova versão do Node..."
  sudo npm install -g pm2 --quiet
  fn_log_ok "PM2 $(pm2 --version) reinstalado."

  fn_start
  fn_log_info "Se encontrar problemas, reinicie a VM: sudo reboot"
  fn_separator
}

# ------------------------------------------------------------------------------
# FUNÇÕES: ADMIN
# ------------------------------------------------------------------------------
fn_admin_backup_config() {
  local conf="${DATA_DIR}/Config/options.json"
  if [[ -f "$conf" ]]; then
    local backup="${DATA_DIR}/Config/$(date +"%H%M-%d%m%Y")-options.json.bkp"
    cp "$conf" "$backup"
    fn_log_ok "Backup criado: ${backup}"
  fi
}

fn_admin_install_foundry_url() {
  fn_separator
  fn_log_info "Instalando Foundry VTT via link de download..."
  fn_log_warn "Isso removerá a pasta '${FOUNDRY_DIR}'. Os seus DADOS (worlds, systems, modules) NÃO serão afetados."
  read -r -p "$(echo -e "${C_YELLOW}Cole o link de download do Foundry VTT (Linux/Node.js) e pressione Enter:${C_RESET} ")" linkdownloadfoundry

  if [[ -z "$linkdownloadfoundry" ]]; then
    fn_log_error "Nenhum link fornecido. Operação cancelada."
    exit 1
  fi

  fn_stop 2>/dev/null || true
  fn_admin_backup_config

  cd "${BASE_DIR}" || exit 1
  rm -rf foundry
  mkdir -p foundry "${DATA_DIR}"
  cd foundry/ || exit 1

  fn_log_info "Baixando Foundry VTT..."
  curl --retry 3 --progress-bar -o fvtt.zip "${linkdownloadfoundry}"
  fn_log_info "Descompactando..."
  unzip -q fvtt.zip
  sudo chmod +x main.js
  rm -f fvtt.zip

  cd "${BASE_DIR}" || exit 1
  fn_log_ok "Foundry VTT instalado em ${FOUNDRY_DIR}"
  fn_start
  fn_separator
}

fn_admin_install_foundry_zip() {
  fn_separator
  fn_log_info "Instalando Foundry VTT via arquivo ZIP local..."

  local FILE="${BASE_DIR}/foundry.zip"
  if [[ ! -f "$FILE" ]]; then
    fn_log_error "Arquivo 'foundry.zip' não encontrado em ${BASE_DIR}."
    fn_log_info  "Faça o upload do arquivo ZIP (Linux/Node.js) via FileZilla e nomeie como: ~/foundry.zip"
    exit 1
  fi

  fn_log_ok "foundry.zip encontrado. Iniciando instalação..."
  fn_log_warn "Isso removerá a pasta '${FOUNDRY_DIR}'. Os seus DADOS não serão afetados."
  read -r -p "$(echo -e "${C_YELLOW}Pressione Enter para continuar ou Ctrl+C para cancelar.${C_RESET}")"

  fn_stop 2>/dev/null || true
  fn_admin_backup_config

  cd "${BASE_DIR}" || exit 1
  rm -rf foundry
  mkdir -p foundry "${DATA_DIR}"
  mv "$FILE" foundry/
  cd foundry/ || exit 1

  fn_log_info "Descompactando..."
  unzip -q foundry.zip
  sudo chmod +x main.js
  rm -f foundry.zip

  cd "${BASE_DIR}" || exit 1
  fn_log_ok "Foundry VTT instalado em ${FOUNDRY_DIR}"
  fn_start
  fn_separator
}

fn_admin_remove_password() {
  fn_log_info "Removendo senha de administração do Foundry VTT..."
  fn_stop 2>/dev/null || true
  local admin_file="${DATA_DIR}/Config/admin.txt"
  if [[ -f "$admin_file" ]]; then
    rm -f "$admin_file"
    fn_log_ok "Senha removida. Acesse o Foundry VTT sem senha de admin."
  else
    fn_log_warn "Nenhuma senha de admin encontrada (arquivo não existe)."
  fi
  fn_start
}

fn_admin_reset_config() {
  fn_log_info "Restaurando arquivo de configuração do Foundry VTT para o padrão..."
  fn_admin_backup_config
  fn_stop 2>/dev/null || true
  rm -f "${DATA_DIR}/Config/options.json"
  fn_log_ok "Configuração resetada. O Foundry VTT gerará um novo arquivo ao iniciar."
  fn_start
}

# ------------------------------------------------------------------------------
# FUNÇÕES: SWAP
# ------------------------------------------------------------------------------
fn_swap_status() {
  fn_separator
  echo -e "${C_BOLD}Estado da SWAP${C_RESET}"
  free -mh | grep -E "Mem|Swap"
  fn_separator
}

fn_swap_enable() {
  fn_separator
  fn_log_warn "ATENÇÃO: Use SWAP apenas em máquinas com pouca RAM. NÃO use em ARM."
  fn_log_warn "Isso consumirá 2GB de espaço em disco."
  read -r -p "$(echo -e "${C_YELLOW}Deseja continuar? (s/N): ${C_RESET}")" resposta
  if [[ ! "$resposta" =~ ^[Ss]$ ]]; then
    fn_log_info "Operação cancelada."
    return 0
  fi

  if swapon --show | grep -q '/swapfile'; then
    fn_log_warn "SWAP já está ativa."
    fn_swap_status
    return 0
  fi

  fn_log_info "Criando e ativando SWAP de 2GB..."
  if [[ -f /swapfile ]]; then
    fn_log_warn "/swapfile já existe. Ativando sem recriar..."
    sudo swapon /swapfile 2>/dev/null || true
  else
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile   none    swap    sw    0   0' | sudo tee -a /etc/fstab > /dev/null
  fi
  fn_log_ok "SWAP de 2GB ativada com sucesso."
  fn_swap_status
  fn_separator
}

# ------------------------------------------------------------------------------
# FUNÇÕES: FIREWALL
# ------------------------------------------------------------------------------
fn_firewall_status() {
  fn_separator
  echo -e "${C_BOLD}Estado do Firewall (ufw)${C_RESET}"
  sudo ufw status numbered
  fn_separator
}

fn_firewall_enable() {
  fn_separator
  fn_log_info "Instalando e configurando o firewall ufw..."
  sudo apt-get -y -qq install ufw
  sudo ufw allow 22/tcp   comment "SSH"
  sudo ufw allow 80/tcp   comment "HTTP"
  sudo ufw allow 443/tcp  comment "HTTPS"
  sudo ufw allow 443/udp  comment "HTTPS/UDP"
  sudo ufw allow 30000/tcp comment "Foundry VTT"
  sudo ufw --force enable
  fn_log_ok "Firewall configurado e ativo."
  fn_log_info "Se ainda não funcionar, reinicie a VM."
  fn_separator
}

# ------------------------------------------------------------------------------
# FUNÇÕES: CADDY
# ------------------------------------------------------------------------------
fn_caddy_install() {
  fn_separator
  fn_log_info "Instalando Caddy (servidor web/proxy reverso)..."
  sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy
  fn_log_ok "Caddy instalado: $(caddy version 2>/dev/null || echo 'OK')"
  fn_separator

  fn_caddy_config
}

fn_caddy_config() {
  fn_separator
  fn_log_info "Configurando o Caddy para o Foundry VTT..."
  fn_stop 2>/dev/null || true
  sudo service caddy stop 2>/dev/null || true

  read -r -p "$(echo -e "${C_YELLOW}Digite o seu domínio e pressione Enter: ${C_RESET}")" dominio

  if [[ -z "$dominio" ]]; then
    fn_log_error "Domínio não fornecido. Operação cancelada."
    exit 1
  fi

  # Salvar domínio na config
  JARBAS_DOMAIN="$dominio"
  fn_save_conf

  fn_log_info "Baixando e configurando Caddyfile para '${dominio}'..."
  curl -fsSL -o /tmp/Caddyfile \
    "https://raw.githubusercontent.com/mukasc/mestre-digital/refs/heads/master/Scripts/caddy/Caddyfile.txt"
  sed -i "s+MEUDOMINIOFOUNDRY+${dominio}+g" /tmp/Caddyfile
  sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile

  # Atualizar options.json com jq (se disponível) ou sed (fallback)
  local opts_json="${DATA_DIR}/Config/options.json"
  if [[ -f "$opts_json" ]]; then
    fn_admin_backup_config
    if command -v jq &>/dev/null; then
      fn_log_info "Atualizando options.json com jq..."
      jq --arg d "$dominio" \
        '.hostname = $d | .proxySSL = true | .proxyPort = 443' \
        "$opts_json" > /tmp/options.tmp && mv /tmp/options.tmp "$opts_json"
    else
      fn_log_warn "jq não encontrado. Usando sed como fallback..."
      sed -i "s+\"hostname\":.*,+\"hostname\": \"${dominio}\",+g" "$opts_json"
      sed -i 's+"proxySSL": false+"proxySSL": true+g' "$opts_json"
      sed -i 's+"proxyPort": null+"proxyPort": 443+g' "$opts_json"
    fi
    fn_log_ok "options.json atualizado."
  fi

  sudo service caddy start
  fn_start
  fn_log_ok "Caddy configurado! Acesse: https://${dominio}"
  fn_separator
}

fn_caddy_file() {
  fn_separator
  echo -e "${C_BOLD}Arquivo do Caddy (/etc/caddy/Caddyfile)${C_RESET}"
  fn_separator
  cat /etc/caddy/Caddyfile 2>/dev/null || fn_log_warn "Caddyfile não encontrado."
  fn_separator
  echo -e "${C_BOLD}Arquivo de Configuração do Foundry VTT (${DATA_DIR}/Config/options.json)${C_RESET}"
  fn_separator
  cat "${DATA_DIR}/Config/options.json" 2>/dev/null || fn_log_warn "options.json não encontrado."
  fn_separator
  echo -e "  Para editar manualmente: ${C_CYAN}nano /etc/caddy/Caddyfile${C_RESET}"
}

fn_caddy_manage() {
  local action="${1:-}"
  case "$action" in
    start)
      fn_log_info "Iniciando o Caddy..."
      sudo service caddy start
      fn_log_ok "Caddy iniciado."
      ;;
    stop)
      fn_log_info "Encerrando o Caddy..."
      sudo service caddy stop
      fn_log_ok "Caddy encerrado."
      ;;
    restart)
      fn_log_info "Reiniciando o Caddy..."
      sudo service caddy restart
      fn_log_ok "Caddy reiniciado."
      ;;
    status)
      fn_log_info "Status do Caddy (pressione 'q' para sair):"
      sudo service caddy status
      ;;
    *)
      fn_log_error "Ação desconhecida para caddy: '${action}'"
      echo "Opções: {instalar|config|arquivo|start|stop|restart|status}"
      exit 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# FUNÇÕES: SETUP INICIAL
# ------------------------------------------------------------------------------
fn_setup() {
  fn_separator
  fn_log_info "CONFIGURAÇÕES INICIAIS DO SERVIDOR"
  fn_separator

  # Firewall
  fn_firewall_enable

  # Dependências básicas
  fn_log_info "Instalando dependências básicas..."
  sudo apt-get update -qq
  sudo apt-get -y -qq install zip unzip vim curl jq

  # Instala Node.js 22 PRIMEIRO (pm2 depende do node)
  fn_install_node

  # Instala e configura PM2 (fn_install_node já instala o pm2, aqui configuramos o startup)
  fn_log_info "Configurando PM2 para auto-inicialização..."
  pm2 startup 2>/dev/null || true
  sudo env PATH="$PATH:/usr/bin" \
    /usr/lib/node_modules/pm2/bin/pm2 startup systemd \
    -u "${RUN_USER}" --hp "${BASE_DIR}" 2>/dev/null || true

  # Instala Foundry VTT
  fn_admin_install_foundry_url

  # Cria atalhos simbólicos
  fn_log_info "Criando atalhos..."
  [[ -L data   ]] || ln -s "${DATA_DIR}/Data/"   data   2>/dev/null || true
  [[ -L config ]] || ln -s "${DATA_DIR}/Config/" config 2>/dev/null || true
  [[ -L logs   ]] || ln -s "${DATA_DIR}/Logs/"   logs   2>/dev/null || true
  fn_log_ok "Atalhos: ~/data, ~/config, ~/logs"

  pm2 save

  # Salvar config persistente
  fn_save_conf

  # Logo
  curl -fsSL -o /tmp/md \
    "https://raw.githubusercontent.com/brunocalado/mestre-digital/master/Scripts/logo.txt" \
    && cat /tmp/md && rm -f /tmp/md || true

  fn_log_ok "Setup concluído!"
  read -r -p "$(echo -e "${C_YELLOW}A máquina será reiniciada. Pressione Enter para continuar.${C_RESET}")"
  sudo reboot
}

# ------------------------------------------------------------------------------
# FUNÇÕES: OUTROS
# ------------------------------------------------------------------------------
fn_sobre() {
  curl -fsSL \
    "https://raw.githubusercontent.com/brunocalado/mestre-digital/master/Scripts/logo.txt" \
    -o /tmp/md && cat /tmp/md && rm -f /tmp/md || true
  echo -e "  ${C_CYAN}https://www.mestredigital.online/colabore-com-o-mestre-digital${C_RESET}"
  echo
  echo -e "  Ajuda: ${C_CYAN}https://www.mestredigital.online/post/guia-de-instalacao-do-foundry-vtt-na-oracle-cloud${C_RESET}"
}

fn_compactar() {
  fn_separator
  echo -e "${C_BOLD}Como Compactar Seus Arquivos${C_RESET}"
  fn_separator
  echo "  Para facilitar a transferência entre sua máquina e a nuvem,"
  echo "  compacte os arquivos antes de transferir."
  echo
  echo -e "  ${C_BOLD}Compactar:${C_RESET}"
  echo -e "  ${C_CYAN}zip -r data.zip data/${C_RESET}"
  echo "  (copia tudo de data/ — systems, worlds, modules — para data.zip)"
  echo
  echo -e "  ${C_BOLD}Descompactar:${C_RESET}"
  echo -e "  ${C_CYAN}unzip data.zip${C_RESET}"
  echo "  (descompacta no diretório atual)"
  fn_separator
}

# ------------------------------------------------------------------------------
# FUNÇÕES: BACKUP
# ------------------------------------------------------------------------------
fn_backup() {
  local subcomando="${1:-criar}"

  case "$subcomando" in
    criar)
      fn_separator
      fn_log_info "Criando backup dos dados do Foundry VTT..."
      fn_log_warn "Isso pode demorar alguns minutos dependendo do tamanho dos seus dados."

      # Verificar se há espaço suficiente (ao menos 200MB livres)
      local free_kb
      free_kb=$(df "${BASE_DIR}" | awk 'NR==2 {print $4}')
      if (( free_kb < 204800 )); then
        fn_log_warn "Atenção: menos de 200MB livres em disco. O backup pode falhar."
        fn_log_info "Use './jarbas hardware' para verificar o espaço disponível."
      fi

      local timestamp
      timestamp=$(date +"%Y%m%d-%H%M%S")
      local backup_dir="${BASE_DIR}/backups"
      local backup_file="${backup_dir}/foundry-data-${timestamp}.zip"

      mkdir -p "$backup_dir"

      # Para o Foundry para evitar corrupção de dados durante o backup
      fn_log_info "Pausando o Foundry VTT para garantir integridade dos dados..."
      pm2 stop foundry 2>/dev/null || true

      fn_log_info "Compactando dados: worlds, systems, modules, Config..."
      cd "${BASE_DIR}" || exit 1
      zip -r "$backup_file" \
        .local/share/FoundryVTT/Data/worlds/ \
        .local/share/FoundryVTT/Data/systems/ \
        .local/share/FoundryVTT/Data/modules/ \
        .local/share/FoundryVTT/Config/ \
        2>/dev/null || true

      # Reinicia o Foundry (sempre, mesmo se o zip falhou parcialmente)
      fn_log_info "Reiniciando o Foundry VTT..."
      fn_start || fn_log_warn "Não foi possível reiniciar automaticamente. Use: ./jarbas ligar"

      if [[ -f "$backup_file" ]]; then
        local size
        size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "?")
        fn_log_ok "Backup criado com sucesso!"
        fn_log_ok "Arquivo : ${backup_file}"
        fn_log_ok "Tamanho : ${size}"
      else
        fn_log_error "O arquivo de backup não foi gerado. Verifique o espaço em disco."
      fi
      fn_separator
      echo -e "  ${C_BOLD}Para restaurar este backup:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas backup restaurar${C_RESET}"
      fn_separator
      ;;

    listar)
      fn_separator
      echo -e "${C_BOLD}Backups Disponíveis${C_RESET}"
      fn_separator
      local backup_dir="${BASE_DIR}/backups"
      if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        fn_log_warn "Nenhum backup encontrado em ${backup_dir}"
        fn_log_info "Crie um com: ./jarbas backup criar"
      else
        ls -lh "${backup_dir}/"*.zip 2>/dev/null | awk '{print "  "$5"\t"$9}' || true
        echo
        local total
        total=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "?")
        echo -e "  Total ocupado por backups: ${C_YELLOW}${total}${C_RESET}"
      fi
      fn_separator
      ;;

    restaurar)
      fn_separator
      echo -e "${C_BOLD}Restaurar Backup${C_RESET}"
      fn_separator
      local backup_dir="${BASE_DIR}/backups"

      # Listar arquivos disponíveis
      local backups
      mapfile -t backups < <(ls -t "${backup_dir}/"*.zip 2>/dev/null)

      if [[ ${#backups[@]} -eq 0 ]]; then
        fn_log_error "Nenhum backup encontrado em ${backup_dir}"
        fn_log_info  "Crie um com: ./jarbas backup criar"
        exit 1
      fi

      echo -e "  ${C_BOLD}Backups disponíveis (mais recente primeiro):${C_RESET}"
      local i=1
      for f in "${backups[@]}"; do
        local sz
        sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
        echo -e "  ${C_CYAN}[$i]${C_RESET} $(basename "$f")  (${sz})"
        (( i++ ))
      done
      echo
      read -r -p "$(echo -e "${C_YELLOW}Digite o número do backup para restaurar (ou Enter para cancelar): ${C_RESET}")" escolha

      if [[ -z "$escolha" ]]; then
        fn_log_info "Operação cancelada."
        exit 0
      fi

      local idx
      idx=$(( escolha - 1 ))
      if [[ $idx -lt 0 ]] || [[ $idx -ge ${#backups[@]} ]]; then
        fn_log_error "Número inválido."
        exit 1
      fi

      local selected="${backups[$idx]}"
      fn_log_warn "Isso VAI SOBRESCREVER seus dados atuais com o backup: $(basename "$selected")"
      read -r -p "$(echo -e "${C_YELLOW}Tem certeza? (s/N): ${C_RESET}")" confirm
      if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        fn_log_info "Operação cancelada."
        exit 0
      fi

      fn_log_info "Parando o Foundry VTT..."
      pm2 stop foundry 2>/dev/null || true

      fn_log_info "Restaurando backup $(basename "$selected")..."
      cd "${BASE_DIR}" || exit 1
      unzip -o -q "$selected" 2>/dev/null
      fn_fix_permissions

      fn_log_info "Reiniciando o Foundry VTT..."
      fn_start

      fn_log_ok "Backup restaurado com sucesso!"
      fn_separator
      ;;

    *)
      fn_separator
      echo -e "${C_BOLD}Subcomandos de 'backup':${C_RESET}"
      echo "  criar      — cria um backup dos dados (worlds, systems, modules, Config)"
      echo "  listar     — lista todos os backups disponíveis"
      echo "  restaurar  — restaura um backup com seleção interativa"
      echo
      echo "  Exemplo: ./jarbas backup criar"
      fn_separator
      exit 1
      ;;
  esac
}

fn_login2left() {
  fn_log_warn "Tenha certeza do que está fazendo!"
  local tmp_css
  tmp_css=$(mktemp)
  curl -fsSL -H 'Cache-Control: no-cache' \
    -o "$tmp_css" \
    "https://raw.githubusercontent.com/brunocalado/mestre-digital/master/Foundry%20VTT/css/text-left-no-title.css?$(date +%s)"
  cat "$tmp_css" >> "${FOUNDRY_DIR}/public/css/style.css"
  rm -f "$tmp_css"
  fn_log_ok "CSS de login aplicado."
}

# ------------------------------------------------------------------------------
# FUNÇÃO: AJUDA DETALHADA
# ------------------------------------------------------------------------------
fn_help() {
  local tema="${1:-}"

  # Se um comando específico for pedido, exibe ajuda detalhada só dele
  case "$tema" in
    ligar)
      fn_separator
      echo -e "${C_BOLD}COMANDO: ligar${C_RESET}"
      fn_separator
      echo "  Inicia o servidor Foundry VTT usando o gerenciador de processos PM2."
      echo
      echo "  O que este comando faz:"
      echo "    1. Para qualquer instância anterior do Foundry em execução"
      echo "    2. Verifica se o Node.js e o PM2 estão instalados"
      echo "    3. Verifica se o Foundry VTT está instalado corretamente"
      echo "    4. Corrige permissões de arquivos automaticamente"
      echo "    5. Inicia o Foundry e salva o processo no PM2"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas ligar${C_RESET}"
      fn_separator
      ;;
    desligar)
      fn_separator
      echo -e "${C_BOLD}COMANDO: desligar${C_RESET}"
      fn_separator
      echo "  Para o servidor Foundry VTT. Seguro de executar mesmo se o servidor"
      echo "  já estiver parado (não gera erros)."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas desligar${C_RESET}"
      fn_separator
      ;;
    reiniciar)
      fn_separator
      echo -e "${C_BOLD}COMANDO: reiniciar${C_RESET}"
      fn_separator
      echo "  Para e inicia o servidor Foundry VTT em sequência."
      echo "  Equivalente a rodar 'desligar' e depois 'ligar'."
      echo "  Útil após instalar um módulo ou system manualmente."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas reiniciar${C_RESET}"
      fn_separator
      ;;
    status)
      fn_separator
      echo -e "${C_BOLD}COMANDO: status${C_RESET}"
      fn_separator
      echo "  Exibe o painel do PM2 com informações sobre o processo do Foundry:"
      echo "    - Se está online, parado ou com erro"
      echo "    - Uso de CPU e memória"
      echo "    - Tempo online"
      echo "    - Número de reinicializações automáticas"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas status${C_RESET}"
      fn_separator
      ;;
    logs)
      fn_separator
      echo -e "${C_BOLD}COMANDO: logs${C_RESET}"
      fn_separator
      echo "  Acessa os logs do servidor Foundry VTT."
      echo
      echo "  Subcomandos:"
      echo "    (sem subcomando)  Exibe logs em tempo real. Pressione Ctrl+C para sair."
      echo "    exportar          Salva as últimas 500 linhas em ~/jarbas-log-DATA.txt"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas logs${C_RESET}           # tempo real"
      echo -e "  ${C_CYAN}./jarbas logs exportar${C_RESET}  # salva em arquivo"
      fn_separator
      ;;
    backup)
      fn_separator
      echo -e "${C_BOLD}COMANDO: backup${C_RESET}"
      fn_separator
      echo "  Gerencia backups dos dados do Foundry VTT (worlds, systems, modules, Config)."
      echo "  Os backups são salvos em: ~/backups/"
      echo
      echo "  IMPORTANTE: Sempre faça um backup ANTES de atualizar a versão do Foundry."
      echo "  O Foundry migra dados ao atualizar e essa migração é unidirecional."
      echo
      echo "  Subcomandos:"
      echo "    criar      Para o Foundry, compacta os dados e reinicia em seguida"
      echo "    listar     Mostra todos os backups disponíveis com tamanho e data"
      echo "    restaurar  Menu interativo para escolher e restaurar um backup"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas backup criar${C_RESET}      # antes de um upgrade"
      echo -e "  ${C_CYAN}./jarbas backup listar${C_RESET}     # ver backups disponíveis"
      echo -e "  ${C_CYAN}./jarbas backup restaurar${C_RESET}  # voltar a uma versão anterior"
      fn_separator
      ;;
    admin)
      fn_separator
      echo -e "${C_BOLD}COMANDO: admin${C_RESET}"
      fn_separator
      echo "  Funções administrativas do Foundry VTT."
      echo
      echo "  Subcomandos:"
      echo
      echo "  instalar"
      echo "    Instala ou reinstala o Foundry VTT usando o link de download temporário"
      echo "    do site oficial. Use sempre o link da versão Linux/Node.js."
      echo "    ATENÇÃO: Remove a pasta '~/foundry'. Seus dados NÃO são apagados."
      echo
      echo "  instalarzip"
      echo "    Instala o Foundry a partir de um arquivo 'foundry.zip' que você"
      echo "    fez upload na pasta principal via FileZilla ou similar."
      echo "    ATENÇÃO: Remove a pasta '~/foundry'. Seus dados NÃO são apagados."
      echo
      echo "  removesenha"
      echo "    Remove o arquivo 'admin.txt' que guarda a senha do Foundry."
      echo "    Use quando esquecer a senha de administrador."
      echo
      echo "  resetaconfig"
      echo "    Remove o 'options.json' do Foundry, restaurando as configurações"
      echo "    para o padrão. O Foundry criará um novo arquivo ao iniciar."
      echo "    Um backup da config é criado automaticamente antes da remoção."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas admin instalar${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas admin instalarzip${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas admin removesenha${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas admin resetaconfig${C_RESET}"
      fn_separator
      ;;
    node)
      fn_separator
      echo -e "${C_BOLD}COMANDO: node${C_RESET}"
      fn_separator
      echo "  Atualiza o Node.js para a versão 22 (recomendada para o Foundry VTT V13+)."
      echo
      echo "  O que este comando faz:"
      echo "    1. Verifica a versão atual do Node.js instalada"
      echo "    2. Pede confirmação antes de reinstalar se já estiver na v22"
      echo "    3. Para o Foundry VTT"
      echo "    4. Configura o repositório oficial do Node.js 22"
      echo "    5. Instala o Node.js via apt"
      echo "    6. Reinstala o PM2 com a nova versão do Node"
      echo "    7. Reinicia o Foundry VTT"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas node${C_RESET}"
      fn_separator
      ;;
    setup)
      fn_separator
      echo -e "${C_BOLD}COMANDO: setup${C_RESET}"
      fn_separator
      echo "  Configuração inicial completa de um servidor novo."
      echo "  Execute este comando apenas UMA VEZ, após acessar o servidor pela primeira vez."
      echo
      echo "  O que este comando faz em ordem:"
      echo "    1. Configura e ativa o firewall (ufw)"
      echo "    2. Instala dependências (zip, unzip, vim, curl, jq)"
      echo "    3. Instala o Node.js 22"
      echo "    4. Configura o PM2 para auto-inicialização com a VM"
      echo "    5. Instala o Foundry VTT (pede o link de download)"
      echo "    6. Cria atalhos: ~/data, ~/config, ~/logs"
      echo "    7. Salva as configurações em ~/.jarbas.conf"
      echo "    8. Reinicia a máquina"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas setup${C_RESET}"
      fn_separator
      ;;
    update)
      fn_separator
      echo -e "${C_BOLD}COMANDO: update${C_RESET}"
      fn_separator
      echo "  Baixa e instala a última versão do Jarbas do repositório oficial."
      echo "  O servidor Foundry VTT NÃO é afetado por este comando."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas update${C_RESET}"
      fn_separator
      ;;
    caddy)
      fn_separator
      echo -e "${C_BOLD}COMANDO: caddy${C_RESET}"
      fn_separator
      echo "  Gerencia o Caddy, um servidor web que funciona como proxy reverso"
      echo "  e fornece HTTPS automático via Let's Encrypt para o seu domínio."
      echo
      echo "  Subcomandos:"
      echo "    instalar  Instala o Caddy via repositório oficial e já configura"
      echo "    config    Configura o Caddy com seu domínio (atualiza Caddyfile"
      echo "              e options.json do Foundry autom.)"
      echo "    arquivo   Exibe o conteúdo atual do Caddyfile e do options.json"
      echo "    start     Inicia o serviço do Caddy"
      echo "    stop      Para o serviço do Caddy"
      echo "    restart   Reinicia o serviço do Caddy"
      echo "    status    Exibe o estado do serviço do Caddy"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas caddy instalar${C_RESET}   # primeira vez"
      echo -e "  ${C_CYAN}./jarbas caddy config${C_RESET}     # configurar domínio"
      echo -e "  ${C_CYAN}./jarbas caddy restart${C_RESET}    # após mudar configurações"
      fn_separator
      ;;
    firewall)
      fn_separator
      echo -e "${C_BOLD}COMANDO: firewall${C_RESET}"
      fn_separator
      echo "  Gerencia o firewall ufw no servidor."
      echo
      echo "  Portas liberadas pelo 'ativar':"
      echo "    22    — SSH (acesso ao servidor)"
      echo "    80    — HTTP"
      echo "    443   — HTTPS (TCP e UDP)"
      echo "    30000 — Foundry VTT (acesso direto sem domínio)"
      echo
      echo "  Subcomandos:"
      echo "    status  Mostra as regras ativas do firewall"
      echo "    ativar  Instala e habilita o ufw com as portas necessárias"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas firewall status${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas firewall ativar${C_RESET}"
      fn_separator
      ;;
    swap)
      fn_separator
      echo -e "${C_BOLD}COMANDO: swap${C_RESET}"
      fn_separator
      echo "  Gerencia a memória SWAP (memória virtual em disco)."
      echo
      echo "  ATENÇÃO:"
      echo "    - Use apenas em máquinas com pouca RAM (ex: instância Free Tier Oracle)"
      echo "    - NÃO use em máquinas ARM (Ampere) — já têm RAM suficiente"
      echo "    - O 'ativar' deve ser executado apenas UMA VEZ"
      echo "    - Consome 2GB de espaço em disco"
      echo
      echo "  Subcomandos:"
      echo "    status  Exibe se a SWAP está ativa e quanto está sendo usado"
      echo "    ativar  Cria e ativa um arquivo SWAP de 2GB"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas swap status${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas swap ativar${C_RESET}"
      fn_separator
      ;;
    hardware)
      fn_separator
      echo -e "${C_BOLD}COMANDO: hardware${C_RESET}"
      fn_separator
      echo "  Exibe informações de hardware do servidor:"
      echo "    - Espaço em disco (uso e livre)"
      echo "    - Memória RAM total e usada"
      echo "    - Modelo e número de processadores"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas hardware${C_RESET}"
      fn_separator
      ;;
    versao)
      fn_separator
      echo -e "${C_BOLD}COMANDO: versao${C_RESET}"
      fn_separator
      echo "  Exibe as versões instaladas de todos os componentes:"
      echo "    Node.js, NPM, PM2, Sistema Operacional, Foundry VTT e Jarbas."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas versao${C_RESET}"
      fn_separator
      ;;
    suporte)
      fn_separator
      echo -e "${C_BOLD}COMANDO: suporte${C_RESET}"
      fn_separator
      echo "  Executa um diagnóstico completo do servidor. Útil para identificar"
      echo "  problemas e ao pedir ajuda no fórum ou suporte."
      echo
      echo "  O que o suporte verifica:"
      echo "    - IP público do servidor"
      echo "    - Domínio configurado"
      echo "    - Se o Foundry VTT está instalado corretamente"
      echo "    - Se as portas 80, 443 e 30000 estão acessíveis externamente"
      echo "    - Estado do firewall ufw"
      echo "    - Dicas de solução de problemas"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas suporte${C_RESET}"
      fn_separator
      ;;
    horacerta)
      fn_separator
      echo -e "${C_BOLD}COMANDO: horacerta${C_RESET}"
      fn_separator
      echo "  Configura o fuso horário do servidor para America/Sao_Paulo."
      echo "  Para escolher outro fuso, use: sudo dpkg-reconfigure tzdata"
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas horacerta${C_RESET}"
      fn_separator
      ;;
    compactar)
      fn_separator
      echo -e "${C_BOLD}COMANDO: compactar${C_RESET}"
      fn_separator
      echo "  Exibe instruções de como compactar e descompactar seus arquivos"
      echo "  para facilitar a transferência via FileZilla ou similar."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas compactar${C_RESET}"
      fn_separator
      ;;
    sobre)
      fn_separator
      echo -e "${C_BOLD}COMANDO: sobre${C_RESET}"
      fn_separator
      echo "  Exibe informações sobre o desenvolvedor e links do Mestre Digital."
      echo
      echo -e "  ${C_BOLD}Uso:${C_RESET}"
      echo -e "  ${C_CYAN}./jarbas sobre${C_RESET}"
      fn_separator
      ;;

    # Sem argumento: exibe o menu geral
    *)
      fn_header
      fn_separator
      echo -e "${C_BOLD}Uso:${C_RESET} ./jarbas <comando> [subcomando]"
      echo -e "      ./jarbas ajuda <comando>   para ajuda detalhada de um comando"
      fn_separator

      echo -e "${C_BOLD}[ Servidor Foundry VTT ]${C_RESET}"
      echo -e "  ${C_GREEN}ligar${C_RESET}              Inicia o servidor Foundry VTT"
      echo -e "  ${C_GREEN}desligar${C_RESET}           Para o servidor"
      echo -e "  ${C_GREEN}reiniciar${C_RESET}          Para e reinicia o servidor"
      echo -e "  ${C_GREEN}status${C_RESET}             Exibe o status do processo no PM2"
      echo -e "  ${C_GREEN}logs${C_RESET}               Logs em tempo real (Ctrl+C para sair)"
      echo -e "  ${C_GREEN}logs exportar${C_RESET}      Salva logs em arquivo"
      echo

      echo -e "${C_BOLD}[ Backup ]${C_RESET}"
      echo -e "  ${C_GREEN}backup criar${C_RESET}       Cria backup de worlds/systems/modules/Config"
      echo -e "  ${C_GREEN}backup listar${C_RESET}      Lista backups disponíveis"
      echo -e "  ${C_GREEN}backup restaurar${C_RESET}   Restaura um backup (interativo)"
      echo

      echo -e "${C_BOLD}[ Instalação e Atualização ]${C_RESET}"
      echo -e "  ${C_CYAN}setup${C_RESET}                      Configuração inicial do servidor (1x)"
      echo -e "  ${C_CYAN}node${C_RESET}                       Atualiza o Node.js para a v22"
      echo -e "  ${C_CYAN}update${C_RESET}                     Atualiza o Jarbas"
      echo -e "  ${C_CYAN}admin instalar${C_RESET}             Instala Foundry via link de download"
      echo -e "  ${C_CYAN}admin instalarzip${C_RESET}          Instala Foundry via arquivo .zip"
      echo -e "  ${C_CYAN}admin removesenha${C_RESET}          Remove senha do painel admin"
      echo -e "  ${C_CYAN}admin resetaconfig${C_RESET}         Restaura options.json ao padrão"
      echo

      echo -e "${C_BOLD}[ Rede e Segurança ]${C_RESET}"
      echo -e "  ${C_YELLOW}firewall status${C_RESET}            Mostra regras do firewall"
      echo -e "  ${C_YELLOW}firewall ativar${C_RESET}            Configura ufw (portas 22,80,443,30000)"
      echo -e "  ${C_YELLOW}caddy instalar${C_RESET}             Instala o Caddy (HTTPS automático)"
      echo -e "  ${C_YELLOW}caddy config${C_RESET}               Configura domínio e SSL"
      echo -e "  ${C_YELLOW}caddy arquivo${C_RESET}              Exibe Caddyfile e options.json"
      echo -e "  ${C_YELLOW}caddy start|stop|restart|status${C_RESET}  Gerencia o serviço"
      echo

      echo -e "${C_BOLD}[ Sistema ]${C_RESET}"
      echo -e "  hardware           Informações de disco, RAM e CPU"
      echo -e "  versao             Versões instaladas (Node, PM2, Foundry...)"
      echo -e "  suporte            Diagnóstico completo do servidor"
      echo -e "  horacerta          Ajusta o fuso horário (Sao_Paulo)"
      echo -e "  swap status        Estado da memória SWAP"
      echo -e "  swap ativar        Ativa SWAP de 2GB (apenas x86, 1x)"
      echo -e "  compactar          Instruções para compactar arquivos"
      echo -e "  sobre              Sobre o desenvolvedor"
      echo

      echo -e "  ${C_BOLD}Dica:${C_RESET} ${C_CYAN}./jarbas ajuda backup${C_RESET}  — exibe ajuda detalhada sobre qualquer comando"
      fn_separator
      exit 1
      ;;
  esac
}

# =============================================================================
# DISPATCHER PRINCIPAL
# =============================================================================
fn_header

case "${1:-}" in
  ligar)        fn_start ;;
  desligar)     fn_stop ;;
  reiniciar)    fn_restart ;;
  status)       fn_status ;;
  versao)       fn_versions ;;
  hardware)     fn_hardware ;;
  suporte)      fn_support ;;
  horacerta)    fn_fix_time ;;
  update)       fn_update_jarbas ;;
  sobre)        fn_sobre ;;
  compactar)    fn_compactar ;;
  setup)        fn_setup ;;
  login2left)   fn_login2left ;;
  node)         fn_install_node ;;
  logs)         fn_logs "${@:2}" ;;
  backup)       fn_backup "${@:2}" ;;
  ajuda)        fn_help "${@:2}" ;;

  admin)
    case "${2:-}" in
      instalar)       fn_admin_install_foundry_url ;;
      instalarzip)    fn_admin_install_foundry_zip ;;
      removesenha)    fn_admin_remove_password ;;
      resetaconfig)   fn_admin_reset_config ;;
      *)
        fn_separator
        echo -e "${C_BOLD}Subcomandos de 'admin':${C_RESET}"
        echo "  instalar      — instala via link do site Foundry VTT (Linux/Node.js)"
        echo "  instalarzip   — instala via arquivo foundry.zip (upload via FileZilla)"
        echo "  removesenha   — remove a senha do painel admin do Foundry"
        echo "  resetaconfig  — restaura o options.json para o padrão"
        echo
        echo "  Exemplo: ./jarbas admin removesenha"
        fn_separator
        exit 1
        ;;
    esac
    ;;

  swap)
    case "${2:-}" in
      status) fn_swap_status ;;
      ativar) fn_swap_enable ;;
      *)
        fn_separator
        echo -e "${C_BOLD}Subcomandos de 'swap':${C_RESET}"
        echo "  status  — mostra estado da SWAP"
        echo "  ativar  — cria e ativa SWAP de 2GB (APENAS UMA VEZ, não usar em ARM)"
        echo
        echo "  Exemplo: ./jarbas swap status"
        fn_separator
        exit 1
        ;;
    esac
    ;;

  firewall)
    case "${2:-}" in
      status) fn_firewall_status ;;
      ativar) fn_firewall_enable ;;
      *)
        fn_separator
        echo -e "${C_BOLD}Subcomandos de 'firewall':${C_RESET}"
        echo "  status  — mostra estado do ufw"
        echo "  ativar  — instala e configura ufw com as portas necessárias"
        echo
        echo "  Exemplo: ./jarbas firewall status"
        fn_separator
        exit 1
        ;;
    esac
    ;;

  caddy)
    case "${2:-}" in
      instalar) fn_caddy_install ;;
      config)   fn_caddy_config ;;
      arquivo)  fn_caddy_file ;;
      start|stop|restart|status) fn_caddy_manage "${2}" ;;
      *)
        fn_separator
        echo -e "${C_BOLD}Subcomandos de 'caddy':${C_RESET}"
        echo "  instalar          — instala o Caddy"
        echo "  config            — configura com seu domínio (SSL automático)"
        echo "  arquivo           — exibe Caddyfile e options.json"
        echo "  start|stop|restart|status — gerencia o serviço"
        echo
        echo "  Exemplo: ./jarbas caddy instalar"
        fn_separator
        exit 1
        ;;
    esac
    ;;

  *) fn_help ;;
esac

fn_separator
exit 0