# openwrt-tools

Набор независимых друг от друга утилит для роутеров на прошивке OpenWrt.
Каждая живёт в своём подкаталоге со своей подробной документацией — здесь
только обзор и команды для быстрого запуска одной строкой, чтобы не
искать их по разным репозиториям или по всему документу.

## Быстрый старт

### [cudy-tr3000-usb-share](02%20Projects/Github/openwrt-tools/cudy-tr3000-usb-share/README.md)

USB 3.0 порт роутера Cudy TR3000 → сетевая SMB-шара (Windows/macOS/Linux/
Android/iOS), плюс два опциональных дополнения для физических кнопок
роутера.

Сетевая шара (основной скрипт):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install.sh | sh
```

Переключатель "mode" → Wi-Fi вкл/выкл + красный LED (опционально):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-mode-button.sh | sh
```

Кнопка reset → короткое нажатие подключает новый накопитель или
безопасно размонтирует текущий (опционально):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000-usb-share/install-reset-button.sh | sh
```

Переменные окружения, режимы (`status`/`swap-disk`/`cron-alert`),
troubleshooting NTFS, имена LED и все нюансы — в
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

Первоначальная настройка чистого OpenWrt-роутера: обновление системы,
AdGuard Home, podkop, тема LuCI и сетевые UCI-настройки — за один проход
и два самостоятельных ребута.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/install.sh | sh
```

Переопределение hostname/LAN-IP, смена пароля AdGuard Home, логи — в
[openwrt-tool/README.md](02%20Projects/Github/openwrt-tools/openwrt-tool/README.md).

## Структура репозитория

```
openwrt-tools/
├── cudy-tr3000-usb-share/          USB-шара + кнопки mode/reset для Cudy TR3000
├── cudy-wr3000u-wps-wifi-toggle/   Кнопка WPS → Wi-Fi вкл/выкл + LED для Cudy WR3000U
└── openwrt-tool/                   Первоначальная настройка OpenWrt + AdGuard Home
```

Каждый подкаталог — самостоятельный проект (свои скрипты, своя
документация, устанавливаются независимо друг от друга); общее у них
только то, что оба разворачиваются на роутере одной командой
`wget -O - <url> | sh` и хранят историю разработки в этом репозитории.
