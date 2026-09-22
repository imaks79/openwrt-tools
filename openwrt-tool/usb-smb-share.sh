#!/bin/sh
# ==============================================================================
# OpenWrt — USB-накопитель в сетевую SMB-шару (ksmbd или Samba4 — выбор
# диалогом). Работает на любом роутере с OpenWrt, у которого есть USB-порт:
# опробовано на Cudy TR3000, но не завязано ни на конкретную модель, ни на
# конкретную платформу — используются только стандартные пакеты OpenWrt
# (opkg/apk) и стандартная UCI-схема (fstab/network/firewall), без
# специфичных для одного устройства путей. Разумные ограничения: пакетам
# нужно физически поместиться на флеш (ksmbd — легче, поэтому вариант по
# умолчанию), а на роутере должен быть сам USB-порт.
#
# Использование на роутере (через SSH):
#   wget -O - https://raw.githubusercontent.com/<USER>/<REPO>/main/usb-smb-share.sh | sh
#
# Вся настройка — через переменные окружения перед командой (все опциональны):
#   OPENWRT_TOOL_MOUNT_POINT      точка монтирования USB (по умолчанию /mnt/usb1)
#   OPENWRT_TOOL_FS_TYPE          ext4 | exfat | ntfs3 | vfat | f2fs (по умолчанию ext4)
#   OPENWRT_TOOL_SHARE_NAME       имя сетевой шары (по умолчанию share)
#   OPENWRT_TOOL_WORKGROUP        рабочая группа SMB (по умолчанию WORKGROUP)
#   OPENWRT_TOOL_SMB_USER         логин для доступа к шаре (по умолчанию smbuser)
#   OPENWRT_TOOL_SMB_BACKEND      ksmbd | samba4 — если не задано, скрипт спросит
#                                 интерактивно (см. ниже)
#   OPENWRT_TOOL_GUEST            1 — разрешить анонимный доступ (не рекомендуется)
#   OPENWRT_TOOL_WITH_CRON_ALERT  1 — сразу поставить ежедневную проверку заполнения диска
#   OPENWRT_TOOL_MODE             setup (по умолчанию) | status | swap-disk |
#                                 smb-backend | cron-alert
#
# Примеры:
#   OPENWRT_TOOL_FS_TYPE=exfat OPENWRT_TOOL_SHARE_NAME=movies \
#     wget -O - https://raw.githubusercontent.com/<USER>/<REPO>/main/usb-smb-share.sh | sh
#
#   wget -O /root/usb-smb-share.sh https://raw.githubusercontent.com/<USER>/<REPO>/main/usb-smb-share.sh
#   OPENWRT_TOOL_MODE=status sh /root/usb-smb-share.sh
#
# Выбор SMB-сервера: если OPENWRT_TOOL_SMB_BACKEND не задан, скрипт задаст
# вопрос прямо в SSH-сессии (ksmbd — по умолчанию, просто Enter) — как при
# первой установке, так и в режиме smb-backend. Чтобы не отвечать на вопрос
# при автоматическом/неинтерактивном запуске, задайте
# OPENWRT_TOOL_SMB_BACKEND заранее.
#
# Режимы после первоначальной настройки (не требуют переустановки пакетов
# USB/ФС):
#   OPENWRT_TOOL_MODE=status       показать место на диске, скорость USB, статус SMB, логи
#   OPENWRT_TOOL_MODE=swap-disk    переключить шару на ДРУГОЙ физический накопитель
#   OPENWRT_TOOL_MODE=smb-backend  переустановить/переключить SMB-сервер (ksmbd<->samba4)
#                                  на уже настроенной шаре, без переразметки диска —
#                                  старый backend останавливается, отключается и
#                                  удаляется (освобождает флеш), новый настраивается
#                                  заново (пароль SMB-пользователя вводится повторно —
#                                  базы паролей ksmbd/samba4 не совместимы)
#   OPENWRT_TOOL_MODE=cron-alert   поставить ежедневную проверку заполнения диска отдельно
#
# Особенность: выбор раздела (если накопителей несколько), выбор SMB-сервера,
# а также ввод пароля SMB-пользователя (ksmbd.adduser/smbpasswd) требуют
# интерактивного ввода. Так как при запуске через "wget -O- ... | sh"
# стандартный ввод скрипта уже занят телом самого скрипта, все такие места
# явно читают из /dev/tty — реального терминала SSH-сессии, а не из
# перекрытого stdin (без этого ksmbd.adduser мгновенно получает EOF вместо
# пароля и завершается, даже не дав его ввести).
# ==============================================================================

