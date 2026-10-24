<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

A port of [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) to Bash. It looks for TLS servers that suit Xray REALITY as `dest`: TLS 1.3, ALPN `h2`, and a certificate with a CN and an issuer organization. The script also checks DNS and highlights other people's proxy sites.

## Download

Needs `bash` 4.3+ and `openssl` 1.1.1+. Works on Linux, macOS (bash from Homebrew) and in Git Bash on Windows.

```bash
curl -Ls -o RealiTLScanner.sh https://raw.githubusercontent.com/nekogs/RealiTLScanner-bash/main/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## Usage

It is recommended to run the scanner locally: running it on a VPS may get the server flagged.

```bash
# Show help
./RealiTLScanner.sh

# Scan a specific IP, IP CIDR or domain:
./RealiTLScanner.sh -addr 1.2.3.4
# Note: infinite mode turns on automatically when `addr` is an IP or a domain (ip, ip-1, ip+1, ... until Ctrl+C)

# Scan a list of targets from a file (one per line):
./RealiTLScanner.sh -in in.txt

# Crawl domains from a URL and scan them:
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# Specify a port to scan, default: 443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# Show verbose output, including failed scans and unsuitable targets:
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# Save results to a file, default: out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# Set a thread count, default: 2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# Set a timeout for each scan, default: 10 (seconds)
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# Scan IPv6 addresses as well as IPv4:
./RealiTLScanner.sh -in in.txt -46

# Turn off the DNS check of the certificate domain (on by default):
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# Print logs in the format of the original RealiTLScanner:
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### Enable GeoIP

To show the country of each IP, put a MaxMind GeoLite2/GeoIP2 Country database named `Country.mmdb` into the folder you run the script from. You can download one [here](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb). Lookups use `mmdblookup` or, when it is missing, `python3`.

## Support the author

The script's author is a political prisoner in Russia. If you can spare something for
instant noodles, I'd be grateful!

|           | Address                                                                 |
|-----------|-----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## License

MIT
