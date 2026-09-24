#!/bin/sh
# ==============================================================================
# Cudy WR3000U — кнопка WPS вместо запуска WPS-подключения совмещает две
# функции по длительности нажатия:
#   - короткое (< 5 сек) — Wi-Fi вкл/выкл (оба диапазона разом) + два
#     диапазонных LED на панели (2.4 ГГц / 5 ГГц);
#   - долгое (>= 5 сек)  — безопасно монтирует/размонтирует USB-накопитель
#     (требует, чтобы шара уже была настроена openwrt-tool/usb-smb-share.sh).
#
# Использование на роутере (через SSH, ЖЕЛАТЕЛЬНО ПО КАБЕЛЮ — см. ниже):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# Скачивает wps-button-wifi-toggle.sh из этого репозитория и кладёт его в
# /etc/rc.button/wps — так называется хук, который procd вызывает на
# каждое физическое нажатие кнопки WPS (модуль ядра button-hotplug
# переводит linux,code=KEY_WPS_BUTTON в переменную BUTTON="wps" —
# подробности в комментариях самого файла).
#
# Имена светодиодов blue:wlan-2ghz / blue:wlan-5ghz подтверждены командой
# "ls /sys/class/leds/" на реальном Cudy WR3000U (OpenWrt). Если на вашей
# прошивке имена отличаются — проверьте на роутере:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_2G_DIR=/sys/class/leds/<имя> LED_5G_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
#
# ВНИМАНИЕ: если вы зашли по SSH через сам Wi-Fi (а не по кабелю/LAN) —
# нажатие кнопки может выключить Wi-Fi и оборвать вашу же SSH-сессию
# вместе с сетью. Тестируйте и устанавливайте по кабелю.
# ==============================================================================

set -e

TARGET=/etc/rc.button/wps
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/wps-button-wifi-toggle.sh"
SYSUPGRADE_CONF=/etc/sysupgrade.conf

# Если на роутере уже есть штатный /etc/rc.button/wps (например, для
# реальной WPS-функциональности) — сохраняем его копию, чтобы не потерять
# оригинальную логику безвозвратно.
if [ -f "$TARGET" ] && [ ! -f "$TARGET.orig" ]; then
    cp "$TARGET" "$TARGET.orig"
    echo "Существующий $TARGET сохранён как $TARGET.orig"
fi

echo "Скачиваю $SCRIPT_URL -> $TARGET"
mkdir -p "$(dirname "$TARGET")"
wget -O "$TARGET" "$SCRIPT_URL"
chmod +x "$TARGET"

if [ -n "$LED_2G_DIR" ]; then
    sed -i "s#^LED_2G_DIR=.*#LED_2G_DIR=\"$LED_2G_DIR\"#" "$TARGET"
    echo "LED_2G_DIR переопределён на $LED_2G_DIR"
fi
if [ -n "$LED_5G_DIR" ]; then
    sed -i "s#^LED_5G_DIR=.*#LED_5G_DIR=\"$LED_5G_DIR\"#" "$TARGET"
    echo "LED_5G_DIR переопределён на $LED_5G_DIR"
fi

# /etc/rc.button/wps — обычный файл, а не UCI-конфиг, поэтому по умолчанию
# НЕ переживает "sysupgrade" (без -n сохраняются только файлы, перечисленные
# в /etc/sysupgrade.conf). Добавляем его туда сами, чтобы после обновления
# прошивки скрипт не пришлось ставить заново.
[ -f "$SYSUPGRADE_CONF" ] || : > "$SYSUPGRADE_CONF"
if ! grep -qxF "$TARGET" "$SYSUPGRADE_CONF"; then
    echo "$TARGET" >> "$SYSUPGRADE_CONF"
    echo "Добавил $TARGET в $SYSUPGRADE_CONF — переживёт sysupgrade."
fi

echo "Готово: $TARGET установлен."
echo
echo "Список реальных имён LED на этом роутере (сверьте с LED_2G_DIR/LED_5G_DIR внутри $TARGET):"
ls /sys/class/leds/ 2>/dev/null || echo "(/sys/class/leds/ недоступен)"
echo
echo "Проверка без физической кнопки:"
echo "  короткое нажатие (Wi-Fi):        SEEN=0 ACTION=released BUTTON=wps $TARGET"
echo "  долгое нажатие (USB, 5+ сек):    SEEN=5 ACTION=released BUTTON=wps $TARGET"
echo
echo "Долгое нажатие требует уже настроенной USB-шары:"
echo "  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh"
