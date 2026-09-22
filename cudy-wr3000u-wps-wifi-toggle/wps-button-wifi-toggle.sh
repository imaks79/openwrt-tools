#!/bin/sh
# Кнопка WPS на Cudy WR3000U совмещает две функции по длительности нажатия
# (вместо запуска настоящего WPS-подключения):
#
#   - короткое нажатие (< 5 сек, ACTION=released, SEEN<5) — переключает
#     Wi-Fi целиком (оба диапазона разом) и синхронно зажигает/гасит два
#     диапазонных LED панели (2.4 ГГц/5 ГГц);
#   - долгое нажатие (>= 5 сек, SEEN>=5) — безопасно монтирует/размонтирует
#     USB-накопитель, подключённый к роутеру (WR3000U аппаратно имеет
#     USB-порт — xhci/usb_phy включены в device tree, mt7981b-cudy-wbr3000uax-v1.dtsi),
#     чтобы не заходить по SSH ради размонтирования перед извлечением флешки.
#
# GPIO-кнопка "wps" в device tree Cudy WR3000U (mt7981b-cudy-wr3000-nand.dtsi)
# объявлена с linux,code = KEY_WPS_BUTTON. Модуль ядра button-hotplug
# переводит этот код в переменную окружения BUTTON="wps" (таблица в
# package/kernel/button-hotplug/src/button-hotplug.c), поэтому хук должен
# называться /etc/rc.button/wps.
#
# Длительность нажатия читается из SEEN — модуль button-hotplug добавляет
# эту переменную к КАЖДОМУ событию (pressed/released) как число полных
# секунд с предыдущего события для этой кнопки (button-hotplug.c: "seen =
# jiffies", "(seen - priv->seen[btn]) / HZ"), поэтому отдельно обрабатывать
# ACTION=pressed/timeout не нужно — вся логика по факту отпускания.
#
# === Короткое нажатие: Wi-Fi ===
#
# У кнопки WPS, в отличие от флажка "mode" на Cudy TR3000, нет двух
# устойчивых положений — только "нажата"/"отпущена". Поэтому желаемое
# состояние сети нельзя прочитать из положения кнопки, оно вычисляется
# инверсией текущего: если ХОТЯ БЫ ОДНА секция wifi-device сейчас включена
# (disabled=0) — выключаем все; если все уже выключены — включаем все.
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
# === Долгое нажатие: USB-накопитель ===
#
# Требует, чтобы сетевая USB-шара уже была настроена универсальным
# скриптом openwrt-tool/usb-smb-share.sh из этого репозитория:
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh
#
# Точка монтирования читается из той же UCI-секции, которую настраивает
# usb-smb-share.sh (fstab.usbmount.target) — если её нет, используется
# /mnt/usb1 по умолчанию. Логика:
#   - накопитель сейчас смонтирован     -> безопасно размонтировать
#     (обычный "umount", как перед физическим извлечением);
#   - накопитель сейчас НЕ смонтирован  -> выполнить
#     "OPENWRT_TOOL_MODE=swap-disk sh usb-smb-share.sh", чтобы
#     смонтировать заново тот же накопитель (переподключили) либо
#     подхватить новый — swap-disk сам определяет файловую систему и
#     обновляет UUID в fstab.usbmount.
# Если usb-smb-share.sh ещё не устанавливался на этом роутере — долгое
# нажатие просто логирует предупреждение через logger и ничего не делает
# (без ошибок и без попытки что-то смонтировать вслепую).
#
# Ограничение: "swap-disk" запускается без интерактивного терминала и сам
# проверяет интернет (wait_for_network) — если накопителей несколько или
# сети нет в момент нажатия, mount завершится ошибкой (см. logread и файл
# лога ниже). Подключайте один накопитель за раз.
#
# Установка на роутере — см. install-wps-button.sh в этом репозитории.
#
# ВНИМАНИЕ: если вы зашли по SSH через сам Wi-Fi (а не по кабелю/LAN) —
# короткое нажатие может выключить Wi-Fi и оборвать вашу же SSH-сессию.
# Тестируйте и устанавливайте по кабелю.

. /lib/functions.sh

LED_2G_DIR="/sys/class/leds/blue:wlan-2ghz"
LED_5G_DIR="/sys/class/leds/blue:wlan-5ghz"

USB_LONG_PRESS_SECONDS=5
USB_INSTALL_SH="/root/openwrt-tool/usb-smb-share.sh"
USB_INSTALL_LOG="/root/openwrt-tool/wps-button-swap-disk.log"

[ "$ACTION" = "released" ] || exit 0

usb_mount_point() {
    mp="$(uci -q get fstab.usbmount.target)"
    [ -z "$mp" ] && mp="/mnt/usb1"
    echo "$mp"
}

handle_usb_toggle() {
    if [ ! -x "$USB_INSTALL_SH" ]; then
        logger -t rc.button.wps "wps долгое нажатие: $USB_INSTALL_SH не найден — сначала настройте USB-шару (openwrt-tool/usb-smb-share.sh), пропускаю"
        return 0
    fi

    mp="$(usb_mount_point)"

    if grep -qs " ${mp} " /proc/mounts; then
        if err="$(umount "$mp" 2>&1)"; then
            logger -t rc.button.wps "wps долгое нажатие: $mp успешно размонтирован — накопитель можно извлекать"
        else
            logger -t rc.button.wps "wps долгое нажатие: не удалось размонтировать $mp: $err (проверьте logread/smbstatus — накопитель, вероятно, занят)"
        fi
    else
        logger -t rc.button.wps "wps долгое нажатие: $mp не смонтирован, запускаю swap-disk для нового/переподключённого накопителя"
        if OPENWRT_TOOL_MODE=swap-disk sh "$USB_INSTALL_SH" >>"$USB_INSTALL_LOG" 2>&1; then
            logger -t rc.button.wps "wps долгое нажатие: swap-disk успешно смонтировал накопитель"
        else
            logger -t rc.button.wps "wps долгое нажатие: swap-disk не смонтировал накопитель — см. $USB_INSTALL_LOG и dmesg"
        fi
    fi
}

if [ "${SEEN:-0}" -ge "$USB_LONG_PRESS_SECONDS" ] 2>/dev/null; then
    handle_usb_toggle
    exit 0
fi

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
