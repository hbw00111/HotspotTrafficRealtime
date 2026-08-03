<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="Hotspot Traffic app icon">
</p>

<h1 align="center">Hotspot Traffic</h1>

<p align="center">轻量、原生的 macOS 外网流量监控 App</p>

Hotspot Traffic 使用 SwiftUI、系统自带的 `nettop` 和 SQLite，统计 Mac 的实时上下行、应用流量与历史趋势。它不需要 Node、Python、浏览器服务或第三方运行时。

## 功能

- 实时显示下载、上传和合计速度
- 菜单栏可自由组合图标、实时下载、实时上传和今日用量
- 作为菜单栏 App 后台运行，不占用程序坞位置
- 按今天、7 天、30 天或自定义日期查看历史
- 按应用统计流量，并单独展示 Shadowrocket、MacPacketTunnel、tun2socks 等隧道进程
- 前台 5 秒采样，后台自动降为 30 秒，历史数据分批写入
- 数据只保存在本机，不读取请求内容，也不上传到外部服务

## 下载

前往 [Releases](../../releases/latest) 下载 `HotspotTraffic-v1.1.1-macOS-arm64.zip`，解压后打开 `HotspotTraffic.app`。当前预编译版本适用于 Apple Silicon Mac；其他架构可以按下文从源码构建。

当前构建使用临时本地签名。macOS 首次提示来源时，在 Finder 中右键 App，选择“打开”。

## 统计范围

采集器监听 `nettop` 的 `external` 外部网络流量，包含普通应用和 VPN 隧道。在 Mac 通过手机热点联网时，这些外网流量就是热点消耗。

首帧是系统累计值，会被丢弃；后续只累计增量。隧道进程会单独展示，避免与应用层流量相加造成重复理解。

## 隐私

数据保存在：

```text
~/Library/Application Support/HotspotTraffic/traffic.sqlite3
```

数据库只记录时间、进程名、PID、接口和字节数。发布仓库和 Release 均不包含本机数据库或历史记录。

## 从源码构建

需要 macOS 13 或更高版本，以及 Swift 5.9 或完整 Xcode 工具链。

```bash
./scripts/build-app.sh
```

App 会生成到 `outputs/HotspotTraffic.app`。调试时也可以用 Xcode 打开 `Package.swift`，选择 `HotspotTrafficApp` 运行。

运行核心验证：

```bash
verify_dir="$(mktemp -d)"
swiftc -parse-as-library \
  Sources/HotspotTrafficApp/Models.swift \
  Sources/HotspotTrafficApp/NettopParser.swift \
  Sources/HotspotTrafficApp/TrafficStore.swift \
  scripts/verify-core.swift \
  -lsqlite3 \
  -o "$verify_dir/verify-core"
"$verify_dir/verify-core"
```

## 实现说明

采集器通过 `/usr/bin/script` 为 `nettop` 提供伪终端，并保持标准输入打开，避免后台空转占用 CPU。前台历史按 60 秒聚合，后台按 5 分钟聚合；无流量时每分钟写入一次心跳，历史页面仍会显示当天采样状态。

开源项目参考与许可证说明见 [REFERENCES.md](REFERENCES.md)。

## License

[MIT](LICENSE)
