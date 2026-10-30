#!/bin/sh
# ==============================================================================
# Cudy WR3000U — кнопка WPS вместо запуска WPS-подключения при любом
# нажатии включает/выключает агент netbird (netbird up/down; требует уже
# установленного и залогиненного netbird).
# Светодиоды не используются (на этой модели все заняты системой).
#
# Использование на роутере (через SSH, НЕ через netbird — см. ниже):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# Если бинарь netbird лежит не в PATH:
#   NETBIRD_BIN=/usr/sbin/netbird \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# ВНИМАНИЕ: если вы зашли по SSH через netbird — нажатие кнопки может
# отключить netbird и оборвать вашу сессию. Тестируйте по LAN.
# ==============================================================================

set -e

TARGET=/etc/rc.button/wps
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/wps-button-wifi-toggle.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

if [ -f "$TARGET" ] && [ ! -f "$TARGET.orig" ]; then
    cp "$TARGET" "$TARGET.orig"
    echo "Существующий $TARGET сохранён как $TARGET.orig"
fi

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$NETBIRD_BIN" ]; then
    sed -i "s#^NETBIRD_BIN=.*#NETBIRD_BIN=\"$NETBIRD_BIN\"#" "$TARGET"
    echo "NETBIRD_BIN переопределён на $NETBIRD_BIN"
fi

[ -f "$SYSUPGRADE_CONF" ] || : > "$SYSUPGRADE_CONF"
if ! grep -qxF "$TARGET" "$SYSUPGRADE_CONF"; then
    echo "$TARGET" >> "$SYSUPGRADE_CONF"
    echo "Добавил $TARGET в $SYSUPGRADE_CONF — переживёт sysupgrade."
fi

echo "Готово: $TARGET установлен."
echo
echo "Проверка без физической кнопки:"
echo "  netbird вкл/выкл:  ACTION=released BUTTON=wps $TARGET"
echo "Логи: logread -e rc.button.wps"
