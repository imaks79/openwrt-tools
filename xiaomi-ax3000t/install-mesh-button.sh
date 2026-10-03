#!/bin/sh
# ==============================================================================
# Xiaomi AX3000T — кнопка Mesh: короткое нажатие — Wi-Fi вкл/выкл, 2-5 с —
# wireguard/amneziawg вкл/выкл, от 5 с — netbird вкл/выкл; LED: выкл (Wi-Fi
# выключен) / синий / жёлтый (есть подключённый пир).
#
# Использование на роутере (через SSH, ЖЕЛАТЕЛЬНО ПО КАБЕЛЮ):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
#
# Если автоопределение светодиодов не подходит (см. "ls /sys/class/leds/"):
#   LED_YELLOW_DIR=/sys/class/leds/<имя> LED_BLUE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
# Нестандартный путь к netbird: NETBIRD_BIN=/usr/sbin/netbird (аналогично).
#
# ВНИМАНИЕ: если вы зашли по SSH через Wi-Fi — нажатие кнопки оборвёт сессию.
# ==============================================================================

set -e

TARGET=/etc/rc.button/BTN_9
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/mesh-button-wifi-toggle.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf
RC_LOCAL=/etc/rc.local
SYNC_LINE="ACTION=sync BUTTON=BTN_9 $TARGET"

if [ -f "$TARGET" ] && [ ! -f "$TARGET.orig" ]; then
    cp "$TARGET" "$TARGET.orig"
    echo "Существующий $TARGET сохранён как $TARGET.orig"
fi

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$LED_YELLOW_DIR" ]; then
    sed -i "s#^LED_YELLOW_DIR=.*#LED_YELLOW_DIR=\"$LED_YELLOW_DIR\"#" "$TARGET"
    echo "LED_YELLOW_DIR переопределён на $LED_YELLOW_DIR"
fi
if [ -n "$LED_BLUE_DIR" ]; then
    sed -i "s#^LED_BLUE_DIR=.*#LED_BLUE_DIR=\"$LED_BLUE_DIR\"#" "$TARGET"
    echo "LED_BLUE_DIR переопределён на $LED_BLUE_DIR"
fi

if [ -n "$NETBIRD_BIN" ]; then
    sed -i "s#^NETBIRD_BIN=.*#NETBIRD_BIN=\"$NETBIRD_BIN\"#" "$TARGET"
    echo "NETBIRD_BIN переопределён на $NETBIRD_BIN"
fi

# Синхронизация LED при загрузке и раз в минуту из cron (LED следует за
# подключением/отключением пиров). Вставляем в rc.local перед "exit 0".
[ -f "$RC_LOCAL" ] || printf '#!/bin/sh\nexit 0\n' > "$RC_LOCAL"
if ! grep -qF "$SYNC_LINE" "$RC_LOCAL"; then
    sed -i "/^exit 0/i (sleep 15; $SYNC_LINE) &" "$RC_LOCAL"
    echo "Добавил синхронизацию LED при загрузке в $RC_LOCAL"
fi

CRON_FILE=/etc/crontabs/root
CRON_LINE="* * * * * $SYNC_LINE"
touch "$CRON_FILE"
if ! grep -qF "$SYNC_LINE" "$CRON_FILE"; then
    echo "$CRON_LINE" >> "$CRON_FILE"
    echo "Добавил опрос пиров раз в минуту в $CRON_FILE"
fi
/etc/init.d/cron enable 2>/dev/null
/etc/init.d/cron restart 2>/dev/null

[ -f "$SYSUPGRADE_CONF" ] || : > "$SYSUPGRADE_CONF"
for f in "$TARGET" "$RC_LOCAL" "$CRON_FILE"; do
    grep -qxF "$f" "$SYSUPGRADE_CONF" || echo "$f" >> "$SYSUPGRADE_CONF"
done

echo "Готово: $TARGET установлен."
echo
echo "Имена LED на этом роутере:"
ls /sys/class/leds/ 2>/dev/null || echo "(/sys/class/leds/ недоступен)"
echo
echo "Проверка без физической кнопки:"
echo "  ACTION=released BUTTON=BTN_9 $TARGET"
