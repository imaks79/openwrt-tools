#!/bin/sh
# ==============================================================================
# Cudy TR3000 — короткое нажатие reset (<1 сек) переключает USB-накопитель без
# захода по SSH: размонтирует его, если он смонтирован, либо подключает новый
# (через "OPENWRT_TOOL_MODE=swap-disk" из ../openwrt-tool/usb-smb-share.sh),
# если сейчас ничего не смонтировано. Успех — белый светодиод мигает 5 раз,
# ошибка — красный горит 5 секунд. Требует, чтобы шара уже была настроена
# этим скриптом (см. openwrt-tool/README.md).
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
#
# Скачивает reset-button-usb-toggle.sh из этого репозитория и кладёт его в
# /etc/rc.button/reset — стандартный хук procd для физической кнопки reset.
# Файл заменяет штатный /etc/rc.button/reset прошивки: reboot по короткому
# нажатию убран (заменён на переключение USB-накопителя), factory reset на
# удержании 5+ секунд не изменён.
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
# ==============================================================================

set -e

TARGET=/etc/rc.button/reset
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/reset-button-usb-toggle.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$LED_RED_DIR" ]; then
    sed -i "s#^LED_RED_DIR=.*#LED_RED_DIR=\"$LED_RED_DIR\"#" "$TARGET"
    echo "LED_RED_DIR переопределён на $LED_RED_DIR"
fi
if [ -n "$LED_WHITE_DIR" ]; then
    sed -i "s#^LED_WHITE_DIR=.*#LED_WHITE_DIR=\"$LED_WHITE_DIR\"#" "$TARGET"
    echo "LED_WHITE_DIR переопределён на $LED_WHITE_DIR"
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
echo "Проверка без физической кнопки (эмуляция короткого нажатия):"
echo "  SEEN=0 ACTION=released BUTTON=reset $TARGET"
