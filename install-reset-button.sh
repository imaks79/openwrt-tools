#!/bin/sh
# ==============================================================================
# Cudy TR3000 — кнопка reset дополнительно безопасно размонтирует USB-накопитель
# при удержании 1-4 секунды (мёртвая зона между reboot и factory reset на этой
# прошивке), с подтверждением тройным миганием красного LED.
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
#
# Скачивает reset-button-usb-unmount.sh из этого репозитория и кладёт его в
# /etc/rc.button/reset — стандартный хук procd для физической кнопки reset.
# Файл заменяет штатный /etc/rc.button/reset прошивки, ПОЛНОСТЬЮ СОХРАНЯЯ его
# исходную логику (reboot на коротком нажатии, factory reset на удержании
# 5+ секунд) — добавляется только обработка промежуточного удержания
# 1-4 секунды, которая раньше ничего не делала.
#
# ВАЖНО: имя светодиода red:power подобрано и проверено на Cudy TR3000
# 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой модели/прошивке
# сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/install-reset-button.sh | sh
# ==============================================================================

set -e

TARGET=/etc/rc.button/reset
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/cudy-tr3000-usb-share/main/reset-button-usb-unmount.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$LED_RED_DIR" ]; then
    sed -i "s#^LED_RED_DIR=.*#LED_RED_DIR=\"$LED_RED_DIR\"#" "$TARGET"
    echo "LED_RED_DIR переопределён на $LED_RED_DIR"
fi

# /etc/rc.button/reset — обычный файл прошивки, а не UCI-конфиг, поэтому по
# умолчанию НЕ переживает "sysupgrade" (без -n сохраняются только файлы,
# перечисленные в /etc/sysupgrade.conf). Добавляем его туда сами, чтобы
# после обновления прошивки правку не пришлось накатывать заново.
[ -f "$SYSUPGRADE_CONF" ] || : > "$SYSUPGRADE_CONF"
if ! grep -qxF "$TARGET" "$SYSUPGRADE_CONF"; then
    echo "$TARGET" >> "$SYSUPGRADE_CONF"
    echo "Добавил $TARGET в $SYSUPGRADE_CONF — переживёт sysupgrade."
fi

echo "Готово: $TARGET установлен."
echo
echo "Проверка без физической кнопки (эмуляция удержания 1-4 сек):"
echo "  SEEN=2 ACTION=released BUTTON=reset $TARGET"
