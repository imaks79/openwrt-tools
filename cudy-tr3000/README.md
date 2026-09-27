# cudy-tr3000

Два физических дополнения для Cudy TR3000 (прошивка на базе OpenWrt/LuCI):

- **`install-mode-button.sh`** — переключатель "mode" на корпусе управляет
  одной из трёх функций (выбор через `ACTION_MODE` при установке): либо
  включает/выключает Wi-Fi (по умолчанию), либо блокирует форвардинг
  LAN→WAN файрволом (Wi-Fi/LAN/USB-шара остаются доступны — приватное
  использование SMB-шары без выхода в интернет), либо включает/выключает
  подключение netbird. В защитном положении вместо белого статусного
  светодиода горит красный.
- **`install-reset-button.sh`** — короткое нажатие штатной кнопки reset
  переключает USB-накопитель (подключает новый/безопасно размонтирует
  текущий) без захода по SSH.

Сама настройка USB → сетевая SMB-шара переехала в универсальный скрипт
[`../openwrt-tool/usb-smb-share.sh`](../openwrt-tool/README.md) — он не
привязан к конкретной модели и работает на любом роутере с OpenWrt, у
которого есть USB-порт. Кнопка reset из этого каталога — необязательная
надстройка **поверх** него, специфичная именно для физической кнопки
Cudy TR3000.

## Обязательное условие для кнопки reset

`install-reset-button.sh` управляет уже существующей шарой — сначала
настройте её универсальным скриптом:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/openwrt-tool/usb-smb-share.sh | sh
```

Подробности, переменные окружения, режимы (`status`/`swap-disk`/
`smb-backend`/`cron-alert`), выбор SMB-сервера (ksmbd/samba4) — в
[openwrt-tool/README.md](../openwrt-tool/README.md).

Переключатель "mode" (Wi-Fi вкл/выкл, блокировка WAN либо netbird
вкл/выкл) от шары не зависит — его можно ставить независимо от всего
остального.

## Если форкаете этот проект

Этот каталог — часть монорепозитория
[openwrt-tools](https://github.com/imaks79/openwrt-tools), поэтому
raw-ссылки внутри скриптов включают префикс `cudy-tr3000/`.
Если форкаете или переносите **именно этот каталог** в отдельный
репозиторий — поменяйте `<USER>/<REPO>` (или полный путь, если у нового
репозитория нет такого подкаталога) в переменной `SCRIPT_URL` в обоих
файлах:

```sh
grep -rn '^SCRIPT_URL=' *.sh
```

Это `install-mode-button.sh` (качает `mode-button-wifi-toggle.sh`) и
`install-reset-button.sh` (качает `reset-button-usb-toggle.sh`). Учтите
также, что `reset-button-usb-toggle.sh` жёстко ссылается на
`/root/openwrt-tool/usb-smb-share.sh` (переменная `INSTALL_SH`) — если
переносите и `openwrt-tool` тоже, обновите и этот путь.

## Дополнительно: переключатель "mode" — Wi-Fi, блокировка WAN или netbird

Физический флажок "mode" на Cudy TR3000 управляет одной из трёх
взаимоисключающих функций — выбирается переменной `ACTION_MODE` при
установке:

- **`ACTION_MODE=wifi`** (по умолчанию) — включает/выключает Wi-Fi.
- **`ACTION_MODE=wan`** — блокирует/разблокирует форвардинг LAN→WAN
  файрволом (без `ifdown` — интерфейс и модемная/PPPoE-сессия не рвутся,
  включение обратно мгновенное). Wi-Fi, LAN и USB-шара продолжают
  работать как обычно, наружу в интернет трафик не идёт. Сценарий:
  приватно попользоваться SMB-шарой через недоверенную сеть, не открывая
  маршрут наружу.
- **`ACTION_MODE=netbird`** — включает/выключает подключение
  [netbird](https://netbird.io/) командами `netbird up`/`netbird down`.
  Требует уже установленного и настроенного netbird (пакет `netbird`,
  `/etc/init.d/netbird enable && /etc/init.d/netbird start`, логин
  `netbird login --setup-key <KEY>`) — сам демон/сервис скрипт не трогает,
  переключает только состояние подключения. Если бинарь `netbird` не
  найден — логирует предупреждение через `logger` и ничего не делает.

В защитном положении (Wi-Fi выключен, WAN заблокирован или netbird
отключён — в зависимости от `ACTION_MODE`) — вместо белого статусного
светодиода горит красный.

Установка одной строкой (лучше по кабелю/LAN — см. предупреждение ниже):

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
```

