#!/bin/sh
# Переключение Wi-Fi (все wifi-device из /etc/config/wireless) флажком "mode"
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic).
#
# GPIO-метка этого переключателя в device tree — "mode" (видно в
# /sys/kernel/debug/gpio), но модуль ядра gpio_button_hotplug строит
# переменную BUTTON из linux,code, а не из метки — для этого устройства
# она равна "BTN_0" (подтверждено логом /etc/hotplug.d/button/*
# при физическом переключении: "BUTTON=BTN_0 ACTION=pressed/released").
# Поэтому файл должен называться /etc/rc.button/BTN_0, а не .../mode.
#
# Переключатель имеет два фиксированных положения, и именно положение
# (а не факт срабатывания) определяет желаемое состояние сети:
#   pressed  -> Wi-Fi должен быть включён  (disabled=0)
#   released -> Wi-Fi должен быть выключен (disabled=1)
# Если сеть уже находится в нужном состоянии, uci/wifi не трогаем —
# это защищает от лишних перезапусков при повторных/дребезжащих событиях.
#
# Пока Wi-Fi выключен, горит красный светодиод (red:power). Штатный
# белый светодиод (white:status) на этой прошивке горит статически —
# у него нет автотриггера, завязанного на радио (trigger=none,
# brightness всегда 1), поэтому сам по себе он не гаснет и перекрывает
# собой красный. Скрипт гасит его вручную, когда включает красный, и
# возвращает brightness=1 обратно, когда Wi-Fi снова включён.
#
# Установка на роутере — самый простой способ, одной строкой (см. также
# install-mode-button.sh в этом репозитории для деталей и переопределения
# имён LED через переменные окружения):
#
#   wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-mode-button.sh | sh
#
# Либо вручную, тем же способом, что и install.sh для USB-шары:
#
#   scp mode-button-wifi-toggle.sh root@<ip роутера>:/etc/rc.button/BTN_0
#   ssh root@<ip роутера> chmod +x /etc/rc.button/BTN_0

. /lib/functions.sh

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"

case "${ACTION}" in
pressed)
    rfkill_state=0
    ;;
released)
    rfkill_state=1
    ;;
*)
    exit 0
    ;;
esac

# Текущее состояние берём с первой попавшейся секции wifi-device —
# в этом скрипте все секции всегда переключаются синхронно, так что
# для сравнения достаточно одной.
wifi_check_state() {
    [ -n "$current_disabled" ] && return 0
    current_disabled="$(uci -q get wireless.$1.disabled)"
    [ -z "$current_disabled" ] && current_disabled=0
}

wifi_rfkill_set() {
    uci set wireless.$1.disabled=$rfkill_state
}

led_red_on() {
    echo 0 > "${LED_WHITE_DIR}/brightness" 2>/dev/null
    [ -e "${LED_RED_DIR}/trigger" ] && echo none > "${LED_RED_DIR}/trigger" 2>/dev/null
    if [ -e "${LED_RED_DIR}/max_brightness" ]; then
        cat "${LED_RED_DIR}/max_brightness" > "${LED_RED_DIR}/brightness" 2>/dev/null
    else
        echo 1 > "${LED_RED_DIR}/brightness" 2>/dev/null
    fi
}

led_red_off() {
    echo 0 > "${LED_RED_DIR}/brightness" 2>/dev/null
    echo 1 > "${LED_WHITE_DIR}/brightness" 2>/dev/null
}

config_load wireless
current_disabled=""
config_foreach wifi_check_state wifi-device

if [ "$current_disabled" = "$rfkill_state" ]; then
    logger -t rc.button.mode "mode switch ${ACTION}: уже disabled=${rfkill_state}, пропускаю"
else
    logger -t rc.button.mode "mode switch ${ACTION}: wireless disabled=${rfkill_state}"
    config_foreach wifi_rfkill_set wifi-device
    uci commit wireless
    wifi up
fi

if [ "$rfkill_state" = "1" ]; then
    led_red_on
else
    led_red_off
fi

exit 0
