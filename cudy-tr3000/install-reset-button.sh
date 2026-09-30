#!/bin/sh
# ==============================================================================
# Cudy TR3000 — физическая кнопка reset совмещает три функции по длительности
# нажатия (вместо штатного reboot по короткому нажатию):
#   - короткое (<1 сек)      — переключение USB-накопителя (swap-disk из
#                               ../openwrt-tool/usb-smb-share.sh): размонтирует
#                               текущий, если смонтирован, затем до 60 сек
#                               ищет и монтирует другой;
#   - от 1 до 5 секунд        — включает/выключает подключение netbird
#                               (netbird up/down; требует уже установленного и
#                               настроенного netbird, сам скрипт его не ставит);
#   - 5+ секунд                — полный сброс к заводским настройкам (factory
#                               reset), как и в исходной прошивке.
# Успех короткого/среднего нажатия — белый светодиод мигает 5 раз, ошибка —
# красный горит 5 секунд. USB-функция требует, чтобы шара уже была настроена
# openwrt-tool/usb-smb-share.sh (см. openwrt-tool/README.md).
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
#
# Скачивает reset-button-usb-toggle.sh из этого репозитория и кладёт его в
# /etc/rc.button/reset — стандартный хук procd для физической кнопки reset.
# Файл заменяет штатный /etc/rc.button/reset прошивки: reboot по короткому
# нажатию убран, factory reset на удержании 5+ секунд не изменён.
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
#
# Если бинарь netbird называется/лежит иначе, чем просто "netbird" в PATH —
# переопределите перед установкой:
#   NETBIRD_BIN=/usr/sbin/netbird \
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
if [ -n "$NETBIRD_BIN" ]; then
    sed -i "s#^NETBIRD_BIN=.*#NETBIRD_BIN=\"$NETBIRD_BIN\"#" "$TARGET"
    echo "NETBIRD_BIN переопределён на $NETBIRD_BIN"
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
echo "Проверка без физической кнопки:"
echo "  Короткое нажатие (USB swap-disk):  SEEN=0 ACTION=released BUTTON=reset $TARGET"
echo "  Среднее нажатие (netbird up/down): SEEN=2 ACTION=released BUTTON=reset $TARGET"
