#!/bin/sh
# ==============================================================================
# OpenWrt + AdGuard Home — скрипт первоначальной настройки роутера
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/install.sh | sh
#
# Чтобы задать уникальный hostname для конкретного роутера (сразу качаем в
# /root/openwrt-tool/install.sh — именно туда скрипт сохраняет себя сам,
# поэтому повторного скачивания при первом запуске не будет):
#   mkdir -p /root/openwrt-tool
#   wget -O /root/openwrt-tool/install.sh https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/install.sh
#   OPENWRT_TOOL_HOSTNAME=router-05 sh /root/openwrt-tool/install.sh
#
# Чтобы задать свой адрес LAN вместо 192.168.3.1 (подставится во все
# зависимые параметры — network.lan.ipaddr, DNS-опцию DHCP, конфиг
# AdGuard Home):
#   OPENWRT_TOOL_LAN_IP=192.168.50.1 sh /root/openwrt-tool/install.sh
#
# Скрипт сам переживает две перезагрузки (после обновления пакетов и после
# финальной настройки): он сохраняет себя в /root/openwrt-tool/install.sh,
# регистрирует одноразовый хук в /etc/rc.local и после каждого ребута
# продолжает с того места, на котором остановился. Прогресс хранится в
# /etc/openwrt-tool.stage.
# ==============================================================================

set -e

STATE_FILE=/etc/openwrt-tool.stage
SELF_DIR=/root/openwrt-tool
SELF_PATH="$SELF_DIR/install.sh"
LOG_FILE="$SELF_DIR/install.log"
# ЗАМЕНИТЕ на прямую ссылку (raw) на этот файл в вашем репозитории:
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/install.sh"
# НЕ используем переменную окружения HOSTNAME как есть: это стандартное
# имя, которое некоторые оболочки/окружения (проверено на busybox ash в
# Docker) уже выставляют сами, и тогда наш дефолт "OpenWrt" молча
# подменяется чужим значением. Используем собственное уникальное имя.
ROUTER_HOSTNAME="${OPENWRT_TOOL_HOSTNAME:-OpenWrt}"
# Адрес роутера в сети LAN. Меняя эту переменную, достаточно один раз задать
# новый адрес — он подставится везде, где раньше был захардкожен
# 192.168.3.1 (network.lan.ipaddr, DNS-опция DHCP, конфиг AdGuard Home),
# так что рассинхронизации между этими параметрами не возникнет.
ROUTER_LAN_IP="${OPENWRT_TOOL_LAN_IP:-192.168.3.1}"
# DHCP-пул выдаётся смещением от начала подсети: диапазон
# [DHCP_START, DHCP_START + DHCP_LIMIT - 1] в последнем октете. Вынесены в
# переменные, чтобы использовать те же значения при валидации ROUTER_LAN_IP
# (см. validate_lan_ip) и при применении uci-настроек.
DHCP_START=100
DHCP_LIMIT=150

mkdir -p "$SELF_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

validate_lan_ip() {
    ip="$1"
    old_ifs="$IFS"
    IFS='.'
    set -- $ip
    IFS="$old_ifs"
    if [ "$#" -ne 4 ]; then
        log "OPENWRT_TOOL_LAN_IP='$ip' — не похож на IPv4-адрес (нужно 4 октета через точку)."
        exit 1
    fi
    o1="$1"; o2="$2"; o3="$3"; o4="$4"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        case "$o" in
            ''|*[!0-9]*)
                log "OPENWRT_TOOL_LAN_IP='$ip' — октет '$o' не является числом."
                exit 1
                ;;
        esac
        if [ "$o" -gt 255 ]; then
            log "OPENWRT_TOOL_LAN_IP='$ip' — октет '$o' больше 255."
            exit 1
        fi
    done
    if [ "$o4" -eq 0 ] || [ "$o4" -eq 255 ]; then
        log "OPENWRT_TOOL_LAN_IP='$ip' — последний октет не может быть 0 или 255 (адрес сети/широковещательный)."
        exit 1
    fi
    dhcp_end=$((DHCP_START + DHCP_LIMIT - 1))
    if [ "$o4" -ge "$DHCP_START" ] && [ "$o4" -le "$dhcp_end" ]; then
        log "OPENWRT_TOOL_LAN_IP='$ip' конфликтует с диапазоном DHCP (.$DHCP_START-.$dhcp_end на этом же роутере). Выберите адрес вне этого диапазона."
        exit 1
    fi
}

wait_for_network() {
    log "Проверка подключения к интернету..."
    i=0
    while ! wget -q --spider https://raw.githubusercontent.com 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
            log "Не удалось дождаться сети (60 секунд). Прерываю выполнение."
            exit 1
        fi
        sleep 2
    done
    log "Сеть доступна."
}

# Сохраняем себя локально, чтобы скрипт можно было запустить повторно
# после перезагрузки (пайп "wget | sh" не оставляет файла на диске).
ensure_local_copy() {
    if [ ! -f "$SELF_PATH" ]; then
        log "Сохраняю копию скрипта в $SELF_PATH"
        wait_for_network
        wget -O "$SELF_PATH" "$SCRIPT_URL"
        chmod +x "$SELF_PATH"
    fi
}

