Скрипт должен выполнять следующий набор команд:
Сразу скажу что команда: uci set attendedsysupgrade.client.login_check_for_upgrades='1' не применяется, это тоже нужно првоерить.
```sh
apk update && \
apk upgrade && \ 
wget -qO- https://raw.githubusercontent.com/ChesterGoodiny/luci-theme-proton2025/main/install.sh | sh && \
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh) && \
apk add luci-app-adguardhome
```

```sh
uci set system.@system[0].hostname='cudy_router' && \
uci set attendedsysupgrade.client.login_check_for_upgrades='1' && \
uci set dropbear.@dropbear[0].PasswordAuth='0' && \
uci set dropbear.@dropbear[0].RootPasswordAuth='0' && \
uci set dropbear.@dropbear[0].Port='2222' && \
uci set uhttpd.main.redirect_https='1' && \
uci set network.lan.ipaddr='192.168.3.1' && \
uci set network.lan.netmask='255.255.255.0' && \
uci set dhcp.lan.start='100' && \
uci set dhcp.lan.limit='150' && \
uci set dhcp.lan.leasetime='12h' && \
uci set dhcp.lan.force='1' && \
uci set network.lan.delegate='0' && \
uci set network.wan.ipv6='0' && \
uci set network.wan.delegate='0' && \
uci set network.wan6.proto='none' && \
uci set network.lan.ipv6='0' && \
uci -q delete dhcp.lan.ra && \
uci -q delete network.globals.ula_prefix && \
uci set dhcp.lan.ra='disabled' && \
uci set dhcp.lan.dhcpv6='disabled' && \
uci set dhcp.lan.ra_management='0' && \
uci delete dhcp.lan.ra_flags && \
uci set dhcp.@dnsmasq[0].port='5353' && \
uci add_list dhcp.lan.dhcp_option='6,192.168.3.1' && \
uci commit system && \
uci commit dropbear && \
uci commit uhttpd && \
uci commit network && \
uci commit dhcp && \
/etc/init.d/odhcpd disable && \
/etc/init.d/odhcpd stop && \
reboot
```
