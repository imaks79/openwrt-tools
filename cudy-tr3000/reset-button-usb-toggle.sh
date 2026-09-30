#!/bin/sh
# Cudy TR3000 — короткое нажатие reset (<1 сек, тот же порог, что раньше
# использовался для reboot) ВСЕГДА ведёт себя так же, как ручной запуск
# "OPENWRT_TOOL_MODE=swap-disk sh usb-smb-share.sh" (универсальный скрипт из
# ../openwrt-tool): безопасно размонтирует текущий накопитель (если он
# смонтирован), затем до 60 секунд ищет физически подключённый USB-раздел и
# монтирует его. Раньше поведение отличалось в зависимости от того, был ли
# накопитель смонтирован (просто umount ИЛИ просто поиск нового) — из-за
# этого смена накопителя требовала ДВУХ отдельных нажатий (сначала
# отмонтировать старый, затем, вставив новый, нажать ещё раз). Теперь это
# одно действие на одно короткое нажатие, полностью эквивалентное ручному
# swap-disk по SSH.
#
# Защита от повторного/прерванного нажатия: пока swap-disk уже выполняется
# (в т.ч. на этапе до 60-секундного ожидания нового накопителя), повторное
# короткое нажатие reset НЕ запускает второй параллельный процесс (это
# могло бы гонять одновременные uci/mount/pkg-операции и оставить конфиг в
# противоречивом состоянии) — оно просто игнорируется с сигналом ошибки.
# Если предыдущий запуск был прерван (например, роутер перезагрузился или
# процесс был убит) и оставил "осиротевший" лок — следующее нажатие сам
# обнаруживает, что процесс с тем PID уже не выполняется, снимает старый
# лок и продолжает как обычно, без необходимости заходить по SSH.
#
# Результат сигнализируется светодиодами:
#   успех  -> белый (white:status) мигает 5 раз;
#   ошибка -> красный (red:power) горит ровно 5 секунд.
# Оба светодиода после сигнала возвращаются в то состояние, в котором были
# до нажатия (важно, если также установлен mode-button-wifi-toggle.sh —
# он держит red:power включённым, пока выключен Wi-Fi, и этот файл не
# должен случайно погасить его или "склеить" состояния).
#
# Reboot с кнопки reset убран. Удержание 5+ секунд по-прежнему делает
# полный сброс к заводским настройкам (factory reset) — без изменений.
#
# Удержание ОТ 1 ДО 5 СЕКУНД (раньше — "мёртвая зона", ничего не делала) —
# теперь включает/выключает подключение netbird (netbird up/down). Требует
# уже установленного и настроенного netbird (пакет netbird,
# "/etc/init.d/netbird enable && /etc/init.d/netbird start", логин
# "netbird login --setup-key <KEY>") — сам демон/сервис эта кнопка не
# трогает, переключает только состояние подключения. Если бинарь netbird не
# найден — логирует предупреждение через logger и ничего не делает (без
# сигнала светодиодом). У кнопки reset, в отличие от флажка "mode", нет
# двух устойчивых положений — только факт нажатия, поэтому желаемое
# состояние вычисляется инверсией текущего (смотрим первую строку "netbird
# status": "Daemon status: Connected" — отключаем; иначе — подключаем).
# Результат сигнализируется теми же светодиодами, что и смена накопителя:
# успех (netbird up/down выполнился) — белый мигает 5 раз; ошибка
# (netbird up/down вернул ненулевой код) — красный горит 5 секунд.
#
# Установка на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
#
# ВАЖНО: имена светодиодов red:power / white:status подобраны и проверены
# на Cudy TR3000 256MB v1 (OpenWrt 25.12.5, mediatek/filogic). На другой
# модели/прошивке сначала проверьте:
#   ls /sys/class/leds/
# и при необходимости переопределите перед установкой:
#   LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
#     wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
#
# Точка монтирования читается из той же UCI-секции, которую настраивает
# usb-smb-share.sh (fstab.usbmount.target) — так эта кнопка всегда
# соответствует реальной точке монтирования, даже если её меняли через
# OPENWRT_TOOL_MOUNT_POINT или OPENWRT_TOOL_MODE=swap-disk. Если секции
# нет — используется /mnt/usb1.
#
# Требует, чтобы сетевая шара уже была настроена универсальным скриптом
# из ../openwrt-tool:
#   wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh
#
# Особенность: "OPENWRT_TOOL_MODE=swap-disk" запускается без подключённого
# терминала. Если к роутеру одновременно подключено несколько разных
# USB-накопителей (а не несколько разделов одного и того же диска — тот
# случай обрабатывается сам, см. usb-smb-share.sh) — спросить, какой
# использовать, не у кого, поэтому автоматически выбирается раздел
# наибольшего размера. Подключайте накопители по одному за раз, если нужен
# конкретный, либо выбирайте явно через SSH.

