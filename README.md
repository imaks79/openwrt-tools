# openwrt-tools

Набор утилит для роутеров на прошивке OpenWrt. Каждая живёт в своём
подкаталоге со своей подробной документацией — здесь только обзор и
команды для быстрого запуска одной строкой, чтобы не искать их по разным
репозиториям или по всему документу. Большинство подкаталогов полностью
самостоятельны; исключение — USB-функция кнопки reset в `cudy-tr3000`,
которая работает поверх шары, настроенной универсальным
`openwrt-tool/usb-smb-share.sh` (см. ниже).

## Быстрый старт

### [cudy-tr3000](02%20Projects/Github/openwrt-tools/cudy-tr3000/README.md)

Два опциональных дополнения для физических кнопок Cudy TR3000 (сама
сетевая шара теперь настраивается универсальным `usb-smb-share.sh` из
`openwrt-tool`, см. ниже).

Переключатель "mode" → Wi-Fi вкл/выкл + красный LED:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
```

Кнопка reset → < 1 сек: подключить новый USB-накопитель или безопасно
размонтировать текущий (требует, чтобы шара уже была настроена
`usb-smb-share.sh`); 1–5 сек: netbird вкл/выкл; ≥ 5 сек: заводской сброс:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
```

Имена LED и все нюансы — в
[cudy-tr3000/README.md](02%20Projects/Github/openwrt-tools/cudy-tr3000/README.md).

### [cudy-wr3000u](02%20Projects/Github/openwrt-tools/cudy-wr3000u/README.md)

Кнопка WPS роутера Cudy WR3000U по длительности удержания: < 2 сек →
Wi-Fi вкл/выкл; 2–5 сек → wireguard/amneziawg вкл/выкл; ≥ 5 сек → netbird
вкл/выкл. Светодиоды не используются.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
```

Подробности — в [cudy-wr3000u/README.md](02%20Projects/Github/openwrt-tools/cudy-wr3000u/README.md).

### [xiaomi-ax3000t](xiaomi-ax3000t/README.md)

Кнопка Mesh роутера Xiaomi AX3000T по длительности удержания: < 2 сек →
Wi-Fi вкл/выкл; 2–5 сек → wireguard/amneziawg вкл/выкл; ≥ 5 сек → netbird
вкл/выкл (после отключения VPN/netbird синий LED моргает дважды). Индикатор:
жёлтый — есть подключённый пир (даже при выключенном Wi-Fi), синий — пиров
нет и Wi-Fi включён, погашен — пиров нет и Wi-Fi выключен. LED обновляет
фоновый опрос каждые 5 сек.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
```

Подключайтесь по кабелю — нажатие обрывает Wi-Fi-сессию. Нюансы, настройка
порогов и переопределение LED — в [xiaomi-ax3000t/README.md](xiaomi-ax3000t/README.md).

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
├── cudy-tr3000/                    mode → Wi-Fi, reset → USB/netbird/factory reset для Cudy TR3000 (поверх openwrt-tool)
├── cudy-wr3000u/                   Кнопка WPS → Wi-Fi / wireguard+amneziawg / netbird для Cudy WR3000U
├── xiaomi-ax3000t/                 Кнопка Mesh → Wi-Fi / wireguard+amneziawg / netbird + LED по пирам для Xiaomi AX3000T
└── openwrt-tool/                   Два универсальных скрипта: setup+AdGuard Home и USB-шара
```

Каждый подкаталог — свои скрипты и своя документация, разворачиваются на
роутере одной командой `wget -O - <url> | sh` и хранят историю разработки
в этом репозитории. Зависимость между каталогами одна: кнопка reset в `cudy-tr3000` вызывает
`openwrt-tool/usb-smb-share.sh` (режим `swap-disk`), поэтому шару сначала
нужно настроить им; всё остальное независимо.
