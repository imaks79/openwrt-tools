#!/bin/sh
# Кнопка WPS на Cudy WR3000U (хук /etc/rc.button/wps) вместо запуска WPS
# переключает по длительности удержания (SEEN — секунды, приходит при
# "released"):
#   < 2 с        — Wi-Fi вкл/выкл (все радиомодули);
#   >= 2, < 5 с  — wireguard и amneziawg вкл/выкл (ifdown/ifup всех
#                  uci-интерфейсов с proto wireguard/amneziawg), чтобы
#                  клиенты не могли подключиться; повторное удержание
#                  поднимает их обратно;
#   >= 5 с       — netbird вкл/выкл (netbird down/up; netbird должен быть
#                  уже установлен и залогинен).
#
# Светодиоды сознательно НЕ используются: на этой модели они все заняты
# штатными индикаторами системы (см. README.md).
#
# GPIO-кнопка "wps" в device tree объявлена с linux,code = KEY_WPS_BUTTON;
# button-hotplug переводит её в BUTTON="wps", поэтому хук называется
# /etc/rc.button/wps. Желаемое состояние вычисляется инверсией текущего.

. /lib/functions.sh

NETBIRD_BIN="${NETBIRD_BIN:-netbird}"
NETBIRD_TIMEOUT="${NETBIRD_TIMEOUT:-20}"

[ "$ACTION" = "released" ] || exit 0

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
    logger -t rc.button.wps "wps: Wi-Fi $([ "$new_disabled" = "1" ] && echo выключен || echo включён)"
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

toggle_vpn() {
    vpn_load
    all="$vpn_wg $vpn_awg"
    if [ -z "$(echo $all)" ]; then
        logger -t rc.button.wps "wps: wireguard/amneziawg интерфейсов в /etc/config/network нет, пропускаю"
        return 0
    fi
    any_up=0
    for i in $all; do iface_is_up "$i" && any_up=1; done
    if [ "$any_up" = "1" ]; then
        for i in $all; do ifdown "$i"; done
        logger -t rc.button.wps "wps: wireguard/amneziawg отключены:$all"
    else
        for i in $all; do ifup "$i"; done
        logger -t rc.button.wps "wps: wireguard/amneziawg включены:$all"
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
        logger -t rc.button.wps "wps: '$NETBIRD_BIN' не найден — сначала установите и настройте netbird, пропускаю"
        return 0
    fi
    if netbird_is_connected; then
        if out="$(netbird_run down)"; then
            logger -t rc.button.wps "wps: netbird отключён"
        else
            logger -t rc.button.wps "wps: netbird down завершился с ошибкой: $out"
        fi
    else
        if out="$(netbird_run up)"; then
            logger -t rc.button.wps "wps: netbird подключён"
        else
            logger -t rc.button.wps "wps: netbird up не завершился за ${NETBIRD_TIMEOUT}с или упал (если не залогинен — выполните вход по SSH: netbird up --setup-key <KEY>): $out"
        fi
    fi
}

seen="${SEEN:-0}"
if [ "$seen" -ge 5 ] 2>/dev/null; then
    toggle_netbird
elif [ "$seen" -ge 2 ] 2>/dev/null; then
    toggle_vpn
else
    toggle_wifi
fi