INSTALL_SH="/root/openwrt-tool/usb-smb-share.sh"
# В той же директории, куда usb-smb-share.sh уже гарантированно сохранил
# себя при первом запуске (mkdir -p) — так append в этот лог не упадёт
# из-за отсутствующей директории, даже если /root/cudy-tr3000
# на этом роутере вообще не создавалась.
INSTALL_LOG="/root/openwrt-tool/reset-button-swap-disk.log"

LED_RED_DIR="/sys/class/leds/red:power"
LED_WHITE_DIR="/sys/class/leds/white:status"

NETBIRD_BIN="${NETBIRD_BIN:-netbird}"

# /var на OpenWrt — tmpfs (обычно симлинк на /tmp), переживает процесс, но не
# перезагрузку — ровно то, что нужно: после ребута "осиротевших" локов от
# предыдущей загрузки уже не будет, разбираться с ними не придётся.
LOCK_DIR="/var/run/reset-button-usb-toggle.lock.d"

OVERLAY="$( grep ' /overlay ' /proc/mounts )"

mount_point() {
    mp="$(uci -q get fstab.usbmount.target)"
    [ -z "$mp" ] && mp="/mnt/usb1"
    echo "$mp"
}

# mkdir атомарен (в отличие от "проверить файл, потом записать" двумя
# отдельными командами) — на нём и построена защита от гонки, если кто-то
# умудрится нажать reset дважды практически одновременно.
#
# Если лок уже занят — проверяем, жив ли ещё процесс, который его держит
# (kill -0). Если жив — значит swap-disk от предыдущего нажатия
# действительно ещё выполняется (например, всё ещё ждёт накопитель в
# find_usb_partition) — отказываем. Если процесса с таким PID больше нет —
# это "осиротевший" лок от прерванного запуска (процесс убили, роутер
# перезагрузился посреди ожидания и т.п.) — снимаем его сами и продолжаем,
# без необходимости заходить по SSH и разбираться руками.
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi

    lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        return 1
    fi

    logger -t rc.button.reset "reset: найден осиротевший лок (pid ${lock_pid:-?} уже не выполняется — предыдущий запуск, похоже, был прерван) — снимаю его и продолжаю"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null
    echo "$$" > "$LOCK_DIR/pid"
    return 0
}

