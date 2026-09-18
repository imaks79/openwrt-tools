#!/bin/sh
# ==============================================================================
# Cudy TR3000 — USB 3.0 в сетевую SMB-шару (ksmbd, с откатом на samba4)
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sh
#
# Вся настройка — через переменные окружения перед командой (все опциональны):
#   CUDY_MOUNT_POINT     точка монтирования USB (по умолчанию /mnt/usb1)
#   CUDY_FS_TYPE          ext4 | exfat | ntfs3 (по умолчанию ext4)
#   CUDY_SHARE_NAME       имя сетевой шары (по умолчанию share)
#   CUDY_WORKGROUP        рабочая группа SMB (по умолчанию WORKGROUP)
#   CUDY_SMB_USER         логин для доступа к шаре (по умолчанию cudyuser)
#   CUDY_GUEST            1 — разрешить анонимный доступ (не рекомендуется)
#   CUDY_WITH_CRON_ALERT  1 — сразу поставить ежедневную проверку заполнения диска
#   CUDY_MODE             setup (по умолчанию) | status | swap-disk | cron-alert
#
# Примеры:
#   CUDY_FS_TYPE=exfat CUDY_SHARE_NAME=movies \
#     wget -O - https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sh
#
#   wget -O /root/install.sh https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh
#   CUDY_MODE=status sh /root/install.sh
#
# Режимы после первоначальной настройки (не требуют переустановки пакетов):
#   CUDY_MODE=status      показать место на диске, скорость USB, статус SMB, логи
#   CUDY_MODE=swap-disk   переключить шару на ДРУГОЙ физический накопитель
#   CUDY_MODE=cron-alert  поставить ежедневную проверку заполнения диска отдельно
#
# Особенность: выбор раздела (если накопителей несколько), а также ввод
# пароля SMB-пользователя (ksmbd.adduser/smbpasswd) требуют интерактивного
# ввода. Так как при запуске через "wget -O- ... | sh" стандартный ввод
# скрипта уже занят телом самого скрипта, все такие места явно читают
# из /dev/tty — реального терминала SSH-сессии, а не из перекрытого stdin
# (без этого ksmbd.adduser мгновенно получает EOF вместо пароля и
# завершается, даже не дав его ввести).
# ==============================================================================

set -e

SELF_DIR=/root/cudy-tr3000-usb-share
SELF_PATH="$SELF_DIR/install.sh"
LOG_FILE="$SELF_DIR/install.log"
# ЗАМЕНИТЕ на прямую ссылку (raw) на этот файл в вашем репозитории, если
# форкаете или переносите проект в другой репозиторий:
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install.sh"

CUDY_MOUNT_POINT="${CUDY_MOUNT_POINT:-/mnt/usb1}"
CUDY_FS_TYPE="${CUDY_FS_TYPE:-ext4}"
CUDY_SHARE_NAME="${CUDY_SHARE_NAME:-share}"
CUDY_WORKGROUP="${CUDY_WORKGROUP:-WORKGROUP}"
CUDY_SMB_USER="${CUDY_SMB_USER:-cudyuser}"
CUDY_MODE="${CUDY_MODE:-setup}"

PKG_MANAGER=""

GUEST_OK="no"
case "${CUDY_GUEST:-0}" in
    1|yes|true|YES|TRUE) GUEST_OK="yes" ;;
esac

WITH_CRON_ALERT="no"
case "${CUDY_WITH_CRON_ALERT:-0}" in
    1|yes|true|YES|TRUE) WITH_CRON_ALERT="yes" ;;
esac

mkdir -p "$SELF_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# OpenWrt 25.x переходит с opkg на apk (форк apk-tools из Alpine) — на части
# прошивок opkg уже отсутствует. Определяем менеджер один раз и дальше везде
# используем эти обёртки вместо прямых вызовов opkg/apk.
pkg_init() {
    [ -n "$PKG_MANAGER" ] && return 0
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    else
        log "Не найден ни apk, ни opkg — не удалось определить пакетный менеджер этой прошивки."
        exit 1
    fi
    log "Пакетный менеджер: $PKG_MANAGER"
}