Чтобы переключатель блокировал WAN вместо Wi-Fi:

```sh
ACTION_MODE=wan \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
```

Чтобы переключатель включал/выключал netbird вместо Wi-Fi:

```sh
ACTION_MODE=netbird \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
```

Скрипт `install-mode-button.sh` скачивает `mode-button-wifi-toggle.sh` и
кладёт его в `/etc/rc.button/BTN_0` — так называется хук, который procd
вызывает на каждое физическое переключение флажка (переменная `BUTTON`
для этого GPIO равна `BTN_0`, хотя в device tree он подписан как "mode").
Также добавляет путь в `/etc/sysupgrade.conf`, чтобы файл пережил
обновление прошивки (`sysupgrade` без `-n` сохраняет только файлы из
этого списка).

Логика:

- Положение переключателя однозначно определяет желаемое состояние сети
  (`pressed` → обычный режим, `released` → защитный режим) — команда не
  повторяется, если сеть уже в нужном состоянии (защита от лишних
  перезапусков при повторных/дребезжащих событиях).
- В режиме `wan` блокируются все секции `forwarding` в
  `/etc/config/firewall`, ведущие в зону `wan` (независимо от исходной
  зоны — lan, guest и т.п.), а не только основная LAN.
- В режиме `netbird` желаемое состояние сравнивается с реальным через
  первую строку `netbird status` (`Daemon status: Connected` при
  установленном соединении) — команда `netbird up`/`down` не повторяется,
  если соединение уже в нужном состоянии.
- Пока активен защитный режим, гаснет штатный белый светодиод
  (`white:status`, на этой прошивке горит статически, без автотриггера) и
  загорается красный (`red:power`).

Имена LED (`red:power` / `white:status`) проверены на Cudy TR3000 256MB
v1 (OpenWrt 25.12.5, mediatek/filogic). На другой модели/прошивке сначала
проверьте `ls /sys/class/leds/` на роутере и при необходимости
переопределите перед установкой:

```sh
LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-mode-button.sh | sh
```

**Важно:** если вы зашли по SSH через сам Wi-Fi (а не по кабелю), то в
режиме `ACTION_MODE=wifi` переключение флажка в положение "выключено"
оборвёт и вашу же SSH-сессию вместе с сетью (в режиме `ACTION_MODE=wan`
Wi-Fi не трогается, но при заходе через WAN доступ пропадёт до обратного
переключения). Устанавливайте и тестируйте по LAN-кабелю. Проверить
логику без физической кнопки:

```sh
ACTION=released BUTTON=BTN_0 /etc/rc.button/BTN_0
ACTION=pressed  BUTTON=BTN_0 /etc/rc.button/BTN_0
```

Проверить режим `wan`, не переустанавливая скрипт:

```sh
ACTION_MODE=wan ACTION=released BUTTON=BTN_0 /etc/rc.button/BTN_0
ACTION_MODE=wan ACTION=pressed  BUTTON=BTN_0 /etc/rc.button/BTN_0
```

Проверить режим `netbird`, не переустанавливая скрипт (требует уже
настроенного netbird):

```sh
ACTION_MODE=netbird ACTION=released BUTTON=BTN_0 /etc/rc.button/BTN_0
ACTION_MODE=netbird ACTION=pressed  BUTTON=BTN_0 /etc/rc.button/BTN_0
```

## Дополнительно: переключение USB-накопителя кнопкой reset