set -e

SELF_DIR=/root/openwrt-tool
SELF_PATH="$SELF_DIR/usb-smb-share.sh"
LOG_FILE="$SELF_DIR/usb-smb-share.log"
# Здесь скрипт запоминает, какой SMB-сервер сейчас настроен ("ksmbd" или
# "samba4") — используется в режиме smb-backend, чтобы понять, что именно
# нужно остановить/удалить перед переключением на другой сервер.
SMB_BACKEND_FILE="$SELF_DIR/.smb_backend"
# ЗАМЕНИТЕ на прямую ссылку (raw) на этот файл в вашем репозитории, если
# форкаете или переносите проект в другой репозиторий:
SCRIPT_URL="https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh"

OPENWRT_TOOL_MOUNT_POINT="${OPENWRT_TOOL_MOUNT_POINT:-/mnt/usb1}"
OPENWRT_TOOL_FS_TYPE="${OPENWRT_TOOL_FS_TYPE:-ext4}"
OPENWRT_TOOL_SHARE_NAME="${OPENWRT_TOOL_SHARE_NAME:-share}"
OPENWRT_TOOL_WORKGROUP="${OPENWRT_TOOL_WORKGROUP:-WORKGROUP}"
OPENWRT_TOOL_SMB_USER="${OPENWRT_TOOL_SMB_USER:-smbuser}"
OPENWRT_TOOL_SMB_BACKEND="${OPENWRT_TOOL_SMB_BACKEND:-}"
OPENWRT_TOOL_MODE="${OPENWRT_TOOL_MODE:-setup}"

PKG_MANAGER=""

GUEST_OK="no"
case "${OPENWRT_TOOL_GUEST:-0}" in
    1|yes|true|YES|TRUE) GUEST_OK="yes" ;;
esac

WITH_CRON_ALERT="no"
case "${OPENWRT_TOOL_WITH_CRON_ALERT:-0}" in
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

# Используется при переключении SMB-сервера (OPENWRT_TOOL_MODE=smb-backend), чтобы
# не держать на флеше пакеты сразу от ksmbd и samba4 одновременно.
pkg_remove() {
    pkg_init
    case "$PKG_MANAGER" in
        apk) apk del "$@" ;;
        opkg) opkg remove "$@" ;;
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

# Диалог выбора SMB-сервера. Если OPENWRT_TOOL_SMB_BACKEND уже задан переменной
# окружения — используем его без вопросов (для неинтерактивных запусков).
# Иначе спрашиваем прямо в SSH-сессии через /dev/tty (см. комментарий вверху
# файла про перекрытый stdin при "wget | sh"). Весь вывод вопроса идёт в
# stderr, чтобы не попасть в "$(choose_smb_backend)" — на stdout уходит
# только итоговое имя backend'а.
choose_smb_backend() {
    case "$OPENWRT_TOOL_SMB_BACKEND" in
        ksmbd|samba4)
            echo "$OPENWRT_TOOL_SMB_BACKEND"
            return 0
            ;;
        "") ;;
        *)
            echo "Недопустимый OPENWRT_TOOL_SMB_BACKEND='$OPENWRT_TOOL_SMB_BACKEND' (ksmbd|samba4)" >&2
            exit 1
            ;;
    esac

    {
        echo ""
        echo "Выберите SMB-сервер для сетевой шары:"
        echo "  1) ksmbd  — облегчённый (в ядре Linux), меньше нагружает флеш/память (по умолчанию)"
        echo "  2) samba4 — полноценный Samba, больше функций и совместимости, тяжелее"
        printf "Ваш выбор [1]: "
    } >&2
    read -r choice < /dev/tty

    case "$choice" in
        2|samba4) echo "samba4" ;;
        ""|1|ksmbd) echo "ksmbd" ;;
        *)
            echo "Некорректный выбор '$choice', использую ksmbd по умолчанию" >&2
            echo "ksmbd"
            ;;
    esac
}

