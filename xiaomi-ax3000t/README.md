# xiaomi-ax3000t

Кнопка **Mesh** на Xiaomi AX3000T (OpenWrt, MediaTek MT7981B).

| Нажатие | Действие |
|---|---|
| любое (длительность не важна) | агент netbird вкл/выкл (`netbird up`/`down`; netbird должен быть уже установлен и залогинен) |

После успешного **отключения** netbird синий LED моргает два раза. Wi-Fi и
wireguard/amneziawg кнопка больше не переключает — они только учитываются в
индикации.

Индикатор (`blue:status` / `yellow:status`):

| Состояние | Светодиод |
|---|---|
| есть подключённый пир (Wi-Fi не важен) | жёлтый |
| пиров нет, Wi-Fi включён | синий |
| пиров нет, Wi-Fi выключен | оба погашены |
| только что отключён netbird | синий моргает 2 раза, затем обычная индикация |

Пир считается подключённым, если у wireguard/amneziawg вырос счётчик принятых байт за последние 30 с (`ACTIVE_WINDOW`; keepalive клиента тоже растит счётчик) или handshake не старше 5 с, а у netbird есть Connected-пир.

LED пересчитывает фоновый цикл (`ACTION=daemon`, запускается из `/etc/rc.local`) каждые 5 с (`POLL_INTERVAL`). Если клиент wireguard без keepalive и без трафика, пир будет считаться неактивным — индикатор синий.

Жёлтый гаснет через `ACTIVE_WINDOW` (30 с) + до 5 с после последнего пакета от клиента. Окно должно быть примерно на 5 с больше `PersistentKeepalive` клиента (обычно 25 с); чтобы сократить время, уменьшите keepalive на клиенте и `ACTIVE_WINDOW` в `/etc/rc.button/BTN_9`.

`netbird up`/`down` ограничены таймаутом `NETBIRD_TIMEOUT` (20 с): если netbird не залогинен, `up` ждёт SSO-вход и будет оборван — войдите один раз по SSH (`netbird up --setup-key <KEY>`). Состояние netbird определяется по `Management: Connected` (старый формат `Daemon status: Connected` тоже поддерживается). Если бинарь не в `PATH` — `NETBIRD_BIN=/путь/к/netbird` перед `wget`.

## Установка

Не заходите по SSH через netbird — нажатие отключит netbird и оборвёт сессию.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
```

Кнопка Mesh в device tree — `BTN_9`, поэтому хук ставится в
`/etc/rc.button/BTN_9`. LED определяются автоматически (`*yellow*` и `*blue*`); если на вашей прошивке не подходит —
проверьте `ls /sys/class/leds/` и переопределите:

```sh
LED_YELLOW_DIR=/sys/class/leds/<имя> LED_BLUE_DIR=/sys/class/leds/<имя> \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
```

Проверка без физической кнопки:

```sh
ACTION=released BUTTON=BTN_9 /etc/rc.button/BTN_9   # netbird вкл/выкл
```

Логи: `logread -e rc.button.mesh`.
