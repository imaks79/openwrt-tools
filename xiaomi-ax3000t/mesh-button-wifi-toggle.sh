#!/bin/sh
# Кнопка Mesh на Xiaomi AX3000T (хук /etc/rc.button/BTN_9).
#
# Действия по длительности удержания (SEEN — секунды, приходит при "released"):
#   < 2 с        — включить/выключить Wi-Fi целиком (все радиомодули);
#   >= 2, < 5 с  — выключить/включить VPN-интерфейсы wireguard и amneziawg
#                  (ifdown/ifup всех uci-интерфейсов с proto wireguard/amneziawg),
#                  чтобы клиенты не могли подключиться; повторное удержание
#                  поднимает их обратно;
#   (после успешного ОТКЛЮЧЕНИЯ VPN/netbird синий LED моргает два раза)
#   >= 5 с       — то же для netbird (netbird down/up; сам netbird должен быть
#                  уже установлен и залогинен).
#
# Индикация (один двухцветный индикатор: blue:status / yellow:status):
#   есть подключённый пир (Wi-Fi не важен)  — горит жёлтый;
#   пиров нет, Wi-Fi включён                — горит синий;
#   пиров нет, Wi-Fi выключен               — оба LED погашены.
# Пир считается подключённым, если: у wireguard/amneziawg-интерфейса
# вырос счётчик принятых байт за последние ACTIVE_WINDOW секунд (по умолчанию
# 30; keepalive клиента тоже растит счётчик) либо handshake не старше
# HANDSHAKE_MAX_AGE секунд (по умолчанию 5); у netbird
# "netbird status" показывает хотя бы одного Connected-пира.
#
# Режим ACTION=daemon — фоновый цикл (запускается из /etc/rc.local), каждые
# POLL_INTERVAL секунд (по умолчанию 5) пересчитывает LED, чтобы он следовал
# за подключением/отключением пиров. ACTION=sync — разовый пересчёт.
#
# В device tree AX3000T кнопка Mesh = BTN_9, поэтому файл называется BTN_9.

. /lib/functions.sh

LED_YELLOW_DIR="${LED_YELLOW_DIR:-}"
LED_BLUE_DIR="${LED_BLUE_DIR:-}"
NETBIRD_BIN="${NETBIRD_BIN:-netbird}"
HANDSHAKE_MAX_AGE="${HANDSHAKE_MAX_AGE:-5}"
ACTIVE_WINDOW="${ACTIVE_WINDOW:-30}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
PIDFILE=/var/run/mesh-btn.pid
BUSYFILE=/var/run/mesh-btn.busy
NETBIRD_TIMEOUT="${NETBIRD_TIMEOUT:-20}"

[ -z "$LED_YELLOW_DIR" ] && LED_YELLOW_DIR="$(ls -d /sys/class/leds/*yellow* 2>/dev/null | head -n1)"
[ -z "$LED_BLUE_DIR" ] && LED_BLUE_DIR="$(ls -d /sys/class/leds/*blue* 2>/dev/null | head -n1)"

[ "$ACTION" = "released" ] || [ "$ACTION" = "sync" ] || [ "$ACTION" = "daemon" ] || exit 0

led_on() {
    dir="$1"
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    [ -e "$dir/trigger" ] && echo none > "$dir/trigger" 2>/dev/null
    if [ -e "$dir/max_brightness" ]; then
        cat "$dir/max_brightness" > "$dir/brightness" 2>/dev/null
    else
        echo 1 > "$dir/brightness" 2>/dev/null
    fi
}

led_off() {
    dir="$1"
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    [ -e "$dir/trigger" ] && echo none > "$dir/trigger" 2>/dev/null
    echo 0 > "$dir/brightness" 2>/dev/null
}

# ---------------- Wi-Fi ----------------

wifi_check_any_enabled() {
    val="$(uci -q get wireless."$1".disabled)"
    [ -z "$val" ] && val=0
    [ "$val" = "0" ] && any_enabled=1
}

wifi_set_disabled() {
    uci set wireless."$1".disabled="$new_disabled"
}

wifi_is_on() {
    any_enabled=0
    config_load wireless
    config_foreach wifi_check_any_enabled wifi-device
    [ "$any_enabled" = "1" ]
}

toggle_wifi() {
    if wifi_is_on; then new_disabled=1; else new_disabled=0; fi
    config_load wireless
    config_foreach wifi_set_disabled wifi-device
    uci commit wireless
    wifi reload
    logger -t rc.button.mesh "mesh: Wi-Fi $([ "$new_disabled" = "1" ] && echo выключен || echo включён)"
}

# ---------------- wireguard / amneziawg ----------------

vpn_collect() {
    proto="$(uci -q get network."$1".proto)"
    case "$proto" in
        wireguard) vpn_wg="$vpn_wg $1" ;;
        amneziawg) vpn_awg="$vpn_awg $1" ;;
    esac
}

vpn_load() {
    vpn_wg=""
    vpn_awg=""
    config_load network
    config_foreach vpn_collect interface
}

iface_is_up() {
    [ "$(ifstatus "$1" 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)" = "true" ]
}