# Какой SMB-сервер сейчас реально настроен на роутере: сначала смотрим
# маркер этого скрипта (SMB_BACKEND_FILE), а если его нет (например, шара
# была настроена более старой версией этого скрипта) — определяем по наличию
# UCI-секции соответствующего сервера. Пустой результат — сервер ещё не
# настраивался.
detect_current_backend() {
    if [ -f "$SMB_BACKEND_FILE" ]; then
        cat "$SMB_BACKEND_FILE"
        return 0
    fi
    if uci -q get ksmbd.usbshare >/dev/null 2>&1; then
        echo "ksmbd"
        return 0
    fi
    if uci -q get samba4.usbshare >/dev/null 2>&1; then
        echo "samba4"
        return 0
    fi
    echo ""
}

# Устанавливает пакеты и настраивает UCI-секцию выбранного SMB-сервера,
# создаёт SMB-пользователя (пароль запрашивается заново — базы паролей
# ksmbd/samba4 отдельные и не переносятся друг в друга), включает и
# перезапускает службу. Используется и при первой настройке (do_setup), и
# при переключении сервера (do_smb_backend). $1 — backend, $2 — путь шары.
setup_smb_backend() {
    backend="$1"
    share_path="$2"

    case "$backend" in
        ksmbd)
            if ! pkg_available ksmbd-server; then
                log "ksmbd-server недоступен в этой прошивке (нет в индексе пакетов)."
                log "Запустите заново с OPENWRT_TOOL_SMB_BACKEND=samba4, чтобы использовать полноценный Samba4."
                exit 1
            fi
            pkg_install ksmbd-server luci-app-ksmbd

            uci set ksmbd.globals=globals
            uci set ksmbd.globals.workgroup="$OPENWRT_TOOL_WORKGROUP"
            uci set ksmbd.globals.description="OpenWrt USB Share"
            uci set ksmbd.globals.interface="lan"

            uci -q delete ksmbd.usbshare 2>/dev/null || true
            uci set ksmbd.usbshare="share"
            uci set ksmbd.usbshare.name="$OPENWRT_TOOL_SHARE_NAME"
            uci set ksmbd.usbshare.path="$share_path"
            uci set ksmbd.usbshare.guest_ok="$GUEST_OK"
            uci set ksmbd.usbshare.read_only="no"
            uci set ksmbd.usbshare.browseable="yes"
            if [ "$GUEST_OK" = "no" ]; then
                uci set ksmbd.usbshare.users="$OPENWRT_TOOL_SMB_USER"
            fi
            uci commit ksmbd

            log "Создание пользователя SMB ($OPENWRT_TOOL_SMB_USER) — сейчас будет запрошен пароль дважды"
            ksmbd.adduser -a "$OPENWRT_TOOL_SMB_USER" < /dev/tty

            /etc/init.d/ksmbd enable
            /etc/init.d/ksmbd restart
            ;;
        samba4)
            pkg_install samba4-server samba4-utils luci-app-samba4

            uci set samba4.@samba[0].workgroup="$OPENWRT_TOOL_WORKGROUP"
            uci set samba4.@samba[0].description="OpenWrt USB Share"

            uci -q delete samba4.usbshare 2>/dev/null || true
            uci set samba4.usbshare="sambashare"
            uci set samba4.usbshare.name="$OPENWRT_TOOL_SHARE_NAME"
            uci set samba4.usbshare.path="$share_path"
            uci set samba4.usbshare.guest_ok="$GUEST_OK"
            uci set samba4.usbshare.create_mask="0700"
            uci set samba4.usbshare.dir_mask="0700"
            if [ "$GUEST_OK" = "no" ]; then
                uci set samba4.usbshare.users="$OPENWRT_TOOL_SMB_USER"
            fi
            uci commit samba4

            log "Создание пользователя SMB ($OPENWRT_TOOL_SMB_USER) — сейчас будет запрошен пароль дважды"
            smbpasswd -a "$OPENWRT_TOOL_SMB_USER" < /dev/tty

            /etc/init.d/samba4 enable
            /etc/init.d/samba4 restart
            ;;
        *)
            log "Неизвестный SMB-backend '$backend' (ksmbd|samba4)"
            exit 1
            ;;
    esac

    echo "$backend" > "$SMB_BACKEND_FILE"
}

