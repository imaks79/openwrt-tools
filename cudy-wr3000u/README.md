# cudy-wr3000u

Кнопка WPS на Cudy WR3000U (OpenWrt, MediaTek MT7981B/Filogic) вместо
запуска WPS-подключения переключает по длительности удержания:

| Удержание | Действие |
|---|---|
| < 2 с | Wi-Fi вкл/выкл (все радиомодули) |
| 2–5 с | wireguard и amneziawg вкл/выкл (`ifdown`/`ifup` всех интерфейсов с таким proto) — клиенты не смогут подключиться; повторное удержание поднимает обратно |
| ≥ 5 с | netbird вкл/выкл (`netbird down`/`up`; netbird должен быть установлен и залогинен). `up`/`down` ограничены `NETBIRD_TIMEOUT` (20 с) |

Светодиоды **не используются**: на этой модели все они заняты штатными
индикаторами системы. Результат смотрите в логе: `logread -e rc.button.wps`.

Раньше длинное нажатие монтировало/размонтировало USB-накопитель
(`swap-disk`), а короткое имело режимы `wifi`/`wan`/`netbird` (`ACTION_MODE`).
Всё это убрано; для USB-шары используйте `openwrt-tool/usb-smb-share.sh`
вручную.

## Установка

Подключайтесь **по кабелю**, не по Wi-Fi — нажатие обрывает Wi-Fi-сессию.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
```

Хук ставится в `/etc/rc.button/wps` (старый файл сохраняется как
`wps.orig`) и добавляется в `/etc/sysupgrade.conf`. Если netbird лежит не в
`PATH` — `NETBIRD_BIN=/путь/к/netbird` перед `wget`.

## Проверка без физической кнопки

```sh
SEEN=0 ACTION=released BUTTON=wps /etc/rc.button/wps   # Wi-Fi
SEEN=3 ACTION=released BUTTON=wps /etc/rc.button/wps   # wireguard/amneziawg
SEEN=6 ACTION=released BUTTON=wps /etc/rc.button/wps   # netbird
```

Длительность берётся из `SEEN` (секунды, которые `button-hotplug` добавляет
к событию `released`). Каждый запуск инвертирует текущее состояние.
