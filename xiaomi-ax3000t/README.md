# xiaomi-ax3000t

Кнопка **Mesh** на Xiaomi AX3000T (OpenWrt, MediaTek MT7981B).

| Удержание | Действие |
|---|---|
| < 2 с | Wi-Fi вкл/выкл (все радиомодули) |
| 2–5 с | wireguard и amneziawg вкл/выкл (`ifdown`/`ifup` всех интерфейсов с таким proto) — клиенты не смогут подключиться; повторное удержание поднимает обратно |
| ≥ 5 с | netbird вкл/выкл (`netbird down`/`up`; netbird должен быть уже установлен и залогинен) |

После успешного **отключения** wireguard/amneziawg или netbird синий LED моргает два раза.

Индикатор (`blue:status` / `yellow:status`):

- Wi-Fi выключен — оба LED погашены;
- Wi-Fi включён, пиров нет — синий;
- Wi-Fi включён, есть подключённый пир (wireguard/amneziawg — handshake не старше 180 с, netbird — есть Connected-пир) — жёлтый.

LED пересчитывается при загрузке (`/etc/rc.local`) и раз в минуту из cron, чтобы следовать за подключением пиров. У wireguard без `persistent_keepalive` и без трафика handshake может устаревать — тогда LED вернётся в синий.

## Установка

Подключайтесь **по кабелю**, не по Wi-Fi — нажатие обрывает Wi-Fi-сессию.

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

Проверка без физической кнопки: `ACTION=released BUTTON=BTN_9 /etc/rc.button/BTN_9`.
Логи: `logread -e rc.button.mesh`.