# Останавливает, отключает и удаляет пакеты СТАРОГО SMB-сервера перед
# переключением на другой — без этого на флеше остались бы висеть сразу два
# сервера, а старая UCI-секция шары продолжала бы существовать рядом с новой.
teardown_smb_backend() {
    old_backend="$1"
    case "$old_backend" in
        ksmbd)
            /etc/init.d/ksmbd stop 2>/dev/null || true
            /etc/init.d/ksmbd disable 2>/dev/null || true
            uci -q delete ksmbd.usbshare 2>/dev/null || true
            uci -q delete ksmbd.globals 2>/dev/null || true
            uci commit ksmbd 2>/dev/null || true
            log "Удаляю пакеты старого SMB-сервера (ksmbd) — освобождаю флеш"
            pkg_remove ksmbd-server luci-app-ksmbd 2>/dev/null || true
            ;;
        samba4)
            /etc/init.d/samba4 stop 2>/dev/null || true
            /etc/init.d/samba4 disable 2>/dev/null || true
            uci -q delete samba4.usbshare 2>/dev/null || true
            uci commit samba4 2>/dev/null || true
            log "Удаляю пакеты старого SMB-сервера (samba4) — освобождаю флеш"
            pkg_remove samba4-server samba4-utils luci-app-samba4 2>/dev/null || true
            ;;
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
    case "$OPENWRT_TOOL_FS_TYPE" in
        ext4|exfat|ntfs3|vfat|f2fs) ;;
        *) log "Недопустимый OPENWRT_TOOL_FS_TYPE='$OPENWRT_TOOL_FS_TYPE' (ext4|exfat|ntfs3|vfat|f2fs)"; exit 1 ;;
    esac

    # Спрашиваем backend сразу, до сетевых операций — чтобы не заставлять
    # ждать перед вопросом, на который всё равно нужен ручной ответ.
    backend="$(choose_smb_backend)"

    wait_for_network

    log "=== Обновление списков пакетов ==="
    pkg_update

    log "=== Установка пакетов для USB и файловых систем ==="
    # kmod-usb-storage обязателен — без него накопитель в принципе не
    # появится. kmod-usb3/kmod-usb-storage-uas нужны только на роутерах с
    # USB 3.0/UAS — на части таргетов (например, чисто USB 2.0 платформы)
    # такого пакета вообще нет в индексе, и безусловная установка уронила бы
    # весь скрипт под "set -e". Ставим их, только если они есть в индексе.
    pkg_install kmod-usb-storage block-mount e2fsprogs fdisk
    pkg_available kmod-usb3 && pkg_install kmod-usb3
    pkg_available kmod-usb-storage-uas && pkg_install kmod-usb-storage-uas

    case "$OPENWRT_TOOL_FS_TYPE" in
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
        vfat)
            # FAT32: ограничение 4 ГБ на файл — годится для документов/фото,
            # не годится для больших видео/бэкапов.
            pkg_install kmod-fs-vfat kmod-nls-cp437 kmod-nls-iso8859-1
            mount_fstype="vfat"
            ;;
        f2fs)
            if ! pkg_available kmod-fs-f2fs; then
                log "kmod-fs-f2fs недоступен в этой прошивке (нет в индексе пакетов)."
                log "Переформатируйте накопитель в ext4 (рекомендуется) или другую поддерживаемую ФС и повторите."
                exit 1
            fi
            pkg_install kmod-fs-f2fs
            pkg_available f2fs-tools && pkg_install f2fs-tools
            mount_fstype="f2fs"
            ;;
    esac

    log "=== Установка SMB-сервера ($backend) ==="
    setup_smb_backend "$backend" "$OPENWRT_TOOL_MOUNT_POINT"

    log "=== Поиск подключённого USB-накопителя ==="
    find_usb_partition
    log "Выбран раздел $USB_DEV (UUID=$USB_UUID)"

    mkdir -p "$OPENWRT_TOOL_MOUNT_POINT"

    log "=== Настройка автомонтирования через UCI (fstab) ==="
    uci -q delete fstab.usbmount 2>/dev/null || true
    uci set fstab.usbmount="mount"
    uci set fstab.usbmount.uuid="$USB_UUID"
    uci set fstab.usbmount.target="$OPENWRT_TOOL_MOUNT_POINT"
    uci set fstab.usbmount.fstype="$mount_fstype"
    uci set fstab.usbmount.options="rw,noatime"
    uci set fstab.usbmount.enabled="1"
    uci commit fstab
    block mount

    log "Проверка firewall (зона lan должна разрешать input accept — обычно так по умолчанию)"
    uci show firewall | grep -A2 "zone\[.*\]\.name='lan'" || true

    lan_ip=$(uci get network.lan.ipaddr 2>/dev/null || echo "<ip роутера>")
    log "Готово! SMB-сервер: $backend"
    printf 'Шара доступна как: \\\\%s\\%s\n' "$lan_ip" "$OPENWRT_TOOL_SHARE_NAME"
    echo "Точка монтирования: $OPENWRT_TOOL_MOUNT_POINT (драйвер: $mount_fstype, UUID=$USB_UUID)"

    if [ "$WITH_CRON_ALERT" = "yes" ]; then
        do_cron_alert
    fi

    do_status
}