install_reboot_hook() {
    if [ ! -f /etc/rc.local ]; then
        printf '#!/bin/sh\nexit 0\n' >/etc/rc.local
        chmod +x /etc/rc.local
    fi
    grep -qF "$SELF_PATH" /etc/rc.local 2>/dev/null && return 0
    sed -i "\|^exit 0|i OPENWRT_TOOL_HOSTNAME='$ROUTER_HOSTNAME' OPENWRT_TOOL_LAN_IP='$ROUTER_LAN_IP' sh $SELF_PATH >> $LOG_FILE 2>&1 &" /etc/rc.local
}

remove_reboot_hook() {
    sed -i "\|$SELF_PATH|d" /etc/rc.local 2>/dev/null || true
}

write_adguardhome_config() {
    log "Записываю конфигурацию AdGuard Home..."
    mkdir -p /etc/adguardhome
    # Кавычки вокруг маркера heredoc обязательны: в конфиге есть bcrypt-хэш
    # вида \$2a\$10\$..., который иначе будет раскрыт shell'ом как переменные.
    cat >/etc/adguardhome/adguardhome.yaml <<'ADGUARDHOME_EOF'
http:
  pprof:
    port: 6060
    enabled: false
  doh:
    routes:
      - GET /dns-query
      - POST /dns-query
      - GET /dns-query/{ClientID}
      - POST /dns-query/{ClientID}
    insecure_enabled: false
  address: 192.168.3.1:8080
  session_ttl: 30d
users:
  # Логин/пароль по умолчанию: root / root. ОБЯЗАТЕЛЬНО смените после
  # первого входа в веб-интерфейс AdGuard Home. Сгенерировать свой хэш:
  #   htpasswd -bnBC 10 "" 'ваш_пароль' | cut -d: -f2
  - name: root
    password: $2y$10$ZbzX5Rvt928Lwtj11fSuB.o.tcI/LRvbVhj0tonigvIZFQNQieioO
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ru
theme: auto
dns:
  bind_hosts:
    - 192.168.3.1
    - 127.0.0.1
  port: 53
  anonymize_client_ip: false
  ratelimit: 20
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - 127.0.0.1:5353
  upstream_dns_file: ""
  bootstrap_dns:
    - 127.0.0.1:5353
  fallback_dns: []
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_enabled: true
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  cache_optimistic_answer_ttl: 30s
  cache_optimistic_max_age: 12h
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: true
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: false
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 90d
  size_memory: 1000
  enabled: true
  ignored_enabled: false
  file_enabled: true
statistics:
  dir_path: ""
  ignored: []
  interval: 1d
  enabled: true
  ignored_enabled: false
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/AdguardFilters/CyrillicFilters/RussianFilter/sections/adservers_firstparty.txt
    name: Russianfilter
    id: 1789734015
  - enabled: true
    url: https://gist.githubusercontent.com/drewpayment/4a316423f7ff7df9dce63a041c478486/raw/6a509d262d7dd687c645349be3fc6217c0764768/AdGuard%2520Russian%2520filter%2520-%2520Rules.txt
    name: 'ADG Russian filter:'
    id: 1789734016
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_27.txt
    name: OISD Blocklist Big
    id: 1789734018
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: UTC
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: true
    duckduckgo: true
    ecosia: true
    google: true
    pixabay: true
    yandex: true
    youtube: true
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  safe_fs_patterns:
    - /var/lib/adguardhome/userfilters/*
  max_http_size: 256MB
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  rewrites_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 34
ADGUARDHOME_EOF
    # Heredoc выше сознательно в одинарных кавычках (внутри bcrypt-хэш вида
    # \$2y\$10\$..., который shell иначе раскрыл бы как переменные), поэтому
    # $ROUTER_LAN_IP туда не подставится напрямую — подменяем адрес отдельным
    # sed после записи файла.
    sed -i "s/192\.168\.3\.1/$ROUTER_LAN_IP/g" /etc/adguardhome/adguardhome.yaml
}

apply_network_settings() {
    log "Применяю сетевые настройки и настройки доступа..."
    uci set system.@system[0].hostname="$ROUTER_HOSTNAME"
    # На чистом OpenWrt пакет attendedsysupgrade-common не установлен, и
    # /etc/config/attendedsysupgrade вообще не существует. `uci set` не
    # может ни создать секцию, ни тем более опцию в отсутствующем конфиге
    # (падает с "Entry not found"), а из-за `set -e` весь скрипт молча
    # прерывается прямо здесь — сеть, dropbear и DHCP так и остаются
    # нетронутыми. Проверено на реальном uci из openwrt/rootfs (SNAPSHOT).
    [ -f /etc/config/attendedsysupgrade ] || touch /etc/config/attendedsysupgrade
    uci -q get attendedsysupgrade.client >/dev/null 2>&1 || uci set attendedsysupgrade.client='client'
    uci set attendedsysupgrade.client.login_check_for_upgrades='1'
    uci set dropbear.@dropbear[0].PasswordAuth='0'
    uci set dropbear.@dropbear[0].RootPasswordAuth='0'
    uci set dropbear.@dropbear[0].Port='2222'
    uci set uhttpd.main.redirect_https='1'
    uci set network.lan.ipaddr="$ROUTER_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set dhcp.lan.start="$DHCP_START"
    uci set dhcp.lan.limit="$DHCP_LIMIT"
    uci set dhcp.lan.leasetime='12h'
    uci set dhcp.lan.force='1'
    uci set network.lan.delegate='0'
    uci set network.wan.ipv6='0'
    uci set network.wan.delegate='0'
    uci set network.wan6.proto='none'
    uci set network.lan.ipv6='0'
    uci -q delete dhcp.lan.ra
    uci -q delete network.globals.ula_prefix
    uci set dhcp.lan.ra='disabled'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ra_management='0'
    uci -q delete dhcp.lan.ra_flags
    uci set dhcp.@dnsmasq[0].port='5353'
    # Список, а не значение: при повторном запуске (например, со сменой
    # ROUTER_LAN_IP) add_list без предварительной очистки добавил бы новый
    # IP вторым элементом, оставив старый — dnsmasq раздавал бы клиентам
    # DNS-опцию (6) сразу с обоими адресами, и часть устройств цеплялась бы
    # за уже недоступный старый адрес.
    uci -q delete dhcp.lan.dhcp_option
    uci add_list dhcp.lan.dhcp_option="6,$ROUTER_LAN_IP"

    uci commit system
    uci commit attendedsysupgrade
    uci commit dropbear
    uci commit uhttpd
    uci commit network
    uci commit dhcp

    /etc/init.d/odhcpd disable
    /etc/init.d/odhcpd stop
}

# ---------------------------------------------------------------------------

validate_lan_ip "$ROUTER_LAN_IP"

ensure_local_copy

STAGE=1
[ -f "$STATE_FILE" ] && STAGE=$(cat "$STATE_FILE")

case "$STAGE" in
1)
    log "=== Этап 1/2: обновление системы ==="
    wait_for_network
    apk update
    apk upgrade
    apk del wpad-basic-mbedtls || log "wpad-basic-mbedtls уже отсутствует, пропускаю"

    echo 2 >"$STATE_FILE"
    install_reboot_hook

    log "Перезагрузка для применения обновлений..."
    sync
    sleep 2
    reboot
    exit 0
    ;;

2)
    log "=== Этап 2/2: установка пакетов и применение конфигурации ==="
    wait_for_network
    apk update
    apk add luci-app-adguardhome
    apk add wpad-openssl

    log "Устанавливаю podkop..."
    # Скрипт podkop задаёт интерактивные вопросы (y/n) через `read`. Так как
    # наш install.sh обычно запускается как "wget -O - ... | sh", stdin уже
    # исчерпан чтением самого скрипта, и `read` внутри podkop сразу получает
    # EOF — это уходит в бесконечный цикл "Введите y или n". Поэтому отвечаем
    # на все вопросы заранее через `yes` (подтверждаем русский язык интерфейса
    # и прочие da/no-подсказки значением по умолчанию).
    yes | sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh) \
        || log "ВНИМАНИЕ: установка podkop завершилась с ошибкой, продолжаю"

    log "Устанавливаю тему luci-theme-proton2025..."
    wget -qO- https://raw.githubusercontent.com/ChesterGoodiny/luci-theme-proton2025/main/install.sh | sh \
        || log "ВНИМАНИЕ: установка темы завершилась с ошибкой, продолжаю"
    
    # log "Устанавливаю roamd ..."
    # wget -O - https://raw.githubusercontent.com/Ground-Zerro/roamd/main/install.sh | sh
    # || log "ВНИМАНИЕ: установка скрипта roamd завершилась с ошибкой, продолжаю"

    write_adguardhome_config
    # Конфиг AdGuard Home биндится на $ROUTER_LAN_IP — этот адрес появится на
    # интерфейсе LAN только после apply_network_settings (uci commit) и
    # перезагрузки в конце этапа. Поэтому здесь сервис только включаем
    # (автозапуск), а не запускаем/перезапускаем: если поднять его раньше
    # смены IP, AdGuard Home не сможет забиндиться на $ROUTER_LAN_IP:8080 и
    # откатится в мастер первого запуска на 0.0.0.0:3000.
    if [ -x /etc/init.d/adguardhome ]; then
        /etc/init.d/adguardhome enable
    fi

    apply_network_settings

    echo 3 >"$STATE_FILE"
    remove_reboot_hook

    log "Настройка завершена. Финальная перезагрузка..."
    sync
    sleep 2
    reboot
    exit 0
    ;;

*)
    log "Настройка уже была выполнена ранее (этап $STAGE)."
    log "Для повторного запуска: rm -f $STATE_FILE && sh $SELF_PATH"
    ;;
esac
