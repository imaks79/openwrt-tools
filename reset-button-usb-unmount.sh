#!/bin/sh
# Cudy TR3000 — кнопка reset дополнительно безопасно размонтирует
# USB-накопитель (см. cudy-tr3000-usb-share) при удержании 1–4 секунды.
#
# Штатная логика кнопки на этой прошивке (OpenWrt 25.12.5, mediatek/filogic):
#   отпущена быстрее 1 сек   -> reboot
#   удержана 5 сек и дольше  -> factory reset
#   удержана от 1 до 5 сек   -> раньше не делала НИЧЕГО (мёртвая зона)
# Этот файл добавляет в мёртвую зону безопасное размонтирование — держите
# reset 1-4 секунды и отпустите, не доводя до 5 секунд (иначе сработает
# сброс к заводским настройкам). Успешное размонтирование подтверждается
# тройным миганием красного светодиода (red:power) — если накопитель занят
# и umount не прошёл, лампа не мигает (подробности в logread).
#
# Установка на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
#
# ВАЖНО: имя светодиода red:power подобрано и проверено на Cudy TR3000
# 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой модели/прошивке
# сначала проверьте `ls /sys/class/leds/` на роутере и при необходимости
# переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
#
# Точка монтирования читается из той же UCI-секции, которую настраивает
# install.sh (fstab.usbmount.target) — так эта кнопка всегда соответствует
# реальной точке монтирования, даже если её меняли через CUDY_MOUNT_POINT
# или CUDY_MODE=swap-disk. Если секции нет — используется /mnt/usb1.

LED_RED_DIR="/sys/class/leds/red:power"

OVERLAY="$( grep ' /overlay ' /proc/mounts )"

mount_point() {
    mp="$(uci -q get fstab.usbmount.target)"
    [ -z "$mp" ] && mp="/mnt/usb1"
    echo "$mp"
}

# Кратко мигаем красным 3 раза, не меняя его исходное состояние насовсем —
# тот же светодиод может постоянно гореть красным (mode-button-wifi-toggle.sh,
# пока выключен Wi-Fi), поэтому запоминаем и возвращаем исходную яркость.
blink_red() {
    [ -e "${LED_RED_DIR}/brightness" ] || return 0

    saved_brightness="$(cat "${LED_RED_DIR}/brightness" 2>/dev/null || echo 0)"
    max_brightness="$(cat "${LED_RED_DIR}/max_brightness" 2>/dev/null || echo 1)"

    i=0
    while [ "$i" -lt 3 ]; do
        echo "$max_brightness" > "${LED_RED_DIR}/brightness" 2>/dev/null
        sleep 1
        echo 0 > "${LED_RED_DIR}/brightness" 2>/dev/null
        sleep 1
        i=$((i + 1))
    done

    echo "$saved_brightness" > "${LED_RED_DIR}/brightness" 2>/dev/null
}

safe_unmount() {
    mp="$(mount_point)"

    if ! grep -qs " ${mp} " /proc/mounts; then
        logger -t rc.button.reset "reset: $mp не смонтирован, нечего размонтировать"
        return 0
    fi

    if err="$(umount "$mp" 2>&1)"; then
        logger -t rc.button.reset "reset: $mp успешно размонтирован по удержанию кнопки"
        blink_red
    else
        logger -t rc.button.reset "reset: не удалось размонтировать $mp: $err (проверьте logread/smbstatus — накопитель, вероятно, занят)"
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
        echo "REBOOT" > /dev/console
        sync
        reboot
    elif [ "$SEEN" -ge 5 ] && [ -n "$OVERLAY" ]
    then
        echo "FACTORY RESET" > /dev/console
        factoryreset -y && reboot &
    else
        echo "SAFE USB UNMOUNT" > /dev/console
        safe_unmount
    fi
;;
esac

return 0