do_status() {
    echo
    echo "== Использование диска =="
    df -h "$OPENWRT_TOOL_MOUNT_POINT" 2>/dev/null || echo "$OPENWRT_TOOL_MOUNT_POINT не смонтирован"

    echo
    echo "== USB-устройства и скорость линка (5000=USB3, 480=USB2) =="
    for f in /sys/bus/usb/devices/*/speed; do
        dev=$(dirname "$f")
        echo "$dev: $(cat "$f" 2>/dev/null) Mbps"
    done

    echo
    echo "== Статус SMB-сервиса =="
    echo "Настроенный backend: $(detect_current_backend | sed 's/^$/неизвестен/')"
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

    cron_line="0 8 * * * USAGE=\$(df $OPENWRT_TOOL_MOUNT_POINT | awk 'NR==2{print \$5}' | tr -d '%'); [ \"\$USAGE\" -ge 90 ] && logger -t $marker \"Диск заполнен на \${USAGE}%\""

    # "|| true" обязателен: пока у root вообще нет crontab (типичный случай
    # при самом первом запуске), "crontab -l" завершается кодом 1. Под
    # "set -e" это прерывает подшелл ДО "echo", и в crontab улетает пустой
    # список — сообщение "Готово" при этом всё равно печатается. Проверено:
    # без "|| true" первый запуск создаёт пустой crontab, а нужная строка
    # реально попадает в crontab только со второго запуска.
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -
    /etc/init.d/cron restart
    log "Готово: ежедневная проверка (08:00) заполнения $OPENWRT_TOOL_MOUNT_POINT добавлена в cron (тег лога: $marker)."
}

do_swap_disk() {
    if ! uci get fstab.usbmount >/dev/null 2>&1; then
        log "Секция fstab.usbmount не найдена — сначала выполните первоначальную настройку (OPENWRT_TOOL_MODE=setup)."
        exit 1
    fi

    wait_for_network

    log "Отмонтирую текущий накопитель (если подключён)"
    umount "$OPENWRT_TOOL_MOUNT_POINT" 2>/dev/null || true

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
        f2fs)
            if ! pkg_available kmod-fs-f2fs; then
                log "kmod-fs-f2fs недоступен в этой прошивке."
                exit 1
            fi
            pkg_install kmod-fs-f2fs >/dev/null
            mount_fstype="f2fs"
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

    if ! grep -qs " ${OPENWRT_TOOL_MOUNT_POINT} " /proc/mounts; then
        log "Не удалось смонтировать $OPENWRT_TOOL_MOUNT_POINT. Проверьте 'logread' и 'dmesg' на роутере."
        exit 1
    fi

    df -h "$OPENWRT_TOOL_MOUNT_POINT"
    log "Готово: новый накопитель смонтирован в $OPENWRT_TOOL_MOUNT_POINT (драйвер: $mount_fstype)."
    echo "Шара, логин и пароль не менялись — доступ по тому же сетевому пути."
}

# Переустановка/переключение SMB-сервера на уже настроенной шаре (диск и
# точка монтирования не трогаются). Спрашивает backend тем же диалогом, что
# и do_setup; если выбран ДРУГОЙ backend, чем сейчас активен — старый
# останавливается, отключается и удаляется (teardown_smb_backend), новый
# ставится и настраивается заново (setup_smb_backend), включая повторный
# ввод пароля SMB-пользователя. Если выбран тот же backend — это просто
# переустановка поверх текущей конфигурации (например, чтобы поменять
# пользователя/пароль или почистить настройки).
do_smb_backend() {
    if ! uci get fstab.usbmount >/dev/null 2>&1; then
        log "Секция fstab.usbmount не найдена — сначала выполните первоначальную настройку (OPENWRT_TOOL_MODE=setup)."
        exit 1
    fi
    share_path="$(uci get fstab.usbmount.target)"

    target_backend="$(choose_smb_backend)"
    current_backend="$(detect_current_backend)"

    wait_for_network
    pkg_update

    if [ -n "$current_backend" ] && [ "$current_backend" != "$target_backend" ]; then
        log "Переключаю SMB-сервер: $current_backend -> $target_backend"
        teardown_smb_backend "$current_backend"
    elif [ "$current_backend" = "$target_backend" ]; then
        log "SMB-сервер уже $target_backend — переустанавливаю поверх текущей настройки"
    fi

    log "=== Настройка SMB-сервера ($target_backend) ==="
    setup_smb_backend "$target_backend" "$share_path"

    lan_ip=$(uci get network.lan.ipaddr 2>/dev/null || echo "<ip роутера>")
    log "Готово! Активный SMB-сервер: $target_backend"
    printf 'Шара доступна как: \\\\%s\\%s\n' "$lan_ip" "$OPENWRT_TOOL_SHARE_NAME"
}

# ---------------------------------------------------------------------------

ensure_local_copy

case "$OPENWRT_TOOL_MODE" in
    setup) do_setup ;;
    status) do_status ;;
    swap-disk) do_swap_disk ;;
    smb-backend) do_smb_backend ;;
    cron-alert) do_cron_alert ;;
    *)
        log "Неизвестный OPENWRT_TOOL_MODE='$OPENWRT_TOOL_MODE' (setup|status|swap-disk|smb-backend|cron-alert)"
        exit 1
        ;;
esac