Штатная кнопка reset на Cudy TR3000 (прошивка OpenWrt 25.12.5)
подключает/отключает USB-накопитель прямо на роутере — без SSH. Требует,
чтобы шара уже была настроена скриптом
[`../openwrt-tool/usb-smb-share.sh`](../openwrt-tool/README.md) (см. выше).

Штатная логика кнопки на этой прошивке (до установки):

- отпущена быстрее 1 сек — reboot;
- удержана 5 сек и дольше — сброс к заводским настройкам;
- удержана от 1 до 5 сек — не делала ничего («мёртвая зона»).

`install-reset-button.sh` меняет короткое нажатие (<1 сек, тот же порог,
что раньше был у reboot) на переключение накопителя, а **reboot с кнопки
убирает** — если он всё же понадобится, доступен по SSH (`reboot`) или
через LuCI:

- **Накопитель сейчас смонтирован** — короткое нажатие reset безопасно
  его размонтирует (как перед физическим извлечением).
- **Накопитель сейчас не смонтирован** — короткое нажатие reset
  выполняет `OPENWRT_TOOL_MODE=swap-disk sh /root/openwrt-tool/usb-smb-share.sh`,
  чтобы подхватить только что подключённый новый накопитель (тот же
  механизм, что описан в режиме `swap-disk` в
  [openwrt-tool/README.md](../openwrt-tool/README.md)).

Результат сигнализируется светодиодами и не требует смотреть в `logread`:

- **успех** (размонтировано или новый диск смонтирован) — белый
  светодиод (`white:status`) мигает 5 раз;
- **ошибка** (диск занят / не удалось смонтировать) — красный
  (`red:power`) горит 5 секунд сплошным светом.

`red:power` и `white:status` на этой прошивке физически один и тот же
индикатор (см. секцию про `mode-button-wifi-toggle.sh` выше) — поэтому на
время сигнала второй светодиод явно гасится (иначе оба остаются
включёнными одновременно и не видно ни однозначного красного, ни
однозначного белого). После сигнала оба светодиода возвращаются к тому
состоянию, в котором были до нажатия — это важно, если также установлен
`mode-button-wifi-toggle.sh`: он держит `red:power` включённым, пока
активен защитный режим (Wi-Fi выключен, WAN заблокирован или netbird
отключён — в зависимости от `ACTION_MODE`), и кнопка reset не собьёт эту
индикацию.

Удержание 5+ секунд (factory reset) не изменено. Удержание от 1 до
5 секунд по-прежнему ничего не делает.

**Ограничение:** `swap-disk` запускается без интерактивного терминала.
Если к роутеру одновременно подключено несколько USB-накопителей,
`usb-smb-share.sh` обычно просит выбрать раздел вручную — в контексте
кнопки такого ввода нет, поэтому выбор не сработает и это будет показано
как ошибка (красный на 5 секунд). Подключайте один накопитель за раз,
либо выбирайте раздел через SSH
(`OPENWRT_TOOL_MODE=swap-disk sh /root/openwrt-tool/usb-smb-share.sh`).

Установка одной строкой:

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
```

Заменяет штатный `/etc/rc.button/reset` и добавляет его в
`/etc/sysupgrade.conf`, чтобы правка пережила обновление прошивки. Лог
запусков `swap-disk` из этой кнопки пишется в
`/root/openwrt-tool/reset-button-swap-disk.log`.

Имена LED (`red:power` / `white:status`) проверены на Cudy TR3000 256MB
v1. На другой модели/прошивке сначала проверьте `ls /sys/class/leds/` и
при необходимости переопределите:

```sh
LED_RED_DIR=/sys/class/leds/<имя> LED_WHITE_DIR=/sys/class/leds/<имя> \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/cudy-tr3000/install-reset-button.sh | sh
```

Проверить без физической кнопки (эмуляция короткого нажатия):

```sh
SEEN=0 ACTION=released BUTTON=reset /etc/rc.button/reset
```
