<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

Порт [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) на Bash. Ищет TLS-серверы, которые подходят как `dest` для Xray REALITY: TLS 1.3, ALPN `h2`, в сертификате есть CN и организация издателя. Скрипт проверяет DNS и подсвечивает чужие прокси сайты.

## Скачать

Нужны `bash` 4.3+ и `openssl` 1.1.1+. Работает на Linux, macOS (bash из Homebrew) и в Git Bash на Windows.

```bash
curl -Ls -o RealiTLScanner.sh https://github.com/nekogs/RealiTLScanner-bash/releases/latest/download/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## Использование

Сканер лучше запускать локально: сканирование с VPS может привести к тому, что хостер пометит сервер.

```bash
# Показать справку
./RealiTLScanner.sh

# Сканировать IP, CIDR или домен:
./RealiTLScanner.sh -addr 1.2.3.4
# Если addr — это IP или домен, бесконечный режим включается сам (ip, ip-1, ip+1, ... до Ctrl+C)

# Сканировать список целей из файла (по одной на строку):
./RealiTLScanner.sh -in in.txt

# Собрать домены со страницы и просканировать их:
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# Порт для проверки, по умолчанию: 443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# Подробный вывод, включая неудачные проверки и неподходящие адреса:
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# Сохранить результат в файл, по умолчанию: out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# Число потоков, по умолчанию: 2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# Таймаут на одну проверку, по умолчанию: 10 (секунд)
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# Сканировать IPv6-адреса вместе с IPv4:
./RealiTLScanner.sh -in in.txt -46

# Отключить проверку DNS домена из сертификата (по умолчанию включена):
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# Печатать логи в формате оригинального RealiTLScanner:
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### GeoIP

Чтобы видеть страну каждого IP, положите базу MaxMind GeoLite2/GeoIP2 Country под именем `Country.mmdb` в папку, из которой запускаете скрипт. Скачать можно [здесь](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb). Поиск идёт через `mmdblookup`, а если его нет, через `python3`.

## Поддержать автора

Автор скрипта — политический заключённый в РФ. Если у вас есть возможность подкинуть
на дошик — буду благодарен!

|           | Адрес                                                                 |
|-----------|-----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## Лицензия

MIT