# Пир активен, если у него вырос счётчик принятых байт за последние
# ACTIVE_WINDOW секунд (keepalive клиента тоже растит счётчик) или handshake
# не старше HANDSHAKE_MAX_AGE. Предыдущие значения хранятся в
# /tmp/mesh-btn-<iface>.state ("pubkey rx время_последнего_роста").
# $1 — утилита (wg|awg), $2 — интерфейс
tool_has_peer() {
    command -v "$1" >/dev/null 2>&1 || return 1
    state="/tmp/mesh-btn-$2.state"
    "$1" show "$2" dump 2>/dev/null | awk -v now="$(date +%s)" -v win="$ACTIVE_WINDOW" \
        -v hsmax="$HANDSHAKE_MAX_AGE" -v state="$state" '
        BEGIN { while ((getline line < state) > 0) { split(line, f, " "); rx[f[1]] = f[2]; ts[f[1]] = f[3] } close(state) }
        NF == 8 {
            k = $1; hs = $5; r = $6
            if (!(k in rx)) ts[k] = 0
            else if (rx[k] != r) ts[k] = now
            rx[k] = r; seen[k] = 1
            if (now - ts[k] <= win || (hs > 0 && now - hs <= hsmax)) found = 1
        }
        END {
            printf "" > state
            for (k in seen) print k, rx[k], ts[k] >> state
            exit !found
        }'
}

vpn_has_peer() {
    vpn_load
    for i in $vpn_wg; do iface_is_up "$i" && tool_has_peer wg "$i" && return 0; done
    for i in $vpn_awg; do iface_is_up "$i" && tool_has_peer awg "$i" && return 0; done
    return 1
}

toggle_vpn() {
    vpn_load
    all="$vpn_wg $vpn_awg"
    if [ -z "$(echo $all)" ]; then
        logger -t rc.button.mesh "mesh: wireguard/amneziawg интерфейсов в /etc/config/network нет, пропускаю"
        return 0
    fi
    any_up=0
    for i in $all; do iface_is_up "$i" && any_up=1; done
    if [ "$any_up" = "1" ]; then
        down_ok=1
        for i in $all; do ifdown "$i" || down_ok=0; done
        [ "$down_ok" = "1" ] && blink_done=1
        logger -t rc.button.mesh "mesh: wireguard/amneziawg отключены:$all"
    else
        for i in $all; do ifup "$i"; done
        logger -t rc.button.mesh "mesh: wireguard/amneziawg включены:$all"
    fi
}

# ---------------- netbird ----------------

netbird_present() {
    command -v "$NETBIRD_BIN" >/dev/null 2>&1
}

# Новые версии netbird (0.78) не печатают "Daemon status:", поэтому смотрим
# на "Management: Connected"; старый формат тоже поддерживаем.
netbird_is_connected() {
    "$NETBIRD_BIN" status 2>/dev/null | grep -Eq '^(Management|Daemon status): Connected$'
}

# "Peers count: 2/5 Connected" — хотя бы один подключённый пир
netbird_has_peer() {
    netbird_present || return 1
    "$NETBIRD_BIN" status 2>/dev/null | grep -Eq '^Peers count: [1-9][0-9]*/'
}

# netbird up/down с ограничением по времени: без логина "netbird up" ждёт
# SSO-вход в браузере и иначе висел бы минутами
netbird_run() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$NETBIRD_TIMEOUT" "$NETBIRD_BIN" "$1" 2>&1
    else
        "$NETBIRD_BIN" "$1" 2>&1
    fi
}

toggle_netbird() {
    if ! netbird_present; then
        logger -t rc.button.mesh "mesh: '$NETBIRD_BIN' не найден — сначала установите и настройте netbird, пропускаю"
        return 0
    fi
    if netbird_is_connected; then
        if out="$(netbird_run down)"; then
            logger -t rc.button.mesh "mesh: netbird отключён"
            blink_done=1
        else
            logger -t rc.button.mesh "mesh: netbird down завершился с ошибкой: $out"
        fi
    else
        if out="$(netbird_run up)"; then
            logger -t rc.button.mesh "mesh: netbird подключён"
        else
            logger -t rc.button.mesh "mesh: netbird up не завершился за ${NETBIRD_TIMEOUT}с или упал (если не залогинен — выполните вход по SSH: netbird up --setup-key <KEY>): $out"
        fi
    fi
}

# ---------------- LED ----------------

# два синих моргания — подтверждение успешного отключения VPN/netbird
blink_blue_twice() {
    led_off "$LED_YELLOW_DIR"
    for _ in 1 2; do
        led_off "$LED_BLUE_DIR"
        sleep 0.3
        led_on "$LED_BLUE_DIR"
        sleep 0.3
    done
    led_off "$LED_BLUE_DIR"
}

apply_led() {
    if vpn_has_peer || netbird_has_peer; then
        led_off "$LED_BLUE_DIR"
        led_on "$LED_YELLOW_DIR"
    elif wifi_is_on; then
        led_off "$LED_YELLOW_DIR"
        led_on "$LED_BLUE_DIR"
    else
        led_off "$LED_BLUE_DIR"
        led_off "$LED_YELLOW_DIR"
    fi
}

if [ "$ACTION" = "daemon" ]; then
    # фоновый опрос: единственный экземпляр, пропускает цикл, пока
    # обрабатывается нажатие кнопки (BUSYFILE)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        exit 0
    fi
    echo "$$" > "$PIDFILE"
    trap 'rm -f "$PIDFILE"; exit 0' INT TERM
    while :; do
        [ -f "$BUSYFILE" ] || apply_led
        sleep "$POLL_INTERVAL"
    done
fi

if [ "$ACTION" = "released" ]; then
    : > "$BUSYFILE"
    trap 'rm -f "$BUSYFILE"' EXIT
    seen="${SEEN:-0}"
    if [ "$seen" -ge 5 ] 2>/dev/null; then
        toggle_netbird
    elif [ "$seen" -ge 2 ] 2>/dev/null; then
        toggle_vpn
    else
        toggle_wifi
    fi
fi

[ "$blink_done" = "1" ] && blink_blue_twice
apply_led
