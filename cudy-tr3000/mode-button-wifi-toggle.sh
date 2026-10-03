#!/bin/sh
# Флажок "mode" на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic)
# управляет одной из трёх взаимоисключающих функций — выбирается переменной
# ACTION_MODE (задаётся при установке, см. install-mode-button.sh):
#
#   ACTION_MODE=wifi (по умолчанию) — переключает Wi-Fi (все wifi-device из
#     /etc/config/wireless), как и раньше.
#   ACTION_MODE=wan — блокирует форвардинг LAN->WAN файрволом. Wi-Fi, LAN и
#     USB-шара (usb-smb-share.sh) продолжают работать как обычно, наружу в
#     интернет трафик не идёт. Сценарий: приватно попользоваться SMB-шарой
#     через недоверенную сеть, не открывая маршрут наружу. Интерфейс WAN не
#     трогаем (ifdown/ifup) — так модемная/PPPoE-сессия не рвётся, включение
#     обратно происходит мгновенно, без переподключения.
#   ACTION_MODE=netbird — включает/выключает подключение netbird (netbird
#     up/down). Требует уже установленного и настроенного netbird (пакет
#     netbird, "/etc/init.d/netbird enable && /etc/init.d/netbird start",
#     логин "netbird login --setup-key <KEY>" — сам демон/сервис не
#     трогаем, переключаем только состояние подключения). Если бинарь
#     "netbird" не найден — скрипт логирует предупреждение и ничего не
#     делает.
#
# GPIO-метка этого переключателя в device tree — "mode" (видно в
# /sys/kernel/debug/gpio), но модуль ядра gpio_button_hotplug строит
# переменную BUTTON из linux,code, а не из метки — для этого устройства
# она равна "BTN_0" (подтверждено логом /etc/hotplug.d/button/*
# при физическом переключении: "BUTTON=BTN_0 ACTION=pressed/released").
# Поэтому файл должен называться /etc/rc.button/BTN_0, а не .../mode.
#
# Переключатель имеет два фиксированных положения, и именно положение
# (а не факт срабатывания) определяет желаемое состояние сети:
#   pressed  -> обычный режим  (Wi-Fi включён   / WAN разрешён  / netbird подключён)
#   released -> защитный режим (Wi-Fi выключен  / WAN заблокирован / netbird отключён)
# Если сеть уже находится в нужном состоянии, uci не трогаем — это защищает
# от лишних перезапусков при повторных/дребезжащих событиях.
#
# Пока активен защитный режим, горит красный светодиод (red:power). Штатный
# белый светодиод (white:status) на этой прошивке горит статически —
# у него нет автотриггера, завязанного на радио (trigger=none,
# brightness всегда 1), поэтому сам по себе он не гаснет и перекрывает
# собой красный. Скрипт гасит его вручную, когда включает красный, и
# возвращает brightness=1 обратно, когда защитный режим снят.
#
# Установка на роутере — самый простой способ, одной строкой (см. также
# install-mode-button.sh в этом репозитории для деталей, выбора ACTION_MODE
# и переопределения имён LED через переменные окружения):
#
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
#
# Либо вручную, тем же способом, что и usb-smb-share.sh для USB-шары
# (см. ../openwrt-tool):
#
#   scp mode-button-wifi-toggle.sh root@<ip роутера>:/etc/rc.button/BTN_0
#   ssh root@<ip роутера> chmod +x /etc/rc.button/BTN_0

. /lib/functions.sh

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"

ACTION_MODE="${ACTION_MODE:-wifi}"
NETBIRD_BIN="${NETBIRD_BIN:-netbird}"

case "${ACTION}" in
pressed)
    blocked=0
    ;;
released)
    blocked=1
    ;;
*)
    exit 0
    ;;
esac

# Проверяем КАЖДУЮ секцию wifi-device, а не только первую попавшуюся:
# секции могут разъехаться (например, если кто-то вручную поменял одно
# из радио через LuCI/uci) — need_update должен взводиться, если хоть
# одна секция не совпадает с желаемым состоянием, иначе рассинхрон
# останется незамеченным и не будет исправлен переключателем.
wifi_check_state() {
    val="$(uci -q get wireless."$1".disabled)"
    [ -z "$val" ] && val=0
    [ "$val" != "$blocked" ] && need_update=1
}

wifi_rfkill_set() {
    uci set wireless."$1".disabled="$blocked"
}

apply_wifi_mode() {
    config_load wireless
    need_update=0
    config_foreach wifi_check_state wifi-device

    if [ "$need_update" = "0" ]; then
        logger -t rc.button.mode "mode switch ${ACTION} (wifi): уже disabled=${blocked} на всех секциях, пропускаю"
    else
        logger -t rc.button.mode "mode switch ${ACTION} (wifi): wireless disabled=${blocked}"
        config_foreach wifi_rfkill_set wifi-device
        uci commit wireless
        wifi up
    fi
}