pkg_update() {
    pkg_init
    case "$PKG_MANAGER" in
        apk) apk update ;;
        opkg) opkg update ;;
    esac
}

pkg_install() {
    pkg_init
    case "$PKG_MANAGER" in
        apk) apk add "$@" ;;
        opkg) opkg install "$@" ;;
    esac
}

# Есть ли пакет с точным именем $1 в индексе репозитория (используется для
# необязательных kmod-fs-ntfs3/ksmbd-server, которых нет в части прошивок).
pkg_available() {
    pkg_init
    case "$PKG_MANAGER" in
        apk) apk search -e "$1" 2>/dev/null | grep -q "^$1" ;;
        opkg) opkg list 2>/dev/null | grep -q "^$1" ;;
    esac
}

wait_for_network() {
    log "Проверка подключения к интернету..."
    i=0
    while ! wget -q --spider https://raw.githubusercontent.com 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
            log "Не удалось дождаться сети (60 секунд). Прерываю выполнение."
            exit 1
        fi
        sleep 2
    done
    log "Сеть доступна."
}

# Сохраняем себя локально — удобно для повторных запусков (status/swap-disk)
# без повторного скачивания. Пайп "wget | sh" сам по себе файла не оставляет.
ensure_local_copy() {
    if [ ! -f "$SELF_PATH" ]; then
        log "Сохраняю копию скрипта в $SELF_PATH"
        wait_for_network
        wget -O "$SELF_PATH" "$SCRIPT_URL"
        chmod +x "$SELF_PATH"
    fi
}

# Ищет подключённые USB-накопители строго среди /dev/sdX (так в OpenWrt
# всегда называются диски, подключённые через kmod-usb-storage) — внутренние
# разделы прошивки роутера (mtdblock/mmcblk/...) никогда не трогаются.
# Результат — в переменных USB_DEV / USB_UUID / USB_DEVTYPE.
find_usb_partition() {
    wait_seconds=60
    elapsed=0
    candidates=""
    while [ "$elapsed" -le "$wait_seconds" ]; do
        block_info=$(block info 2>/dev/null)
        candidates=$(echo "$block_info" | grep -E '^/dev/sd[a-z][0-9]*:' | grep 'UUID=' || true)
        [ -n "$candidates" ] && break
        if [ "$elapsed" -eq 0 ]; then
            log "Накопитель ещё не виден. Подключите его к USB 3.0 порту роутера — жду до ${wait_seconds} секунд..."
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "$block_info"

    if [ -z "$candidates" ]; then
        log "Не найден подключённый USB-накопитель (/dev/sdX) (ждал ${wait_seconds} сек)."
        exit 1
    fi

    candidate_count=$(echo "$candidates" | wc -l)
    if [ "$candidate_count" -gt 1 ]; then
        echo "Найдено несколько USB-разделов:"
        echo "$candidates"
        printf "Введите путь устройства (например /dev/sda1): "
        read -r chosen_dev < /dev/tty
        chosen=$(echo "$candidates" | grep -E "^${chosen_dev}:")
        if [ -z "$chosen" ]; then
            log "Устройство $chosen_dev не найдено среди перечисленных выше."
            exit 1
        fi
    else
        chosen="$candidates"
    fi

    USB_DEV=$(echo "$chosen" | cut -d: -f1)
    USB_UUID=$(echo "$chosen" | sed -n "s/.*UUID=\"\([^\"]*\)\".*/\1/p")
    USB_DEVTYPE=$(echo "$chosen" | sed -n "s/.*TYPE=\"\([^\"]*\)\".*/\1/p")

    if [ -z "$USB_DEV" ] || [ -z "$USB_UUID" ]; then
        log "Не удалось определить UUID выбранного раздела."
        exit 1
    fi
}

