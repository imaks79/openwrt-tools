#!/bin/sh
# ==============================================================================
# Cudy WR3000U — кнопка WPS вместо запуска WPS-подключения переключает по
# длительности удержания:
#   - < 2 сек        — Wi-Fi вкл/выкл (все радиомодули);
#   - от 2 до 5 сек  — wireguard и amneziawg вкл/выкл (ifdown/ifup), чтобы
#                      клиенты не могли подключиться; повторно — обратно;
#   - от 5 сек       — netbird вкл/выкл (netbird down/up; требует уже
#                      установленного и залогиненного netbird).
# Светодиоды не используются (на этой модели все заняты системой).
#
# Использование на роутере (через SSH, ЖЕЛАТЕЛЬНО ПО КАБЕЛЮ — см. ниже):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# Если бинарь netbird лежит не в PATH:
#   NETBIRD_BIN=/usr/sbin/netbird \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# ВНИМАНИЕ: если вы зашли по SSH через сам Wi-Fi — нажатие кнопки может
# выключить Wi-Fi и оборвать вашу сессию. Тестируйте и устанавливайте по кабелю.
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
echo "  Wi-Fi:                  SEEN=0 ACTION=released BUTTON=wps $TARGET"
echo "  wireguard/amneziawg:    SEEN=3 ACTION=released BUTTON=wps $TARGET"
echo "  netbird:                SEEN=6 ACTION=released BUTTON=wps $TARGET"
echo "Логи: logread -e rc.button.wps"
