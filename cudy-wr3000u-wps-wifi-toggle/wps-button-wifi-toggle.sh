#!/bin/sh
# Короткое нажатие штатной кнопки WPS на Cudy WR3000U переключает Wi-Fi
# целиком (оба диапазона разом), вместо запуска WPS-подключения. Плюс
# явно зажигает/гасит два светодиода диапазонов панели — по одному на
# 2.4 ГГц и 5 ГГц — синхронно с новым состоянием радио.
#
# GPIO-кнопка "wps" в device tree Cudy WR3000U (mt7981b-cudy-wr3000-nand.dtsi)
# объявлена с linux,code = KEY_WPS_BUTTON. Модуль ядра button-hotplug
# переводит этот код в переменную окружения BUTTON="wps" (таблица в
# package/kernel/button-hotplug/src/button-hotplug.c), поэтому хук должен
# называться /etc/rc.button/wps.
#
# У кнопки WPS, в отличие от флажка "mode" на Cudy TR3000, нет двух
# устойчивых положений — только "нажата"/"отпущена". Поэтому желаемое
# состояние сети нельзя прочитать из положения кнопки, оно вычисляется
# инверсией текущего: если ХОТЯ БЫ ОДНА секция wifi-device сейчас включена
# (disabled=0) — выключаем все; если все уже выключены — включаем все.
# Действие выполняется по факту отпускания кнопки (ACTION=released),
# длительность нажатия (SEEN) не учитывается — любое короткое нажатие
# переключает состояние.
#
# Соответствие диапазон -> LED берётся из "option band '2g'/'5g'" секций
# wireless.radioN в /etc/config/wireless (стандартное поле в OpenWrt
# 21.02+), а не из порядка radio0/radio1 — так правильное соответствие
# сохраняется, даже если в конкретной сборке порядок радиомодулей другой.
#
# Имена светодиодов blue:wlan-2ghz / blue:wlan-5ghz подтверждены командой
# "ls /sys/class/leds/" на реальном Cudy WR3000U (OpenWrt) — несмотря на
# то, что физически на панели диапазонные индикаторы могут восприниматься
# как красные, в системе они зарегистрированы именно под этими именами
# (совпадает с upstream device tree, mt7981b-cudy-wbr3000uax-v1.dtsi).
# Отдельно существуют red:wps (сама кнопка) и red:fault — этот скрипт их
# не трогает. Если на вашей прошивке имена отличаются — проверьте
# "ls /sys/class/leds/" и переопределите (см. install-wps-button.sh).
#
# Установка на роутере — см. install-wps-button.sh в этом репозитории.
#
# ВНИМАНИЕ: если вы зашли по SSH через сам Wi-Fi (а не по кабелю/LAN) —
# нажатие кнопки может выключить Wi-Fi и оборвать вашу же SSH-сессию.
# Тестируйте и устанавливайте по кабелю.

. /lib/functions.sh

LED_2G_DIR="/sys/class/leds/blue:wlan-2ghz"
LED_5G_DIR="/sys/class/leds/blue:wlan-5ghz"

[ "$ACTION" = "released" ] || exit 0

led_dir_for_band() {
    case "$1" in
        2g) echo "$LED_2G_DIR" ;;
        5g) echo "$LED_5G_DIR" ;;
        *) echo "" ;;
    esac
}

# По умолчанию в device tree у этих LED trigger=phy0tpt/phy1tpt (мигание
# по трафику), поэтому просто "brightness>0" недостаточно — сначала явно
# отключаем trigger, иначе драйвер тут же перезапишет brightness обратно.
led_on() {
    dir="$1"
    [ -e "$dir/trigger" ] && echo none > "$dir/trigger" 2>/dev/null
    if [ -e "$dir/max_brightness" ]; then
        cat "$dir/max_brightness" > "$dir/brightness" 2>/dev/null
    else
        echo 1 > "$dir/brightness" 2>/dev/null
    fi
}

led_off() {
    dir="$1"
    echo 0 > "$dir/brightness" 2>/dev/null
}

# Сводное текущее состояние: включена ли хоть одна секция wifi-device.
wifi_check_any_enabled() {
    val="$(uci -q get wireless."$1".disabled)"
    [ -z "$val" ] && val=0
    [ "$val" = "0" ] && any_enabled=1
}

# Желаемое новое состояние — инверсия сводного: если хоть один радио был
# включён, выключаем все; если все были выключены, включаем все.
wifi_set_and_led() {
    section="$1"
    uci set wireless."$section".disabled="$new_disabled"

    band="$(uci -q get wireless."$section".band)"
    dir="$(led_dir_for_band "$band")"
    [ -n "$dir" ] || return 0

    if [ "$new_disabled" = "0" ]; then
        led_on "$dir"
    else
        led_off "$dir"
    fi
}

config_load wireless

any_enabled=0
config_foreach wifi_check_any_enabled wifi-device

if [ "$any_enabled" = "1" ]; then
    new_disabled=1
else
    new_disabled=0
fi

config_foreach wifi_set_and_led wifi-device
uci commit wireless
wifi up

logger -t rc.button.wps "wps короткое нажатие: wireless disabled=$new_disabled (оба диапазона)"

exit 0