# exFAT — единственная из поддерживаемых ФС, для которой в OpenWrt нет
# внешнего mount-хелпера (/sbin/mount.exfat не существует в принципе, в
# отличие от mount.ntfs3/mount.ntfs-3g у NTFS): block-mount умеет монтировать
# её только напрямую через ядро (kmod-fs-exfat). Если модуль недоступен в
# этой прошивке или не регистрируется в /proc/filesystems, ошибка вида
# 'block: No "mount.exfat" utility available' проявится только на шаге
# монтирования, без внятной причины — проверяем всё заранее.
setup_exfat() {
    if ! pkg_available kmod-fs-exfat; then
        log "kmod-fs-exfat недоступен в этой прошивке (нет в индексе пакетов)."
        log "У exFAT в OpenWrt нет резервного FUSE-варианта (как у NTFS) — переформатируйте накопитель в ext4 (рекомендуется) или ntfs3 и повторите."
        exit 1
    fi
    pkg_install kmod-fs-exfat
    pkg_available exfat-utils && pkg_install exfat-utils

    if ! grep -q '\bexfat\b' /proc/filesystems 2>/dev/null; then
        modprobe exfat >/dev/null 2>&1 || insmod exfat >/dev/null 2>&1 || true
    fi
    if ! grep -q '\bexfat\b' /proc/filesystems 2>/dev/null; then
        log "Пакет kmod-fs-exfat установлен, но ядро не регистрирует файловую систему exfat в этой сборке прошивки."
        log "Смонтировать exFAT напрямую средствами OpenWrt не получится — переформатируйте накопитель в ext4 (рекомендуется) или ntfs3 и повторите."
        exit 1
    fi
    mount_fstype="exfat"
}

do_setup() {
    case "$CUDY_FS_TYPE" in
        ext4|exfat|ntfs3) ;;
        *) log "Недопустимый CUDY_FS_TYPE='$CUDY_FS_TYPE' (ext4|exfat|ntfs3)"; exit 1 ;;
    esac

    wait_for_network

    log "=== Обновление списков пакетов ==="
    pkg_update

    log "=== Установка пакетов для USB 3.0 и файловых систем ==="
    pkg_install kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
                block-mount e2fsprogs fdisk

    case "$CUDY_FS_TYPE" in
        ext4)
            pkg_install kmod-fs-ext4
            mount_fstype="ext4"
            ;;
        exfat)
            setup_exfat
            ;;
        ntfs3)
            # Драйвер ntfs3 в ядре требует Linux 5.15+ (OpenWrt 23.05+). На
            # более старых прошивках пакета kmod-fs-ntfs3 просто нет —
            # откатываемся на ntfs-3g (FUSE): работает на чтение/запись
            # везде, но медленнее и требует больше памяти/CPU.
            if pkg_available kmod-fs-ntfs3; then
                pkg_install kmod-fs-ntfs3
                mount_fstype="ntfs3"
            else
                log "kmod-fs-ntfs3 недоступен в этой прошивке (нужно ядро 5.15+), ставлю ntfs-3g (FUSE, медленнее)"
                pkg_install kmod-fuse ntfs-3g
                mount_fstype="ntfs-3g"
            fi
            ;;
    esac

    log "=== Установка SMB-сервера (ksmbd, легковесный) ==="
    if pkg_available ksmbd-server; then
        pkg_install ksmbd-server luci-app-ksmbd
        smb_backend="ksmbd"
    else
        log "ksmbd-server недоступен в этой прошивке, ставлю Samba4 (тяжелее)"
        pkg_install samba4-server samba4-utils luci-app-samba4
        smb_backend="samba4"
    fi

    log "=== Поиск подключённого USB-накопителя ==="
    find_usb_partition
    log "Выбран раздел $USB_DEV (UUID=$USB_UUID)"

    mkdir -p "$CUDY_MOUNT_POINT"

    log "=== Настройка автомонтирования через UCI (fstab) ==="
    uci -q delete fstab.usbmount 2>/dev/null || true
    uci set fstab.usbmount="mount"
    uci set fstab.usbmount.uuid="$USB_UUID"
    uci set fstab.usbmount.target="$CUDY_MOUNT_POINT"
    uci set fstab.usbmount.fstype="$mount_fstype"
    uci set fstab.usbmount.options="rw,noatime"
    uci set fstab.usbmount.enabled="1"
    uci commit fstab
    block mount

    log "=== Настройка сетевой шары ==="
    if [ "$smb_backend" = "ksmbd" ]; then
        uci set ksmbd.globals=globals
        uci set ksmbd.globals.workgroup="$CUDY_WORKGROUP"
        uci set ksmbd.globals.description="Cudy TR3000 USB Share"
        uci set ksmbd.globals.interface="lan"

        uci -q delete ksmbd.usbshare 2>/dev/null || true
        uci set ksmbd.usbshare="share"
        uci set ksmbd.usbshare.name="$CUDY_SHARE_NAME"
        uci set ksmbd.usbshare.path="$CUDY_MOUNT_POINT"
        uci set ksmbd.usbshare.guest_ok="$GUEST_OK"
        uci set ksmbd.usbshare.read_only="no"
        uci set ksmbd.usbshare.browseable="yes"
        if [ "$GUEST_OK" = "no" ]; then
            uci set ksmbd.usbshare.users="$CUDY_SMB_USER"
        fi
        uci commit ksmbd

        log "Создание пользователя SMB ($CUDY_SMB_USER) — сейчас будет запрошен пароль дважды"
        ksmbd.adduser -a "$CUDY_SMB_USER" < /dev/tty

        /etc/init.d/ksmbd enable
        /etc/init.d/ksmbd restart
    else
        uci set samba4.@samba[0].workgroup="$CUDY_WORKGROUP"
        uci set samba4.@samba[0].description="Cudy TR3000 USB Share"

        uci -q delete samba4.usbshare 2>/dev/null || true
        uci set samba4.usbshare="sambashare"
        uci set samba4.usbshare.name="$CUDY_SHARE_NAME"
        uci set samba4.usbshare.path="$CUDY_MOUNT_POINT"
        uci set samba4.usbshare.guest_ok="$GUEST_OK"
        uci set samba4.usbshare.create_mask="0700"
        uci set samba4.usbshare.dir_mask="0700"
        if [ "$GUEST_OK" = "no" ]; then
            uci set samba4.usbshare.users="$CUDY_SMB_USER"
        fi
        uci commit samba4

        log "Создание пользователя SMB ($CUDY_SMB_USER) — сейчас будет запрошен пароль дважды"
        smbpasswd -a "$CUDY_SMB_USER" < /dev/tty

        /etc/init.d/samba4 enable
        /etc/init.d/samba4 restart
    fi

    log "Проверка firewall (зона lan должна разрешать input accept — обычно так по умолчанию)"
    uci show firewall | grep -A2 "zone\[.*\]\.name='lan'" || true

    lan_ip=$(uci get network.lan.ipaddr 2>/dev/null || echo "<ip роутера>")
    log "Готово!"
    printf 'Шара доступна как: \\\\%s\\%s\n' "$lan_ip" "$CUDY_SHARE_NAME"
    echo "Точка монтирования: $CUDY_MOUNT_POINT (драйвер: $mount_fstype, UUID=$USB_UUID)"

    if [ "$WITH_CRON_ALERT" = "yes" ]; then
        do_cron_alert
    fi

    do_status
}

