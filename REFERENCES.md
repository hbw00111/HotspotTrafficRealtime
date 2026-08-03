# 参考实现

这个项目的实现方向参考了 GitHub 上的几个公开项目，代码没有直接复制。

`MostafaDadkhah/network-traffic-dashboard` 提供了 SQLite 保存采样、按日和按小时聚合、应用排行，以及把 `MacPacketTunnel` / `Shadowrocket` 作为隧道传输单独展示的思路。

`Draam1988/nettop-dashboard` 提供了 macOS `nettop` 的进程解析、PID 拆分和采集错误处理思路。

`corvid-agent/Netwatch` 提供了 Swift 原生调用 `nettop`、SwiftUI 菜单栏监控和本地进程流量模型的参考。

`foamzou/ITraffic-monitor-for-mac` 提供了常驻 `nettop` 的伪终端处理思路：通过 `/usr/bin/script` 保持伪终端和标准输入，避免后台采集空转占 CPU；本项目据此重新实现了自己的流式采集器，并采集全部 `external` 外部网络流量，其中包含 VPN 隧道流量，在用户的热点场景中代表热点消耗。该项目采用 MIT 许可。

参考链接：

https://github.com/MostafaDadkhah/network-traffic-dashboard

https://github.com/Draam1988/nettop-dashboard

https://github.com/corvid-agent/Netwatch

https://github.com/foamzou/ITraffic-monitor-for-mac
