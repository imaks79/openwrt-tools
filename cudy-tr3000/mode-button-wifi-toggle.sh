#!/bin/sh
# Флажок "mode" на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic)
# переключает Wi-Fi (все wifi-device из /etc/config/wireless).
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
#   pressed  -> обычный режим  (Wi-Fi включён)
#   released -> защитный режим (Wi-Fi выключен)
# Если сеть уже находится в нужном состоянии, uci не трогаем — это защищает
# от лишних перезапусков при повторных/дребезжащих событиях.
#
# Пока активен защитный режим, горит красный светодиод (red:power). Штатный
# белый светодиод (white:status) на этой прошивке горит статически —
# у него нет автотриггера, завязанного на радио (trigger=none,
# brightness всегда 1), поэтому сам по себе он не гаснет и перекрывает
# собой красный. Скрипт гасит его вручную, когда включает красный, и
# возвращает brightness=1 обратно, когда защитный режим снят.
#
# Установка на роутере — самый простой способ, одной строкой (см. также
# install-mode-button.sh в этом репозитории для деталей и переопределения имён LED через переменные окружения):
#
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
#
# Либо вручную, тем же способом, что и usb-smb-share.sh для USB-шары
# (см. ../openwrt-tool):
#
#   scp mode-button-wifi-toggle.sh root@<ip роутера>:/etc/rc.button/BTN_0
#   ssh root@<ip роутера> chmod +x /etc/rc.button/BTN_0

. /lib/functions.sh

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"


case "${ACTION}" in
pressed)
    blocked=0
    ;;
released)
    blocked=1
    ;;
*)
    exit 0
    ;;
esac

# Проверяем КАЖДУЮ секцию wifi-device, а не только первую попавшуюся:
# секции могут разъехаться (например, если кто-то вручную поменял одно
# из радио через LuCI/uci) — need_update должен взводиться, если хоть
# одна секция не совпадает с желаемым состоянием, иначе рассинхрон
# останется незамеченным и не будет исправлен переключателем.
wifi_check_state() {
    val="$(uci -q get wireless."$1".disabled)"
    [ -z "$val" ] && val=0
    [ "$val" != "$blocked" ] && need_update=1
}

wifi_rfkill_set() {
    uci set wireless."$1".disabled="$blocked"
}

apply_wifi_mode() {
    config_load wireless
    need_update=0
    config_foreach wifi_check_state wifi-device

    if [ "$need_update" = "0" ]; then
        logger -t rc.button.mode "mode switch ${ACTION} (wifi): уже disabled=${blocked} на всех секциях, пропускаю"
    else
        logger -t rc.button.mode "mode switch ${ACTION} (wifi): wireless disabled=${blocked}"
        config_foreach wifi_rfkill_set wifi-device
        uci commit wireless
        wifi up
    fi
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

apply_wifi_mode

if [ "$blocked" = "1" ]; then
    led_red_on
else
    led_red_off
fi

exit 0
