#!/bin/sh
# ==============================================================================
# Cudy TR3000 — переключатель "mode" управляет одной из двух функций (выбор
# через ACTION_MODE при установке), красный LED вместо белого статусного,
# пока активен защитный режим:
#
#   ACTION_MODE=wifi (по умолчанию) — переключает Wi-Fi.
#   ACTION_MODE=wan  — блокирует форвардинг LAN->WAN файрволом, Wi-Fi/LAN/
#                       USB-шара остаются доступны (приватное использование
#                       SMB-шары без выхода в интернет).
#
# Использование на роутере (через SSH, ЖЕЛАТЕЛЬНО ПО КАБЕЛЮ — см. ниже):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
#
# Выбор режима блокировки WAN вместо Wi-Fi:
#   ACTION_MODE=wan \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
#
# Скачивает mode-button-wifi-toggle.sh из этого репозитория и кладёт его в
# /etc/rc.button/BTN_0 — так называется хук, который procd вызывает на
# каждое физическое переключение флажка "mode" (переменная BUTTON для
# этого GPIO равна "BTN_0", несмотря на метку "mode" в device tree —
# подробности в комментариях самого файла).
#
# Положение переключателя однозначно определяет желаемое состояние сети
# (pressed -> обычный режим, released -> защитный режим), команда не
# повторяется, если сеть уже в нужном состоянии, а пока активен защитный
# режим — вместо белого статусного светодиода (white:status) горит красный
# (red:power).
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
#
# ВНИМАНИЕ: если вы зашли по SSH через сам Wi-Fi (а не по кабелю/LAN) —
# переключение флажка в положение "выключено" в режиме ACTION_MODE=wifi
# оборвёт вашу же SSH-сессию вместе с Wi-Fi (в режиме ACTION_MODE=wan
# Wi-Fi не трогается, но если вы зашли через WAN — потеряете доступ, пока
# не переключите флажок обратно). Тестируйте и устанавливайте по кабелю.
# ==============================================================================

set -e

TARGET=/etc/rc.button/BTN_0
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/mode-button-wifi-toggle.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$ACTION_MODE" ]; then
    sed -i "s#ACTION_MODE:-wifi}#ACTION_MODE:-$ACTION_MODE}#" "$TARGET"
    echo "ACTION_MODE переопределён на $ACTION_MODE (по умолчанию в установленном файле)"
fi
if [ -n "$LED_RED_DIR" ]; then
    sed -i "s#^LED_RED_DIR=.*#LED_RED_DIR=\"$LED_RED_DIR\"#" "$TARGET"
    echo "LED_RED_DIR переопределён на $LED_RED_DIR"
fi
if [ -n "$LED_WHITE_DIR" ]; then
    sed -i "s#^LED_WHITE_DIR=.*#LED_WHITE_DIR=\"$LED_WHITE_DIR\"#" "$TARGET"
    echo "LED_WHITE_DIR переопределён на $LED_WHITE_DIR"
fi

# /etc/rc.button/BTN_0 — обычный файл, а не UCI-конфиг, поэтому по
# умолчанию НЕ переживает "sysupgrade" (без -n сохраняются только файлы,
# перечисленные в /etc/sysupgrade.conf). Добавляем его туда сами, чтобы
# после обновления прошивки скрипт не пришлось ставить заново. Файл
# создаём, если его почему-то ещё нет — иначе "-f" молча пропустит шаг
# и обещание "переживёт sysupgrade" не выполнится.
[ -f "$SYSUPGRADE_CONF" ] || : > "$SYSUPGRADE_CONF"
if ! grep -qxF "$TARGET" "$SYSUPGRADE_CONF"; then
    echo "$TARGET" >> "$SYSUPGRADE_CONF"
    echo "Добавил $TARGET в $SYSUPGRADE_CONF — переживёт sysupgrade."
fi

echo "Готово: $TARGET установлен."
echo
echo "Проверка без физической кнопки (эмуляция события, текущий режим ACTION_MODE):"
echo "  ACTION=released BUTTON=BTN_0 $TARGET"
echo "  ACTION=pressed  BUTTON=BTN_0 $TARGET"
echo
echo "Проверка режима wan вручную, без переустановки:"
echo "  ACTION_MODE=wan ACTION=released BUTTON=BTN_0 $TARGET"
echo "  ACTION_MODE=wan ACTION=pressed  BUTTON=BTN_0 $TARGET"
