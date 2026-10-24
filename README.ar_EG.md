<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

منفذ [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) إلى Bash. يبحث عن خوادم TLS المناسبة لاستخدامها كـ `dest` في Xray REALITY: ‏TLS 1.3 و ALPN `h2` وشهادة تحتوي على CN واسم المنظمة المُصدِرة. يتحقق السكربت أيضًا من DNS ويُميّز مواقع البروكسي التابعة لآخرين.

## التنزيل

يتطلب `bash` بإصدار 4.3 أو أحدث و `openssl` بإصدار 1.1.1 أو أحدث. يعمل على Linux و macOS (bash من Homebrew) و Git Bash على Windows.

```bash
curl -Ls -o RealiTLScanner.sh https://raw.githubusercontent.com/nekogs/RealiTLScanner-bash/main/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## الاستخدام

يُنصح بتشغيل الماسح محليًا: قد يؤدي تشغيله على VPS إلى وضع علامة على الخادم.

```bash
# عرض المساعدة
./RealiTLScanner.sh

# فحص عنوان IP أو CIDR أو نطاق:
./RealiTLScanner.sh -addr 1.2.3.4
# إذا كان addr عنوان IP أو نطاقًا، يُفعَّل الوضع اللانهائي تلقائيًا (ip، ip-1، ip+1، ... حتى Ctrl+C)

# فحص قائمة أهداف من ملف (هدف في كل سطر):
./RealiTLScanner.sh -in in.txt

# جمع النطاقات من رابط URL وفحصها:
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# المنفذ المراد فحصه، الافتراضي: 443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# إخراج مفصل يشمل عمليات الفحص الفاشلة والأهداف غير المناسبة:
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# حفظ النتائج في ملف، الافتراضي: out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# عدد الخيوط (threads)، الافتراضي: 2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# مهلة كل فحص، الافتراضي: 10 (ثوانٍ)
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# فحص عناوين IPv6 إلى جانب IPv4:
./RealiTLScanner.sh -in in.txt -46

# إيقاف فحص DNS لنطاق الشهادة (مُفعّل افتراضيًا):
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# طباعة السجلات بتنسيق RealiTLScanner الأصلي:
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### تفعيل GeoIP

لعرض دولة كل عنوان IP، ضع قاعدة بيانات MaxMind GeoLite2/GeoIP2 Country باسم `Country.mmdb` في المجلد الذي تشغّل منه السكربت. يمكنك تنزيلها من [هنا](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb). يتم البحث عبر `mmdblookup`، وإن لم يكن مثبتًا فعبر `python3`.

## دعم المؤلف

مؤلف هذا السكربت سجين رأي في روسيا. إذا كانت لديك إمكانية المساهمة بثمن بعض
النودلز سريعة التحضير، فسأكون ممتنًا!

|           | العنوان                                                              |
|-----------|----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## الترخيص

MIT
