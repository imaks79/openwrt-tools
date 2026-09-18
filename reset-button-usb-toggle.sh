#!/bin/sh
# Cudy TR3000 — короткое нажатие reset (<1 сек, тот же порог, что раньше
# использовался для reboot) переключает USB-накопитель без захода по SSH:
#
#   - если накопитель уже смонтирован     -> безопасно размонтировать его;
#   - если накопитель сейчас не смонтирован -> выполнить
#     "CUDY_MODE=swap-disk sh install.sh", чтобы подхватить только что
#     подключённый новый накопитель.
#
# Результат сигнализируется светодиодами:
#   успех  -> белый (white:status) мигает 5 раз;
#   ошибка -> красный (red:power) горит ровно 5 секунд.
# Оба светодиода после сигнала возвращаются в то состояние, в котором были
# до нажатия (важно, если также установлен mode-button-wifi-toggle.sh —
# он держит red:power включённым, пока выключен Wi-Fi, и этот файл не
# должен случайно погасить его или "склеить" состояния).
#
# Reboot с кнопки reset убран. Удержание 5+ секунд по-прежнему делает
# полный сброс к заводским настройкам (factory reset) — без изменений.
# Удержание от 1 до 5 секунд ничего не делает (как и в исходной прошивке).
#
# Установка на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
#
# Точка монтирования читается из той же UCI-секции, которую настраивает
# install.sh (fstab.usbmount.target) — так эта кнопка всегда соответствует
# реальной точке монтирования, даже если её меняли через CUDY_MOUNT_POINT
# или CUDY_MODE=swap-disk. Если секции нет — используется /mnt/usb1.
#
# Ограничение: "CUDY_MODE=swap-disk" запускается без подключённого
# терминала. Если к роутеру одновременно подключено НЕСКОЛЬКО
# USB-накопителей, install.sh обычно просит выбрать раздел через
# интерактивный ввод — в контексте кнопки такого терминала нет, поэтому
# выбор не сработает и install.sh завершится с ошибкой (это будет
# показано как ошибка — красный на 5 секунд). Подключайте к роутеру один
# накопитель за раз, либо выбирайте раздел через SSH.

INSTALL_SH="/root/cudy-tr3000-usb-share/install.sh"
INSTALL_LOG="/root/cudy-tr3000-usb-share/install.log"

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"

OVERLAY="$( grep ' /overlay ' /proc/mounts )"

mount_point() {
    mp="$(uci -q get fstab.usbmount.target)"
    [ -z "$mp" ] && mp="/mnt/usb1"
    echo "$mp"
}

# Мигает светодиодом $1 (путь в /sys/class/leds) $2 раз, интервал 1 сек,
# и возвращает исходную яркость обратно (не оставляет включённым/выключенным
# насовсем — на этом светодиоде может быть завязана другая логика, см.
# mode-button-wifi-toggle.sh).
blink_led() {
    dir="$1"
    times="$2"

    [ -e "${dir}/brightness" ] || return 0
    [ -e "${dir}/trigger" ] && echo none > "${dir}/trigger" 2>/dev/null

    saved_brightness="$(cat "${dir}/brightness" 2>/dev/null || echo 0)"
    max_brightness="$(cat "${dir}/max_brightness" 2>/dev/null || echo 1)"

    i=0
    while [ "$i" -lt "$times" ]; do
        echo "$max_brightness" > "${dir}/brightness" 2>/dev/null
        sleep 1
        echo 0 > "${dir}/brightness" 2>/dev/null
        sleep 1
        i=$((i + 1))
    done

    echo "$saved_brightness" > "${dir}/brightness" 2>/dev/null
}

# Держит светодиод $1 включённым $2 секунд, затем возвращает исходную яркость.
hold_led() {
    dir="$1"
    seconds="$2"

    [ -e "${dir}/brightness" ] || return 0
    [ -e "${dir}/trigger" ] && echo none > "${dir}/trigger" 2>/dev/null

    saved_brightness="$(cat "${dir}/brightness" 2>/dev/null || echo 0)"
    max_brightness="$(cat "${dir}/max_brightness" 2>/dev/null || echo 1)"

    echo "$max_brightness" > "${dir}/brightness" 2>/dev/null
    sleep "$seconds"
    echo "$saved_brightness" > "${dir}/brightness" 2>/dev/null
}

signal_success() { blink_led "$LED_WHITE_DIR" 5; }
signal_failure() { hold_led "$LED_RED_DIR" 5; }

handle_usb_button() {
    mp="$(mount_point)"

    if grep -qs " ${mp} " /proc/mounts; then
        echo "USB UNMOUNT" > /dev/console
        if err="$(umount "$mp" 2>&1)"; then
            logger -t rc.button.reset "reset: $mp успешно размонтирован по короткому нажатию"
            signal_success
        else
            logger -t rc.button.reset "reset: не удалось размонтировать $mp: $err (проверьте logread/smbstatus — накопитель, вероятно, занят)"
            signal_failure
        fi
    else
        echo "USB MOUNT NEW DISK" > /dev/console
        logger -t rc.button.reset "reset: $mp не смонтирован, запускаю swap-disk для нового накопителя"
        if CUDY_MODE=swap-disk sh "$INSTALL_SH" >>"$INSTALL_LOG" 2>&1; then
            logger -t rc.button.reset "reset: swap-disk успешно смонтировал новый накопитель"
            signal_success
        else
            logger -t rc.button.reset "reset: swap-disk не смонтировал накопитель — см. $INSTALL_LOG и dmesg"
            signal_failure
        fi
    fi
}

case "$ACTION" in
pressed)
    [ -z "$OVERLAY" ] && return 0

    return 5
;;
timeout)
    . /etc/diag.sh
    set_state failsafe
;;
released)
    if [ "$SEEN" -lt 1 ]
    then
        handle_usb_button
    elif [ "$SEEN" -ge 5 ] && [ -n "$OVERLAY" ]
    then
        echo "FACTORY RESET" > /dev/console
        factoryreset -y && reboot &
    fi
;;
esac

return 0
