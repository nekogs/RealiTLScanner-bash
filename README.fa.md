<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

پورت [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) به Bash. سرورهای TLS مناسب برای `dest` در Xray REALITY را پیدا می‌کند: TLS 1.3، ALPN `h2` و گواهی‌ای که CN و سازمان صادرکننده دارد. اسکریپت DNS را هم بررسی می‌کند و سایت‌های پروکسی دیگران را مشخص می‌کند.

## دانلود

به `bash` نسخهٔ 4.3 به بالا و `openssl` نسخهٔ 1.1.1 به بالا نیاز دارد. روی Linux، macOS (bash از Homebrew) و Git Bash در ویندوز کار می‌کند.

```bash
curl -Ls -o RealiTLScanner.sh https://github.com/nekogs/RealiTLScanner-bash/releases/latest/download/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## کاربرد

بهتر است اسکنر را روی سیستم خودتان اجرا کنید: اجرای آن روی VPS ممکن است باعث علامت‌گذاری سرور شود.

```bash
# نمایش راهنما
./RealiTLScanner.sh

# اسکن یک IP، CIDR یا دامنه:
./RealiTLScanner.sh -addr 1.2.3.4
# اگر addr یک IP یا دامنه باشد، حالت بی‌پایان خودکار فعال می‌شود (ip، ip-1، ip+1، ... تا Ctrl+C)

# اسکن فهرست اهداف از یک فایل (هر خط یک هدف):
./RealiTLScanner.sh -in in.txt

# جمع‌آوری دامنه‌ها از یک URL و اسکن آن‌ها:
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# پورت برای بررسی، پیش‌فرض: 443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# خروجی مفصل، شامل اسکن‌های ناموفق و اهداف نامناسب:
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# ذخیرهٔ نتایج در فایل، پیش‌فرض: out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# تعداد رشته‌ها (thread)، پیش‌فرض: 2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# مهلت هر اسکن، پیش‌فرض: 10 (ثانیه)
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# اسکن آدرس‌های IPv6 در کنار IPv4:
./RealiTLScanner.sh -in in.txt -46

# خاموش کردن بررسی DNS دامنهٔ گواهی (به‌طور پیش‌فرض روشن است):
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# چاپ لاگ‌ها با قالب RealiTLScanner اصلی:
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### فعال‌سازی GeoIP

برای نمایش کشور هر IP، پایگاه دادهٔ MaxMind GeoLite2/GeoIP2 Country را با نام `Country.mmdb` در پوشه‌ای که اسکریپت را از آن اجرا می‌کنید قرار دهید. می‌توانید آن را از [اینجا](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb) دانلود کنید. جست‌وجو با `mmdblookup` انجام می‌شود و اگر نصب نباشد، با `python3`.

## حمایت از نویسنده

نویسندهٔ این اسکریپت یک زندانی سیاسی در روسیه است. اگر می‌توانید چیزی برای رامن بپردازید، سپاسگزار می‌شوم!

|           | آدرس                                                                  |
|-----------|-----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## مجوز

MIT
