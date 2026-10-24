<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

[XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) 的 Bash 移植版。用于查找适合作为 Xray REALITY `dest` 的 TLS 服务器：TLS 1.3、ALPN `h2`，且证书包含 CN 和签发者组织。脚本还会检查 DNS，并标出他人的代理站点。

## 下载

需要 `bash` 4.3+ 和 `openssl` 1.1.1+。可在 Linux、macOS（Homebrew 安装的 bash）以及 Windows 的 Git Bash 中运行。

```bash
curl -Ls -o RealiTLScanner.sh https://raw.githubusercontent.com/nekogs/RealiTLScanner-bash/main/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## 用法

建议在本地运行扫描器：在 VPS 上运行可能导致服务器被标记。

```bash
# 显示帮助
./RealiTLScanner.sh

# 扫描指定的 IP、IP CIDR 或域名：
./RealiTLScanner.sh -addr 1.2.3.4
# 注意：当 addr 为 IP 或域名时，会自动启用无限模式（ip、ip-1、ip+1……直到按下 Ctrl+C）

# 扫描文件中的目标列表（每行一个）：
./RealiTLScanner.sh -in in.txt

# 从 URL 抓取域名并扫描：
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# 指定要扫描的端口，默认：443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# 显示详细输出，包括失败的扫描和不合适的目标：
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# 将结果保存到文件，默认：out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# 设置线程数，默认：2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# 设置每次扫描的超时，默认：10（秒）
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# 同时扫描 IPv6 和 IPv4 地址：
./RealiTLScanner.sh -in in.txt -46

# 关闭证书域名的 DNS 检查（默认开启）：
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# 以原版 RealiTLScanner 的格式输出日志：
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### 启用 GeoIP

要显示每个 IP 的国家，请将名为 `Country.mmdb` 的 MaxMind GeoLite2/GeoIP2 Country 数据库放到运行脚本的文件夹中。可以从[这里](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb)下载。查询使用 `mmdblookup`，如未安装则使用 `python3`。

## 支持作者

脚本作者是俄罗斯的一名政治犯。如果您能赞助一些方便面，我将不胜感激！

|           | 地址                                                                 |
|-----------|-----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## 许可证

MIT