# Снимает лок, только если он всё ещё принадлежит ЭТОМУ процессу (а не был
# успешно захвачен следующим — теоретически, но мало ли) и вызывается через
# trap при любом завершении, в т.ч. по сигналу, чтобы не оставлять лок
# висеть навечно после аварийного прерывания.
release_lock() {
    [ -f "$LOCK_DIR/pid" ] || return 0
    [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK_DIR"
}
trap release_lock EXIT INT TERM

led_get() { cat "${1}/brightness" 2>/dev/null || echo 0; }
led_get_max() { cat "${1}/max_brightness" 2>/dev/null || echo 1; }
led_set() { [ -e "${1}/brightness" ] && echo "$2" > "${1}/brightness" 2>/dev/null; }
led_disable_trigger() { [ -e "${1}/trigger" ] && echo none > "${1}/trigger" 2>/dev/null; }

# red:power и white:status на этой прошивке — физически один и тот же
# индикатор (см. mode-button-wifi-toggle.sh): если оба выставить в
# brightness>0 одновременно, светятся ОБА разом вместо однозначного цвета.
# Поэтому на время сигнала явно гасим второй светодиод, а не только
# управляем нужным, и восстанавливаем оба исходных состояния после —
# чтобы не сбить индикацию mode-button-wifi-toggle.sh (держит red:power
# включённым, пока выключен Wi-Fi).
signal_success() {
    led_disable_trigger "$LED_WHITE_DIR"
    led_disable_trigger "$LED_RED_DIR"

    white_saved="$(led_get "$LED_WHITE_DIR")"
    red_saved="$(led_get "$LED_RED_DIR")"
    white_max="$(led_get_max "$LED_WHITE_DIR")"

    led_set "$LED_RED_DIR" 0

    i=0
    while [ "$i" -lt 5 ]; do
        led_set "$LED_WHITE_DIR" "$white_max"
        sleep 1
        led_set "$LED_WHITE_DIR" 0
        sleep 1
        i=$((i + 1))
    done

    led_set "$LED_WHITE_DIR" "$white_saved"
    led_set "$LED_RED_DIR" "$red_saved"
}

signal_failure() {
    led_disable_trigger "$LED_WHITE_DIR"
    led_disable_trigger "$LED_RED_DIR"

    white_saved="$(led_get "$LED_WHITE_DIR")"
    red_saved="$(led_get "$LED_RED_DIR")"
    red_max="$(led_get_max "$LED_RED_DIR")"

    led_set "$LED_WHITE_DIR" 0
    led_set "$LED_RED_DIR" "$red_max"
    sleep 5

    led_set "$LED_WHITE_DIR" "$white_saved"
    led_set "$LED_RED_DIR" "$red_saved"
}

handle_usb_button() {
    if ! acquire_lock; then
        echo "USB SWAP DISK ALREADY RUNNING" > /dev/console
        logger -t rc.button.reset "reset: swap-disk от предыдущего нажатия ещё выполняется (возможно, всё ещё ждёт накопитель — до 60 сек) — игнорирую повторное нажатие"
        signal_failure
        return 0
    fi

    mp="$(mount_point)"
    if grep -qs " ${mp} " /proc/mounts; then
        echo "USB SWAP DISK" > /dev/console
    else
        echo "USB MOUNT NEW DISK" > /dev/console
    fi
    logger -t rc.button.reset "reset: запускаю swap-disk — $mp будет безопасно отмонтирован (если сейчас смонтирован), затем до 60 сек идёт поиск нового накопителя"

    if OPENWRT_TOOL_MODE=swap-disk sh "$INSTALL_SH" >>"$INSTALL_LOG" 2>&1; then
        logger -t rc.button.reset "reset: swap-disk успешно смонтировал накопитель"
        signal_success
    else
        logger -t rc.button.reset "reset: swap-disk не смонтировал накопитель (если хотели просто извлечь старый без замены — это ожидаемо; если хотели подключить новый — см. $INSTALL_LOG и dmesg)"
        signal_failure
    fi
}

# "Daemon status: Connected" — первая строка вывода "netbird status" при
# установленном соединении (подтверждено официальной документацией
# NetBird). Специально ищем именно "Connected" с большой буквы: у
# состояния "Disconnected" эта подстрока не встречается ("D-i-s-c..." —
# дальше идёт строчная "c"), так что пересечения не будет. Тот же приём,
# что и в mode-button-wifi-toggle.sh/wps-button-wifi-toggle.sh.
netbird_is_connected() {
    "$NETBIRD_BIN" status 2>/dev/null | grep -q '^Daemon status: Connected$'
}

# У кнопки reset, в отличие от флажка "mode", нет двух устойчивых положений
# — только факт нажатия, поэтому желаемое состояние вычисляется инверсией
# текущего (как и для короткого/долгого нажатия WPS на Cudy WR3000U).
handle_netbird_toggle() {
    if ! command -v "$NETBIRD_BIN" >/dev/null 2>&1; then
        logger -t rc.button.reset "reset: '$NETBIRD_BIN' не найден — сначала установите и настройте netbird (netbird login --setup-key ...), пропускаю"
        return 0
    fi

    if netbird_is_connected; then
        echo "NETBIRD DOWN" > /dev/console
        if out="$("$NETBIRD_BIN" down 2>&1)"; then
            logger -t rc.button.reset "reset: netbird отключён (netbird down)"
            signal_success
        else
            logger -t rc.button.reset "reset: netbird down завершился с ошибкой: $out"
            signal_failure
        fi
    else
        echo "NETBIRD UP" > /dev/console
        if out="$("$NETBIRD_BIN" up 2>&1)"; then
            logger -t rc.button.reset "reset: netbird подключён (netbird up)"
            signal_success
        else
            logger -t rc.button.reset "reset: netbird up завершился с ошибкой: $out"
            signal_failure
        fi
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
        handle_usb_button
    elif [ "$SEEN" -ge 1 ] && [ "$SEEN" -lt 5 ] && [ -n "$OVERLAY" ]
    then
        handle_netbird_toggle
    elif [ "$SEEN" -ge 5 ] && [ -n "$OVERLAY" ]
    then
        echo "FACTORY RESET" > /dev/console
        factoryreset -y && reboot &
    fi
;;
esac

return 0