# Блокируем/разблокируем ВСЕ секции "forwarding" в /etc/config/firewall,
# ведущие в зону wan (dest='wan') — независимо от исходной зоны (lan,
# guest и т.п.), чтобы защитный режим перекрывал интернет для всех, а не
# только для основной LAN. LAN-only трафик (в т.ч. SMB-шара) идёт по
# input/forward внутри зоны lan и этим правилом не затрагивается.
fw_check_state() {
    dest="$(uci -q get firewall."$1".dest)"
    [ "$dest" = "wan" ] || return 0
    val="$(uci -q get firewall."$1".enabled)"
    [ -z "$val" ] && val=1
    want=$((1 - blocked))
    [ "$val" != "$want" ] && need_update=1
}

fw_set_state() {
    dest="$(uci -q get firewall."$1".dest)"
    [ "$dest" = "wan" ] || return 0
    want=$((1 - blocked))
    uci set firewall."$1".enabled="$want"
}

fw_reload() {
    if command -v fw4 >/dev/null 2>&1; then
        fw4 reload
    else
        /etc/init.d/firewall reload
    fi
}

apply_wan_mode() {
    config_load firewall
    need_update=0
    config_foreach fw_check_state forwarding

    if [ "$need_update" = "0" ]; then
        logger -t rc.button.mode "mode switch ${ACTION} (wan): форвардинг LAN->WAN уже в нужном состоянии, пропускаю"
    else
        logger -t rc.button.mode "mode switch ${ACTION} (wan): форвардинг LAN->WAN $([ "$blocked" = "1" ] && echo заблокирован || echo разблокирован)"
        config_foreach fw_set_state forwarding
        uci commit firewall
        fw_reload
    fi
}

# "Daemon status: Connected" — первая строка вывода "netbird status" при
# установленном соединении (подтверждено официальной документацией
# NetBird). Специально ищем именно "Connected" с большой буквы: у
# состояния "Disconnected" эта подстрока не встречается ("D-i-s-c..." —
# дальше идёт строчная "c"), так что пересечения не будет.
netbird_is_connected() {
    "$NETBIRD_BIN" status 2>/dev/null | grep -Eq '^(Management|Daemon status): Connected$'
}

apply_netbird_mode() {
    if ! command -v "$NETBIRD_BIN" >/dev/null 2>&1; then
        logger -t rc.button.mode "mode switch ${ACTION} (netbird): '$NETBIRD_BIN' не найден — сначала установите и настройте netbird (netbird login --setup-key ...), пропускаю"
        return 0
    fi

    if netbird_is_connected; then current=0; else current=1; fi

    if [ "$current" = "$blocked" ]; then
        logger -t rc.button.mode "mode switch ${ACTION} (netbird): уже $([ "$blocked" = "1" ] && echo отключён || echo подключён), пропускаю"
        return 0
    fi

    if [ "$blocked" = "1" ]; then
        if out="$("$NETBIRD_BIN" down 2>&1)"; then
            logger -t rc.button.mode "mode switch ${ACTION} (netbird): отключён (netbird down)"
        else
            logger -t rc.button.mode "mode switch ${ACTION} (netbird): netbird down завершился с ошибкой: $out"
        fi
    else
        if out="$("$NETBIRD_BIN" up 2>&1)"; then
            logger -t rc.button.mode "mode switch ${ACTION} (netbird): подключён (netbird up)"
        else
            logger -t rc.button.mode "mode switch ${ACTION} (netbird): netbird up завершился с ошибкой: $out"
        fi
    fi
}

led_red_on() {
    echo 0 > "${LED_WHITE_DIR}/brightness" 2>/dev/null
    [ -e "${LED_RED_DIR}/trigger" ] && echo none > "${LED_RED_DIR}/trigger" 2>/dev/null
    if [ -e "${LED_RED_DIR}/max_brightness" ]; then
        cat "${LED_RED_DIR}/max_brightness" > "${LED_RED_DIR}/brightness" 2>/dev/null
    else
        echo 1 > "${LED_RED_DIR}/brightness" 2>/dev/null
    fi
}

led_red_off() {
    echo 0 > "${LED_RED_DIR}/brightness" 2>/dev/null
    echo 1 > "${LED_WHITE_DIR}/brightness" 2>/dev/null
}

case "$ACTION_MODE" in
wan)
    apply_wan_mode
    ;;
netbird)
    apply_netbird_mode
    ;;
*)
    apply_wifi_mode
    ;;
esac

if [ "$blocked" = "1" ]; then
    led_red_on
else
    led_red_off
fi

exit 0
