#!/bin/sh
# ==============================================================================
# OpenWrt + AdGuard Home — скрипт первоначальной настройки роутера
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sh
#
# Чтобы задать уникальный hostname для конкретного роутера:
#   wget -O /root/install.sh https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh
#   HOSTNAME=router-05 sh /root/install.sh
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
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tool/main/install.sh"
ROUTER_HOSTNAME="${HOSTNAME:-OpenWrt}"

mkdir -p "$SELF_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
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
    sed -i "\|^exit 0|i HOSTNAME='$ROUTER_HOSTNAME' sh $SELF_PATH >> $LOG_FILE 2>&1 &" /etc/rc.local
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
}

apply_network_settings() {
    log "Применяю сетевые настройки и настройки доступа..."
    uci set system.@system[0].hostname="$ROUTER_HOSTNAME"
    # Секция attendedsysupgrade.client существует только если установлен
    # пакет attendedsysupgrade-common (не на всех прошивках он есть по
    # умолчанию). Без этой проверки `uci set` на несуществующую секцию
    # падает с ошибкой, а из-за `set -e` весь скрипт молча прерывается
    # прямо здесь — сеть, dropbear и DHCP так и остаются нетронутыми.
    uci -q get attendedsysupgrade.client >/dev/null 2>&1 || uci set attendedsysupgrade.client='client'
    uci set attendedsysupgrade.client.login_check_for_upgrades='1'
    uci set dropbear.@dropbear[0].PasswordAuth='0'
    uci set dropbear.@dropbear[0].RootPasswordAuth='0'
    uci set dropbear.@dropbear[0].Port='2222'
    uci set uhttpd.main.redirect_https='1'
    uci set network.lan.ipaddr='192.168.3.1'
    uci set network.lan.netmask='255.255.255.0'
    uci set dhcp.lan.start='100'
    uci set dhcp.lan.limit='150'
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
    uci add_list dhcp.lan.dhcp_option='6,192.168.3.1'

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

    write_adguardhome_config
    # Конфиг AdGuard Home биндится на 192.168.3.1 — этот адрес появится на
    # интерфейсе LAN только после apply_network_settings (uci commit) и
    # перезагрузки в конце этапа. Поэтому здесь сервис только включаем
    # (автозапуск), а не запускаем/перезапускаем: если поднять его раньше
    # смены IP, AdGuard Home не сможет забиндиться на 192.168.3.1:8080 и
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
