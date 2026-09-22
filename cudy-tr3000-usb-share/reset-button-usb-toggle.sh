#!/bin/sh
# Cudy TR3000 — короткое нажатие reset (<1 сек, тот же порог, что раньше
# использовался для reboot) переключает USB-накопитель без захода по SSH:
#
#   - если накопитель уже смонтирован     -> безопасно размонтировать его;
#   - если накопитель сейчас не смонтирован -> выполнить
#     "OPENWRT_TOOL_MODE=swap-disk sh usb-smb-share.sh" (универсальный
#     скрипт из ../openwrt-tool), чтобы подхватить только что подключённый
#     новый накопитель.
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
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-reset-button.sh | sh
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-reset-button.sh | sh
#
# Точка монтирования читается из той же UCI-секции, которую настраивает
# usb-smb-share.sh (fstab.usbmount.target) — так эта кнопка всегда
# соответствует реальной точке монтирования, даже если её меняли через
# OPENWRT_TOOL_MOUNT_POINT или OPENWRT_TOOL_MODE=swap-disk. Если секции
# нет — используется /mnt/usb1.
#
# Требует, чтобы сетевая шара уже была настроена универсальным скриптом
# из ../openwrt-tool:
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh
#
# Ограничение: "OPENWRT_TOOL_MODE=swap-disk" запускается без подключённого
# терминала. Если к роутеру одновременно подключено НЕСКОЛЬКО
# USB-накопителей, usb-smb-share.sh обычно просит выбрать раздел через
# интерактивный ввод — в контексте кнопки такого терминала нет, поэтому
# выбор не сработает и usb-smb-share.sh завершится с ошибкой (это будет
# показано как ошибка — красный на 5 секунд). Подключайте к роутеру один
# накопитель за раз, либо выбирайте раздел через SSH.

INSTALL_SH="/root/openwrt-tool/usb-smb-share.sh"
# В той же директории, куда usb-smb-share.sh уже гарантированно сохранил
# себя при первом запуске (mkdir -p) — так append в этот лог не упадёт
# из-за отсутствующей директории, даже если /root/cudy-tr3000-usb-share
# на этом роутере вообще не создавалась.
INSTALL_LOG="/root/openwrt-tool/reset-button-swap-disk.log"

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"

OVERLAY="$( grep ' /overlay ' /proc/mounts )"

mount_point() {
    mp="$(uci -q get fstab.usbmount.target)"
    [ -z "$mp" ] && mp="/mnt/usb1"
    echo "$mp"
}

led_get() { cat "${1}/brightness" 2>/dev/null || echo 0; }
led_get_max() { cat "${1}/max_brightness" 2>/dev/null || echo 1; }
led_set() { [ -e "${1}/brightness" ] && echo "$2" > "${1}/brightness" 2>/dev/null; }
led_disable_trigger() { [ -e "${1}/trigger" ] && echo none > "${1}/trigger" 2>/dev/null; }

# red:power и white:status на этой прошивке — физически один и тот же
# индикатор (см. mode-button-wifi-toggle.sh): если оба выставить в
# brightness>0 одновременно, светятся ОБА разом вместо однозначного цвета.
# Поэтому на время сигнала явно гасим второй светодиод, а не только
# управляем нужным, и восстанавливаем оба исходных состояния после —
# чтобы не сбить индикацию mode-button-wifi-toggle.sh (держит red:power
# включённым, пока выключен Wi-Fi).
signal_success() {
    led_disable_trigger "$LED_WHITE_DIR"
    led_disable_trigger "$LED_RED_DIR"

    white_saved="$(led_get "$LED_WHITE_DIR")"
    red_saved="$(led_get "$LED_RED_DIR")"
    white_max="$(led_get_max "$LED_WHITE_DIR")"

    led_set "$LED_RED_DIR" 0

    i=0
    while [ "$i" -lt 5 ]; do
        led_set "$LED_WHITE_DIR" "$white_max"
        sleep 1
        led_set "$LED_WHITE_DIR" 0
        sleep 1
        i=$((i + 1))
    done

    led_set "$LED_WHITE_DIR" "$white_saved"
    led_set "$LED_RED_DIR" "$red_saved"
}

signal_failure() {
    led_disable_trigger "$LED_WHITE_DIR"
    led_disable_trigger "$LED_RED_DIR"

    white_saved="$(led_get "$LED_WHITE_DIR")"
    red_saved="$(led_get "$LED_RED_DIR")"
    red_max="$(led_get_max "$LED_RED_DIR")"

    led_set "$LED_WHITE_DIR" 0
    led_set "$LED_RED_DIR" "$red_max"
    sleep 5

    led_set "$LED_WHITE_DIR" "$white_saved"
    led_set "$LED_RED_DIR" "$red_saved"
}

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
        if OPENWRT_TOOL_MODE=swap-disk sh "$INSTALL_SH" >>"$INSTALL_LOG" 2>&1; then
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
