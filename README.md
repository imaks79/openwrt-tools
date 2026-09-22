# openwrt-tools

Набор утилит для роутеров на прошивке OpenWrt. Каждая живёт в своём
подкаталоге со своей подробной документацией — здесь только обзор и
команды для быстрого запуска одной строкой, чтобы не искать их по разным
репозиториям или по всему документу. Большинство подкаталогов полностью
самостоятельны; исключение — кнопка reset в `cudy-tr3000-usb-share`,
которая работает поверх шары, настроенной универсальным
`openwrt-tool/usb-smb-share.sh` (см. ниже).

## Быстрый старт

### [cudy-tr3000-usb-share](02%20Projects/Github/openwrt-tools/cudy-tr3000-usb-share/README.md)

Два опциональных дополнения для физических кнопок Cudy TR3000 (сама
сетевая шара теперь настраивается универсальным `usb-smb-share.sh` из
`openwrt-tool`, см. ниже).

Переключатель "mode" → Wi-Fi вкл/выкл + красный LED:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-mode-button.sh | sh
```

Кнопка reset → короткое нажатие подключает новый накопитель или
безопасно размонтирует текущий (требует, чтобы шара уже была настроена
`usb-smb-share.sh`):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-reset-button.sh | sh
```

Имена LED и все нюансы — в
[cudy-tr3000-usb-share/README.md](02%20Projects/Github/openwrt-tools/cudy-tr3000-usb-share/README.md).

### [cudy-wr3000u-wps-wifi-toggle](02%20Projects/Github/openwrt-tools/cudy-wr3000u-wps-wifi-toggle/README.md)

Кнопка WPS роутера Cudy WR3000U → Wi-Fi вкл/выкл (оба диапазона разом) +
два диапазонных LED панели (2.4 ГГц/5 ГГц), отражающих состояние каждого
диапазона.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u-wps-wifi-toggle/install-wps-button.sh | sh
```

Имена LED (`blue:wlan-2ghz`/`blue:wlan-5ghz`) подтверждены на реальном
устройстве; переопределение через переменные окружения и все нюансы — в
[cudy-wr3000u-wps-wifi-toggle/README.md](02%20Projects/Github/openwrt-tools/cudy-wr3000u-wps-wifi-toggle/README.md).

### [openwrt-tool](02%20Projects/Github/openwrt-tools/openwrt-tool/README.md)

Два универсальных скрипта, не привязанных к конкретной модели роутера.

Первоначальная настройка чистого OpenWrt-роутера: обновление системы,
AdGuard Home, podkop, тема LuCI и сетевые UCI-настройки — за один проход
и два самостоятельных ребута (требует apk-сборку OpenWrt, 23.05+/24.10+):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/install.sh | sh
```

USB-накопитель → сетевая SMB-шара (ksmbd/Samba4 — выбор диалогом) — на
любом роутере с OpenWrt, у которого есть USB-порт:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh
```

Переопределение hostname/LAN-IP/mount-point/SMB-сервера, режимы
(`status`/`swap-disk`/`smb-backend`/`cron-alert`), смена пароля AdGuard
Home, troubleshooting NTFS, логи — в
[openwrt-tool/README.md](02%20Projects/Github/openwrt-tools/openwrt-tool/README.md).

## Структура репозитория

```
openwrt-tools/
├── cudy-tr3000-usb-share/          Кнопки mode/reset для Cudy TR3000 (поверх openwrt-tool)
├── cudy-wr3000u-wps-wifi-toggle/   Кнопка WPS → Wi-Fi вкл/выкл + LED для Cudy WR3000U
└── openwrt-tool/                   Два универсальных скрипта: setup+AdGuard Home и USB-шара
```

Каждый подкаталог — свои скрипты и своя документация, разворачиваются на
роутере одной командой `wget -O - <url> | sh` и хранят историю разработки
в этом репозитории. Единственная зависимость между каталогами — кнопка
reset в `cudy-tr3000-usb-share` вызывает `openwrt-tool/usb-smb-share.sh`
(режим `swap-disk`), поэтому шару сначала нужно настроить им; всё
остальное независимо.
