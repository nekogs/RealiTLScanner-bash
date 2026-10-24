<p dir="auto"><a href="/README.md">English</a> | <a href="/README.fa.md">فارسی</a> | <a href="/README.ar_EG.md">العربية</a> | <a href="/README.zh.md">中文</a> | <a href="/README.es.md">Español</a> | <a href="/README.ru.md">Русский</a> | <a href="/README.tr_TR.md">Türkçe</a></p>

# RealiTLScanner — Bash

[XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) projesinin Bash portu. Xray REALITY için `dest` olarak uygun TLS sunucularını bulur: TLS 1.3, ALPN `h2` ve CN ile yayıncı kuruluş içeren bir sertifika. Betik ayrıca DNS kontrolü yapar ve başkalarına ait proxy sitelerini vurgular.

## İndirme

`bash` 4.3+ ve `openssl` 1.1.1+ gerekir. Linux, macOS (Homebrew bash) ve Windows üzerinde Git Bash ile çalışır.

```bash
curl -Ls -o RealiTLScanner.sh https://raw.githubusercontent.com/nekogs/RealiTLScanner-bash/main/RealiTLScanner.sh
chmod +x RealiTLScanner.sh
```

## Kullanım

Tarayıcıyı yerel olarak çalıştırmanız önerilir: bir VPS üzerinde çalıştırmak sunucunun işaretlenmesine yol açabilir.

```bash
# Yardımı göster
./RealiTLScanner.sh

# Bir IP, IP CIDR veya alan adını tara:
./RealiTLScanner.sh -addr 1.2.3.4
# Not: addr bir IP veya alan adıysa sonsuz mod otomatik olarak açılır (ip, ip-1, ip+1, ... Ctrl+C'ye kadar)

# Bir dosyadaki hedef listesini tara (her satırda bir hedef):
./RealiTLScanner.sh -in in.txt

# Bir URL'den alan adlarını topla ve tara:
./RealiTLScanner.sh -url https://launchpad.net/ubuntu/+archivemirrors

# Taranacak port, varsayılan: 443
./RealiTLScanner.sh -addr 1.1.1.1 -port 443

# Ayrıntılı çıktı, başarısız taramalar ve uygun olmayan hedefler dahil:
./RealiTLScanner.sh -addr 1.2.3.0/24 -v

# Sonuçları bir dosyaya kaydet, varsayılan: out.csv
./RealiTLScanner.sh -addr www.microsoft.com -out file.csv

# İş parçacığı (thread) sayısı, varsayılan: 2
./RealiTLScanner.sh -addr wiki.ubuntu.com -thread 10

# Her tarama için zaman aşımı, varsayılan: 10 (saniye)
./RealiTLScanner.sh -addr 107.172.1.1/16 -timeout 5

# IPv4'ün yanında IPv6 adreslerini de tara:
./RealiTLScanner.sh -in in.txt -46

# Sertifika alan adının DNS kontrolünü kapat (varsayılan olarak açık):
./RealiTLScanner.sh -addr 1.2.3.4 -check-dns=false

# Günlükleri orijinal RealiTLScanner biçiminde yazdır:
./RealiTLScanner.sh -addr 1.2.3.4 -raw
```

### GeoIP'yi etkinleştirme

Her IP'nin ülkesini görmek için `Country.mmdb` adlı bir MaxMind GeoLite2/GeoIP2 Country veritabanını betiği çalıştırdığınız klasöre koyun. [Buradan](https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb) indirebilirsiniz. Arama `mmdblookup` ile, yoksa `python3` ile yapılır.

## Yazara destek

Betiklerin yazarı Rusya'da siyasi bir mahkûmdur. Hazır erişteneye katkıda
bulunabilecekseniz minnettar olurum!

|           | Adres                                                                |
|-----------|----------------------------------------------------------------------|
| 💵 USDT (ERC-20) | `0x23c23dc5ed6888d9287da95cba454d4889241202` |
| ₿ BTC      | `bc1q7x2ez0atrtgq0qc5n3phszud0d3geuqvzhhhtu` |

## Lisans

MIT
