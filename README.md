# openwrt-tools

Набор утилит для роутеров на прошивке OpenWrt. Каждая живёт в своём
подкаталоге со своей подробной документацией — здесь только обзор и
команды для быстрого запуска одной строкой, чтобы не искать их по разным
репозиториям или по всему документу. Большинство подкаталогов полностью
самостоятельны; исключение — USB-функция кнопки reset в `cudy-tr3000`,
которая работает поверх шары, настроенной универсальным
`openwrt-tool/usb-smb-share.sh` (см. ниже).

## Что делают кнопки

Сводка действий, которые назначают скрипты из этого репозитория. Каждое
нажатие-переключатель инвертирует текущее состояние (вкл → выкл и обратно).

| Роутер | Кнопка (хук) | Нажатие | Действие | Индикация |
|---|---|---|---|---|
| Cudy TR3000 | флажок mode (`/etc/rc.button/BTN_0`) | положение «включено» (`pressed`) | Wi-Fi включён (все радиомодули) | белый LED |
| | | положение «выключено» (`released`) | Wi-Fi выключен — защитный режим | красный LED вместо белого |
| Cudy TR3000 | reset (`/etc/rc.button/reset`) | < 1 с | USB-накопитель: размонтировать текущий, до 60 с искать и смонтировать новый (`swap-disk`) | успех — белый мигает 5 раз; ошибка — красный горит 5 с |
| | | 1–5 с | netbird вкл/выкл (`netbird up`/`down`) | то же |
| | | ≥ 5 с | сброс к заводским настройкам (как в штатной прошивке) | — |
| Cudy WR3000U | WPS (`/etc/rc.button/wps`) | < 2 с | Wi-Fi вкл/выкл (все радиомодули) | нет, только `logread -e rc.button.wps` |
| | | 2–5 с | wireguard и amneziawg вкл/выкл (`ifdown`/`ifup`) | то же |
| | | ≥ 5 с | netbird вкл/выкл (`netbird down`/`up`) | то же |
| Xiaomi AX3000T | Mesh (`/etc/rc.button/BTN_9`) | < 2 с | Wi-Fi вкл/выкл (все радиомодули) | синий — Wi-Fi включён, погашен — выключен (если нет пиров) |
| | | 2–5 с | wireguard и amneziawg вкл/выкл (`ifdown`/`ifup`) | после отключения синий моргает 2 раза |
| | | ≥ 5 с | netbird вкл/выкл (`netbird down`/`up`) | после отключения синий моргает 2 раза |

Штатные функции, которые при этом пропадают: reboot по короткому нажатию
reset на TR3000 и запуск WPS-подключения на WR3000U. На AX3000T жёлтый LED
дополнительно показывает, что есть подключённый пир (wireguard/amneziawg
или netbird), независимо от Wi-Fi.

## Быстрый старт

### [cudy-tr3000](cudy-tr3000/README.md)

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
[cudy-tr3000/README.md](cudy-tr3000/README.md).

### [cudy-wr3000u](cudy-wr3000u/README.md)

Кнопка WPS роутера Cudy WR3000U по длительности удержания: < 2 сек →
Wi-Fi вкл/выкл; 2–5 сек → wireguard/amneziawg вкл/выкл; ≥ 5 сек → netbird
вкл/выкл. Светодиоды не используются.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
```

Подробности — в [cudy-wr3000u/README.md](cudy-wr3000u/README.md).

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

### [openwrt-tool](openwrt-tool/README.md)

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
[openwrt-tool/README.md](openwrt-tool/README.md).

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