do_status() {
    echo
    echo "== Использование диска =="
    df -h "$CUDY_MOUNT_POINT" 2>/dev/null || echo "$CUDY_MOUNT_POINT не смонтирован"

    echo
    echo "== USB-устройства и скорость линка (5000=USB3, 480=USB2) =="
    for f in /sys/bus/usb/devices/*/speed; do
        dev=$(dirname "$f")
        echo "$dev: $(cat "$f" 2>/dev/null) Mbps"
    done

    echo
    echo "== Статус SMB-сервиса =="
    if [ -x /etc/init.d/ksmbd ]; then
        /etc/init.d/ksmbd status
        echo "Статистика (если доступен debugfs):"
        cat /sys/kernel/debug/ksmbd/stats 2>/dev/null || echo "(недоступно, см. logread ниже)"
    elif [ -x /etc/init.d/samba4 ]; then
        /etc/init.d/samba4 status
        smbstatus 2>/dev/null || echo "(smbstatus недоступен)"
    else
        echo "SMB-сервис не найден"
    fi

    echo
    echo "== Последние сообщения ядра по USB =="
    dmesg | grep -i usb | tail -n 20

    echo
    echo "== Последние записи журнала по SMB =="
    logread | grep -iE 'ksmbd|smb' | tail -n 20

    echo
    echo "== Предупреждения о заполнении диска =="
    logread | grep usb-storage | tail -n 5
}

do_cron_alert() {
    marker="usb-storage-alert"
    if crontab -l 2>/dev/null | grep -qF "$marker"; then
        log "Cron-алерт уже установлен, пропускаю."
        return 0
    fi

    cron_line="0 8 * * * USAGE=\$(df $CUDY_MOUNT_POINT | awk 'NR==2{print \$5}' | tr -d '%'); [ \"\$USAGE\" -ge 90 ] && logger -t $marker \"Диск заполнен на \${USAGE}%\""

    # "|| true" обязателен: пока у root вообще нет crontab (типичный случай
    # при самом первом запуске), "crontab -l" завершается кодом 1. Под
    # "set -e" это прерывает подшелл ДО "echo", и в crontab улетает пустой
    # список — сообщение "Готово" при этом всё равно печатается. Проверено:
    # без "|| true" первый запуск создаёт пустой crontab, а нужная строка
    # реально попадает в crontab только со второго запуска.
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -
    /etc/init.d/cron restart
    log "Готово: ежедневная проверка (08:00) заполнения $CUDY_MOUNT_POINT добавлена в cron (тег лога: $marker)."
}

do_swap_disk() {
    if ! uci get fstab.usbmount >/dev/null 2>&1; then
        log "Секция fstab.usbmount не найдена — сначала выполните первоначальную настройку (CUDY_MODE=setup)."
        exit 1
    fi

    wait_for_network

    log "Отмонтирую текущий накопитель (если подключён)"
    umount "$CUDY_MOUNT_POINT" 2>/dev/null || true

    log "Поиск нового USB-накопителя"
    find_usb_partition
    log "Выбран раздел $USB_DEV (UUID=$USB_UUID, файловая система: ${USB_DEVTYPE:-неизвестна})"

    log "Проверяю/ставлю модуль под файловую систему накопителя"
    case "$USB_DEVTYPE" in
        ext4)
            pkg_install kmod-fs-ext4 >/dev/null
            mount_fstype="ext4"
            ;;
        vfat)
            pkg_install kmod-fs-vfat kmod-nls-cp437 kmod-nls-iso8859-1 >/dev/null
            mount_fstype="vfat"
            ;;
        exfat)
            setup_exfat
            ;;
        ntfs)
            if pkg_available kmod-fs-ntfs3; then
                pkg_install kmod-fs-ntfs3 >/dev/null
                mount_fstype="ntfs3"
            else
                log "kmod-fs-ntfs3 недоступен, ставлю ntfs-3g (FUSE, медленнее)"
                pkg_install kmod-fuse ntfs-3g >/dev/null
                mount_fstype="ntfs-3g"
            fi
            ;;
        *)
            log "Неизвестная/неподдерживаемая файловая система: ${USB_DEVTYPE:-<пусто>}."
            log "Отформатируйте накопитель в ext4, exFAT или NTFS и повторите."
            exit 1
            ;;
    esac

    log "Переключаю точку монтирования на новый накопитель"
    uci set fstab.usbmount.uuid="$USB_UUID"
    uci set fstab.usbmount.fstype="$mount_fstype"
    uci commit fstab
    block mount
    sleep 1

    if ! grep -qs " ${CUDY_MOUNT_POINT} " /proc/mounts; then
        log "Не удалось смонтировать $CUDY_MOUNT_POINT. Проверьте 'logread' и 'dmesg' на роутере."
        exit 1
    fi

    df -h "$CUDY_MOUNT_POINT"
    log "Готово: новый накопитель смонтирован в $CUDY_MOUNT_POINT (драйвер: $mount_fstype)."
    echo "Шара, логин и пароль не менялись — доступ по тому же сетевому пути."
}

# ---------------------------------------------------------------------------

ensure_local_copy

case "$CUDY_MODE" in
    setup) do_setup ;;
    status) do_status ;;
    swap-disk) do_swap_disk ;;
    cron-alert) do_cron_alert ;;
    *)
        log "Неизвестный CUDY_MODE='$CUDY_MODE' (setup|status|swap-disk|cron-alert)"
        exit 1
        ;;
esac
