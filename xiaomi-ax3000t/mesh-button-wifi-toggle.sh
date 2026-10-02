#!/bin/sh
# Кнопка Mesh на Xiaomi AX3000T: однократное нажатие включает/выключает
# Wi-Fi целиком (все радиомодули разом). Пока Wi-Fi выключен — светодиод
# статуса горит yellow:status (синий при этом гаснет); при включении Wi-Fi
# жёлтый гаснет, синий возвращается.
#
# В device tree AX3000T (mt7981b-xiaomi-mi-router-ax3000t.dts) кнопка
# Mesh объявлена с linux,code = BTN_9. Модуль ядра button-hotplug переводит
# этот код в BUTTON="BTN_9", поэтому хук называется /etc/rc.button/BTN_9.
#
# Желаемое состояние нельзя прочитать из положения кнопки (она без
# фиксации), поэтому оно вычисляется инверсией текущего: если ХОТЯ БЫ ОДИН
# wifi-device включён (disabled=0) — выключаем все, иначе включаем все.
#
# На AX3000T в системе зарегистрированы только blue:status и yellow:status
# (отдельного красного нет, ls /sys/class/leds/ на реальном роутере), поэтому
# в роли "красного" индикатора используется yellow:status. Автоопределение:
# первый /sys/class/leds/*red*, иначе yellow:status; синий — первый *blue*. Если
# автоопределение не подходит — проверьте "ls /sys/class/leds/" и
# переопределите LED_RED_DIR / LED_BLUE_DIR (см. install-mesh-button.sh).
#
# Режим ACTION=sync (без нажатия) только приводит LED в соответствие с
# текущим состоянием Wi-Fi — вызывается при загрузке из /etc/rc.local,
# чтобы жёлтый не пропадал после перезагрузки при выключенном Wi-Fi.

. /lib/functions.sh

LED_RED_DIR="${LED_RED_DIR:-}"
LED_BLUE_DIR="${LED_BLUE_DIR:-}"

[ -z "$LED_RED_DIR" ] && LED_RED_DIR="$(ls -d /sys/class/leds/*red* /sys/class/leds/yellow:status 2>/dev/null | head -n1)"
[ -z "$LED_BLUE_DIR" ] && LED_BLUE_DIR="$(ls -d /sys/class/leds/*blue* 2>/dev/null | head -n1)"

[ "$ACTION" = "released" ] || [ "$ACTION" = "sync" ] || exit 0

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

wifi_check_any_enabled() {
    val="$(uci -q get wireless."$1".disabled)"
    [ -z "$val" ] && val=0
    [ "$val" = "0" ] && any_enabled=1
}

wifi_set_disabled() {
    uci set wireless."$1".disabled="$new_disabled"
}

apply_led() {
    if [ "$1" = "1" ]; then
        led_off "$LED_RED_DIR"
        led_on "$LED_BLUE_DIR"
    else
        led_off "$LED_BLUE_DIR"
        led_on "$LED_RED_DIR"
    fi
}

config_load wireless
any_enabled=0
config_foreach wifi_check_any_enabled wifi-device

if [ "$ACTION" = "sync" ]; then
    apply_led "$any_enabled"
    exit 0
fi

if [ "$any_enabled" = "1" ]; then
    new_disabled=1
    wifi_on=0
else
    new_disabled=0
    wifi_on=1
fi

config_foreach wifi_set_disabled wifi-device
uci commit wireless
wifi reload

apply_led "$wifi_on"

if [ "$wifi_on" = "1" ]; then
    logger -t rc.button.mesh "mesh: Wi-Fi включён, жёлтый LED погашен"
else
    logger -t rc.button.mesh "mesh: Wi-Fi выключен, жёлтый LED горит"
fi
