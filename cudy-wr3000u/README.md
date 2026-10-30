# cudy-wr3000u

Кнопка WPS на Cudy WR3000U (OpenWrt, MediaTek MT7981B/Filogic) вместо
запуска WPS-подключения выполняет одно действие:

| Нажатие | Действие |
|---|---|
| любое (длительность не важна) | агент netbird вкл/выкл (`netbird up`/`down`; netbird должен быть установлен и залогинен). `up`/`down` ограничены `NETBIRD_TIMEOUT` (20 с) |

Светодиоды **не используются**: на этой модели все они заняты штатными
индикаторами системы. Результат смотрите в логе: `logread -e rc.button.wps`.

Раньше кнопка по длительности удержания также переключала Wi-Fi и
wireguard/amneziawg, а ещё раньше — монтировала USB-накопитель
(`swap-disk`). Всё это убрано; для USB-шары используйте
`openwrt-tool/usb-smb-share.sh` вручную.

## Установка

Не заходите по SSH через netbird — нажатие отключит netbird и оборвёт сессию.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-wr3000u/install-wps-button.sh | sh
```

Хук ставится в `/etc/rc.button/wps` (старый файл сохраняется как
`wps.orig`) и добавляется в `/etc/sysupgrade.conf`. Если netbird лежит не в
`PATH` — `NETBIRD_BIN=/путь/к/netbird` перед `wget`.

## Проверка без физической кнопки

```sh
ACTION=released BUTTON=wps /etc/rc.button/wps   # netbird вкл/выкл
```

Каждый запуск инвертирует текущее состояние netbird.
