# xiaomi-ax3000t

Кнопка **Mesh** на Xiaomi AX3000T (OpenWrt, MediaTek MT7981B): однократное
нажатие включает/выключает Wi-Fi целиком (все радиомодули). Пока Wi-Fi
выключен — горит светодиод `yellow:status` (синий гаснет; отдельного красного LED в системе нет — на реальном роутере `ls /sys/class/leds/` показывает только `blue:status` и `yellow:status`); при включении жёлтый
гаснет, синий возвращается. Состояние переживает перезагрузку (LED
синхронизируется при старте через `/etc/rc.local`).

## Установка

Подключайтесь **по кабелю**, не по Wi-Fi — нажатие обрывает Wi-Fi-сессию.

```sh
wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
```

Кнопка Mesh в device tree — `BTN_9`, поэтому хук ставится в
`/etc/rc.button/BTN_9`. LED определяются автоматически (`*red*` или `yellow:status`, и `*blue*`); если на вашей прошивке не подходит —
проверьте `ls /sys/class/leds/` и переопределите:

```sh
LED_RED_DIR=/sys/class/leds/<имя> LED_BLUE_DIR=/sys/class/leds/<имя> \
  wget -O - https://raw.githubusercontent.com/imaks79/openwrt-tools/main/xiaomi-ax3000t/install-mesh-button.sh | sh
```

Проверка без физической кнопки: `ACTION=released BUTTON=BTN_9 /etc/rc.button/BTN_9`.
Логи: `logread -e rc.button.mesh`.
