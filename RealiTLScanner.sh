#!/usr/bin/env bash
# RealiTLScanner.sh - a Bash port of XTLS/RealiTLScanner
# (https://github.com/XTLS/RealiTLScanner).
#
# Scans IPs, CIDRs or domains for TLS servers that are good "dest" candidates
# for Xray REALITY: TLS 1.3 + ALPN h2 + a certificate with a CN and an issuer
# organization. Command line, logs and the CSV output match the Go original.
#
# Requirements: bash >= 4.3, openssl (>= 1.1.1; 3.5+ also offers X25519MLKEM768).
# Optional: curl or wget (for -url), getent/dig/host (DNS), timeout (coreutils),
#           mmdblookup or python3 (GeoIP via ./Country.mmdb).

if [ -z "${BASH_VERSION:-}" ]; then
	echo "This script requires bash >= 4.3" >&2
	exit 1
fi
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
	echo "This script requires bash >= 4.3 (found $BASH_VERSION)" >&2
	exit 1
fi

# ---------------------------------------------------------------- settings --

addr=""
in=""
port=443
thread=2
out="out.csv"
timeout=10
verbose=false
raw=false
checkdns=true
PRETTY=false
LIVE=false
enableIPv6=false
url=""

PROG=$0

# ----------------------------------------------------------------- logging --
# Mimics Go's log/slog TextHandler:  time=... level=INFO msg="..." key=value

# Sets REPLY to the current time in RFC 3339 with milliseconds (as slog does).
now_rfc3339() {
	local t=${EPOCHREALTIME:-} s us tz
	if [[ -n $t ]]; then
		s=${t%[.,]*}
		us=${t#*[.,]}
		printf -v REPLY '%(%Y-%m-%dT%H:%M:%S)T' "$s"
		printf -v tz '%(%z)T' "$s"
		REPLY+=".${us:0:3}"
	else
		REPLY=$(date +%Y-%m-%dT%H:%M:%S)
		tz=$(date +%z)
		local ns
		ns=$(date +%N 2>/dev/null)
		[[ $ns =~ ^[0-9]{9}$ ]] || ns=000000000
		REPLY+=".${ns:0:3}"
	fi
	if [[ $tz == "+0000" || $tz == "-0000" ]]; then
		REPLY+="Z"
	else
		REPLY+="${tz:0:3}:${tz:3:2}"
	fi
}

# Sets REPLY to $1 quoted the way slog's TextHandler quotes values.
slog_quote() {
	local v=$1
	if [[ -z $v || $v == *[[:space:]=\"]* || $v == *[[:cntrl:]]* ]]; then
		v=${v//\\/\\\\}
		v=${v//\"/\\\"}
		v=${v//$'\n'/\\n}
		v=${v//$'\r'/\\r}
		v=${v//$'\t'/\\t}
		REPLY="\"$v\""
	else
		REPLY=$v
	fi
}

# log LEVEL MSG [KEY VALUE]...
log() {
	local level=$1 msg=$2 line
	shift 2
	[[ $level == DEBUG && $verbose != true ]] && return 0
	if [[ $PRETTY == true ]]; then
		pretty_log "$level" "$msg" "$@"
		return 0
	fi
	now_rfc3339
	line="time=$REPLY level=$level"
	slog_quote "$msg"
	line+=" msg=$REPLY"
	while (($# >= 2)); do
		slog_quote "$2"
		line+=" $1=$REPLY"
		shift 2
	done
	# one write per line, so lines from parallel workers never interleave
	printf '%s\n' "$line" >&3
}

# ------------------------------------------------------------ pretty output
# Human-friendly rendering of the same events, used on a terminal unless -raw.

C_RESET="" C_DIM="" C_BOLD="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN=""
G_OK="+" G_SKIP="-" G_FAIL="x" G_DOT="|" G_ELL="~" G_PROXY="!" G_ARROW="->"

pretty_init() {
	local utf8=$1
	if [[ -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
		C_RESET=$'\e[0m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m'
		C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RED=$'\e[31m' C_CYAN=$'\e[36m'
	fi
	if [[ $utf8 == true ]]; then
		G_OK="✔" G_SKIP="·" G_FAIL="✗" G_DOT="·" G_ELL="…" G_PROXY="↪" G_ARROW="→"
	fi
}

# fit TEXT WIDTH -> REPLY: cut to WIDTH and pad with spaces
fit() {
	local t=$1 w=$2
	if ((${#t} > w)); then
		REPLY="${t:0:w-1}$G_ELL"
	else
		printf -v REPLY '%-*s' "$w" "$t"
	fi
}

pretty_log() {
	local level=$1 msg=$2 line=""
	shift 2
	local -A a=()
	while (($# >= 2)); do
		a[$1]=$2
		shift 2
	done
	case $msg in
	"Connected to target")
		local ip=${a[ip]} origin="" extra=""
		[[ ${a[origin]} != "$ip" && ${a[origin]} != */* ]] && origin=${a[origin]}
		fit "$ip" 15
		ip=$REPLY
		if [[ ${a[feasible]} == true && ${a[dns]:-ok} != ok ]]; then
			# suitable by TLS, but the certificate's domain lives elsewhere:
			# this IP only relays someone else's site (a proxy / REALITY server)
			[[ -n ${RTS_TMP:-} ]] && printf . >>"$RTS_TMP/proxy"
			fit "${a[cert-domain]}" 30
			local dom=$REPLY
			fit "${a[cert-issuer]}" 24
			local iss=$REPLY
			fit "${a[alpn]}" 4
			local alpn=$REPLY
			fit "${a[curve]}" 14
			local geo where="$G_ARROW ${a[dns]#proxy:}"
			[[ ${a[dns]} == proxy: ]] && where="(domain does not resolve)"
			printf -v geo '%-4s' "${a[geo]}"
			[[ -n $origin ]] && extra=" ${C_DIM}($origin)${C_RESET}"
			line="  ${C_YELLOW}${G_PROXY}${C_RESET} ${C_BOLD}$ip${C_RESET}  ${C_YELLOW}$dom${C_RESET}  $iss  ${a[tls]}  $alpn  $REPLY  $geo  ${C_YELLOW}proxy-site${C_RESET} ${C_DIM}$where${C_RESET}$extra"
		elif [[ ${a[feasible]} == true ]]; then
			[[ -n ${RTS_TMP:-} ]] && printf . >>"$RTS_TMP/found"
			local geo=${a[geo]}
			[[ -n ${a[dns]:-} ]] && printf -v geo '%-4s  %s' "${a[geo]}" "${C_GREEN}matches IP${C_RESET}"
			fit "${a[cert-domain]}" 30
			local dom=$REPLY
			fit "${a[cert-issuer]}" 24
			local iss=$REPLY
			fit "${a[alpn]}" 4
			local alpn=$REPLY
			fit "${a[curve]}" 14
			[[ -n $origin ]] && extra=" ${C_DIM}($origin)${C_RESET}"
			line="  ${C_GREEN}${G_OK}${C_RESET} ${C_BOLD}$ip${C_RESET}  ${C_GREEN}${C_BOLD}$dom${C_RESET}  $iss  ${a[tls]}  $alpn  $REPLY  $geo$extra"
		else
			local why
			if [[ ${a[tls]} != "TLS 1.3" ]]; then why=${a[tls]}
			elif [[ ${a[alpn]} != h2 ]]; then why="ALPN ${a[alpn]:-none}"
			elif [[ -z ${a[cert-domain]} ]]; then why="no CN in certificate"
			else why="no issuer organization"
			fi
			fit "${a[cert-domain]}" 30
			[[ -n $origin ]] && extra=" ($origin)"
			line="  ${C_DIM}${G_SKIP} $ip  $REPLY  not suitable: $why$extra${C_RESET}"
		fi
		;;
	"Cannot dial" | "TLS handshake failed")
		fit "${a[target]}" 21
		local what="no TCP connection"
		[[ $msg == "TLS handshake failed" ]] && what="TLS handshake failed"
		line="  ${C_DIM}${G_FAIL} $REPLY  $what${C_RESET}"
		;;
	"Failed to get IP from the origin")
		fit "${a[origin]}" 21
		line="  ${C_DIM}${G_FAIL} $REPLY  DNS lookup failed${C_RESET}"
		;;
	"Error reading geo") return ;;
	"Enable infinite mode")
		line="${C_DIM}Infinite mode: walking outward from ${a[init]}, press Ctrl+C to stop${C_RESET}"
		;;
	"Enabled GeoIP") line="${C_DIM}GeoIP: on${C_RESET}" ;;
	"Cannot open Country.mmdb") line="${C_DIM}GeoIP: off (${a[err]})${C_RESET}" ;;
	"Fetching url...") line="Fetching $url ..." ;;
	"Not a valid IP, IP CIDR or domain")
		line="${C_YELLOW}Skipped \"${a[line]:-${a[addr]}}\": not an IP, CIDR or domain${C_RESET}"
		[[ $level == ERROR ]] && line="${C_RED}Error: \"${a[addr]}\" is not an IP, CIDR or resolvable domain${C_RESET}"
		;;
	"Invalid cidr") line="${C_YELLOW}Skipped \"${a[cidr]}\": invalid CIDR prefix${C_RESET}" ;;
	"Parsed domains") line="Found ${a[count]} domains on the page" ;;
	"Started all scanning threads")
		local target="-addr $addr"
		[[ -n $in ]] && target="-in $in"
		[[ -n $url ]] && target="-url $url"
		local dnsinfo="DNS check: on"
		[[ $checkdns != true ]] && dnsinfo="DNS check: off"
		line="${C_CYAN}${C_BOLD}RealiTLScanner${C_RESET} $G_DOT $target $G_DOT port $port $G_DOT $thread threads $G_DOT timeout ${timeout}s $G_DOT $dnsinfo $G_DOT CSV: ${out:-off}"$'\n'
		fit IP 15
		local h1=$REPLY
		fit "CERT DOMAIN" 30
		local h2=$REPLY
		fit ISSUER 24
		local h3=$REPLY
		fit CURVE 14
		line+="${C_DIM}    $h1  $h2  $h3  TLS      ALPN  $REPLY  GEO"
		[[ $checkdns == true ]] && line+="   DNS CHECK"
		line+=$C_RESET
		;;
	"Scanning completed" | "Scanning stopped")
		local found=0 checked=0 proxies=0
		[[ -f ${RTS_TMP:-}/found ]] && found=$(wc -c <"$RTS_TMP/found")
		[[ -f ${RTS_TMP:-}/proxy ]] && proxies=$(wc -c <"$RTS_TMP/proxy")
		[[ -f ${RTS_TMP:-}/checked ]] && checked=$(wc -c <"$RTS_TMP/checked")
		local head="Done"
		[[ $msg == "Scanning stopped" ]] && head="Stopped"
		line=$'\n'"${C_BOLD}$head${C_RESET} in ${a[elapsed]} $G_DOT checked $((checked)) $G_DOT ${C_GREEN}${C_BOLD}suitable $((found))${C_RESET}"
		[[ $checkdns == true ]] && line+=" $G_DOT ${C_YELLOW}proxy-site $((proxies))${C_RESET}"
		[[ -n $out && $((found + proxies)) -gt 0 ]] && line+=" $G_DOT saved to $out"
		;;
	*)
		local color=$C_DIM tag=""
		[[ $level == WARN ]] && color=$C_YELLOW tag="Warning: "
		[[ $level == ERROR ]] && color=$C_RED tag="Error: "
		[[ $msg == "You must specify and only specify one of"* ]] && msg="specify exactly one of -addr, -in or -url"
		line="${color}${tag}${msg}"
		local k
		for k in "${!a[@]}"; do line+=" ${k}: ${a[$k]}"; done
		line+=$C_RESET
		;;
	esac
	# wipe the live status line first; the ticker draws it again below
	[[ $LIVE == true ]] && line=$'\r\e[K'$line
	printf '%s\n' "$line" >&3
}

# Live status line under the table, redrawn in place while the scan runs, so
# that a long stretch without results does not look like a hang.
status_ticker() {
	trap '' INT
	trap 'exit 0' TERM
	local i=0 checked found proxies cur el line
	local -a frames=('|' '/' '-' '\')
	while :; do
		checked=0 found=0 proxies=0 cur=""
		[[ -f $RTS_TMP/checked ]] && checked=$(wc -c <"$RTS_TMP/checked")
		[[ -f $RTS_TMP/found ]] && found=$(wc -c <"$RTS_TMP/found")
		[[ -f $RTS_TMP/proxy ]] && proxies=$(wc -c <"$RTS_TMP/proxy")
		[[ -f $RTS_TMP/current ]] && cur=$(<"$RTS_TMP/current")
		el=$SECONDS
		if ((el >= 3600)); then el="$((el / 3600))h$((el % 3600 / 60))m$((el % 60))s"
		elif ((el >= 60)); then el="$((el / 60))m$((el % 60))s"
		else el="${el}s"
		fi
		line="  ${C_CYAN}${frames[i++ % ${#frames[@]}]}${C_RESET} ${C_DIM}scanning $G_DOT checked $((checked)) $G_DOT${C_RESET} ${C_GREEN}suitable $((found))${C_RESET}"
		[[ $checkdns == true ]] && line+=" ${C_DIM}$G_DOT${C_RESET} ${C_YELLOW}proxy-site $((proxies))${C_RESET}"
		line+=" ${C_DIM}$G_DOT $el"
		[[ -n $cur ]] && line+=" $G_DOT now $cur"
		printf '\r\e[K%s' "$line$C_RESET" >&3
		sleep 0.5 2>/dev/null || sleep 1
	done
}

# Formats a duration given in microseconds like Go's time.Duration.String().
go_duration() {
	local us=$1 ns frac h m s out=""
	ns=$((us * 1000))
	if ((ns == 0)); then
		REPLY="0s"
		return
	fi
	if ((ns < 1000000000)); then
		if ((ns < 1000)); then
			REPLY="${ns}ns"
		elif ((ns < 1000000)); then
			frac=$(printf '%03d' $((ns % 1000)))
			frac=${frac%%+(0)}
			REPLY="$((ns / 1000))${frac:+.$frac}µs"
		else
			frac=$(printf '%06d' $((ns % 1000000)))
			frac=${frac%%+(0)}
			REPLY="$((ns / 1000000))${frac:+.$frac}ms"
		fi
		return
	fi
	s=$((ns / 1000000000))
	frac=$(printf '%09d' $((ns % 1000000000)))
	frac=${frac%%+(0)}
	h=$((s / 3600))
	m=$((s % 3600 / 60))
	s=$((s % 60))
	((h > 0)) && out+="${h}h"
	((h > 0 || m > 0)) && out+="${m}m"
	REPLY="${out}${s}${frac:+.$frac}s"
}

now_us() {
	local t=${EPOCHREALTIME:-}
	if [[ -n $t ]]; then
		REPLY="${t%[.,]*}${t#*[.,]}"
	else
		local ns
		ns=$(date +%s%N 2>/dev/null)
		[[ $ns =~ ^[0-9]+$ && ${#ns} -gt 12 ]] || ns="$(date +%s)000000000"
		REPLY=${ns:0:${#ns}-3}
	fi
	REPLY=$((10#$REPLY))
}

# ------------------------------------------------------------------- flags --
# Mimics Go's flag package: -name value, -name=value, --name, bool flags.

print_defaults() {
	cat >&2 <<'EOF'
  -46
    	Enable IPv6 in additional to IPv4
  -addr string
    	Specify an IP, IP CIDR or domain to scan
  -check-dns
    	Resolve the certificate domain and mark the result as proxy-site when it does not point to the scanned IP or its /24 (terminal output only) (default true)
  -in string
    	Specify a file that contains multiple IPs, IP CIDRs or domains to scan, divided by line break
  -out string
    	Output file to store the result (default "out.csv")
  -port int
    	Specify a HTTPS port to check (default 443)
  -raw
    	Print logs in the original RealiTLScanner format (always used when the output is not a terminal)
  -thread int
    	Count of concurrent tasks (default 2)
  -timeout int
    	Timeout for every check (default 10)
  -url string
    	Crawl the domain list from a URL, e.g. https://launchpad.net/ubuntu/+archivemirrors
  -v	Verbose output
EOF
}

usage() {
	printf 'Usage of %s:\n' "$PROG" >&2
	print_defaults
}

flag_fail() {
	printf '%s\n' "$1" >&2
	usage
	exit 2
}

# Go's strconv.ParseBool
parse_bool() {
	case $1 in
	1 | t | T | TRUE | true | True) REPLY=true ;;
	0 | f | F | FALSE | false | False) REPLY=false ;;
	*) return 1 ;;
	esac
}

# Go's strconv.ParseInt(s, 0, 64): decimal, 0x.., 0o.., 0b.., 0.. (octal), "_" separators.
# Returns 1 on syntax error, 2 when out of range.
parse_int() {
	local s=$1 sign="" body digits base
	[[ $s == [+-]* ]] && sign=${s:0:1} && s=${s:1}
	case $s in
	0[xX]*) base=16 body=${s:2} ;;
	0[oO]*) base=8 body=${s:2} ;;
	0[bB]*) base=2 body=${s:2} ;;
	0?*) base=8 body=${s:1} ;;
	*) base=10 body=$s ;;
	esac
	case $base in
	16) [[ $body =~ ^_?[0-9a-fA-F]+(_[0-9a-fA-F]+)*$ ]] || return 1 ;;
	8) [[ $body =~ ^_?[0-7]+(_[0-7]+)*$ ]] || return 1 ;;
	2) [[ $body =~ ^_?[01]+(_[01]+)*$ ]] || return 1 ;;
	10) [[ $body =~ ^[0-9]+(_[0-9]+)*$ ]] || return 1 ;;
	esac
	digits=${body//_/}
	digits=${digits##+(0)}
	[[ -z $digits ]] && digits=0
	digits=${digits,,}
	# reject anything that does not fit into int64 (the smallest value is -2^63)
	local max min
	case $base in
	16) max=7fffffffffffffff min=8000000000000000 ;;
	8) max=777777777777777777777 min=1000000000000000000000 ;;
	2) max=$(printf '1%.0s' {1..63}) min=1$(printf '0%.0s' {1..63}) ;;
	10) max=9223372036854775807 min=9223372036854775808 ;;
	esac
	# shellcheck disable=SC2071 # equal-length digit strings compare lexically
	if ((${#digits} > ${#max})) || [[ ${#digits} -eq ${#max} && $digits > $max ]]; then
		[[ $sign == - && $digits == "$min" ]] || return 2
	fi
	REPLY=$((${sign}${base}#${digits}))
}

parse_flags() {
	local a name val has_val
	while (($#)); do
		a=$1
		[[ ${#a} -lt 2 || ${a:0:1} != - ]] && break
		name=${a:1}
		if [[ ${name:0:1} == - ]]; then
			name=${name:1}
			if [[ -z $name ]]; then # "--" terminates the flags
				shift
				break
			fi
		fi
		if [[ -z $name || ${name:0:1} == - || ${name:0:1} == = ]]; then
			flag_fail "bad flag syntax: $a"
		fi
		shift
		has_val=false
		val=""
		if [[ $name == *=* ]]; then
			val=${name#*=}
			name=${name%%=*}
			has_val=true
		fi
		case $name in
		v | 46 | raw | check-dns)
			if [[ $has_val == true ]]; then
				parse_bool "$val" || flag_fail "invalid boolean value \"$val\" for -$name: parse error"
			else
				REPLY=true
			fi
			case $name in v) verbose=$REPLY ;; 46) enableIPv6=$REPLY ;; raw) raw=$REPLY ;; check-dns) checkdns=$REPLY ;; esac
			;;
		addr | in | out | url | port | thread | timeout)
			if [[ $has_val != true ]]; then
				(($#)) || flag_fail "flag needs an argument: -$name"
				val=$1
				shift
			fi
			case $name in
			addr) addr=$val ;;
			in) in=$val ;;
			out) out=$val ;;
			url) url=$val ;;
			*)
				parse_int "$val"
				case $? in
				1) flag_fail "invalid value \"$val\" for flag -$name: parse error" ;;
				2) flag_fail "invalid value \"$val\" for flag -$name: value out of range" ;;
				esac
				printf -v "$name" '%s' "$REPLY"
				;;
			esac
			;;
		help | h)
			usage
			exit 0
			;;
		*) flag_fail "flag provided but not defined: -$name" ;;
		esac
	done
}

# ------------------------------------------------------------ IP addresses --
# An address is kept as 8 16-bit groups (like Go's 16-byte net.IP); IPv4 is
# stored IPv4-mapped (::ffff:a.b.c.d), exactly as net.ParseIP does.

# parse_ipv4 STR -> IP4 (32-bit integer); follows net.ParseIP (no leading zeros)
parse_ipv4() {
	local s=$1 o
	local -a oct
	# plain globs instead of =~, which is not reliable in every bash build
	[[ $s == *.*.*.* && $s != *.*.*.*.* && $s != *[!0-9.]* ]] || return 1
	IFS=. read -r -a oct <<<"$s"
	((${#oct[@]} == 4)) || return 1
	IP4=0
	for o in "${oct[@]}"; do
		[[ -n $o && ${#o} -le 3 ]] || return 1
		[[ ${#o} -gt 1 && $o == 0* ]] && return 1
		((10#$o > 255)) && return 1
		IP4=$((IP4 << 8 | 10#$o))
	done
	return 0
}

# parse_ip STR -> IPH (array of 8 groups). Same rules as Go's net.ParseIP.
parse_ip() {
	local s=$1 head tail i n
	local -a hg=() tg=() parts
	IPH=()
	if [[ $s != *:* ]]; then
		parse_ipv4 "$s" || return 1
		IPH=(0 0 0 0 0 65535 $((IP4 >> 16)) $((IP4 & 65535)))
		return 0
	fi
	[[ $s == *%* ]] && return 1
	# trailing embedded IPv4
	local v4=""
	if [[ $s =~ ^(.*:)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
		s=${BASH_REMATCH[1]}
		v4=${BASH_REMATCH[2]}
		parse_ipv4 "$v4" || return 1
		[[ $s == *:: ]] || s=${s%:}
		[[ -z $s ]] && return 1
	fi
	if [[ $s == *::* ]]; then
		head=${s%%::*}
		tail=${s#*::}
		[[ $tail == *::* ]] && return 1
	else
		head=$s
		tail=""
	fi
	parse_groups() { # $1 string, $2 array name
		local str=$1 g
		local -n arr=$2
		arr=()
		[[ -z $str ]] && return 0
		[[ $str == :* || $str == *: ]] && return 1
		IFS=: read -ra parts <<<"$str"
		for g in "${parts[@]}"; do
			[[ $g =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
			arr+=($((16#$g)))
		done
	}
	parse_groups "$head" hg || return 1
	parse_groups "$tail" tg || return 1
	local want=8
	[[ -n $v4 ]] && want=6
	if [[ $s == *::* ]]; then
		n=$((want - ${#hg[@]} - ${#tg[@]}))
		((n < 1)) && return 1
		IPH=("${hg[@]}")
		for ((i = 0; i < n; i++)); do IPH+=(0); done
		IPH+=("${tg[@]}")
	else
		IPH=("${hg[@]}")
	fi
	((${#IPH[@]} == want)) || return 1
	[[ -n $v4 ]] && IPH+=($((IP4 >> 16)) $((IP4 & 65535)))
	return 0
}

# is_v4 GROUPS... -> true when Go's ip.To4() != nil
is_v4() {
	(($1 == 0 && $2 == 0 && $3 == 0 && $4 == 0 && $5 == 0 && $6 == 65535))
}

# format_ip GROUPS... -> REPLY; same output as Go's net.IP.String()
format_ip() {
	if is_v4 "$@"; then
		REPLY="$(($7 >> 8)).$(($7 & 255)).$(($8 >> 8)).$(($8 & 255))"
		return
	fi
	local -a g=("$@")
	local i best=-1 bestlen=0 cur=-1 curlen=0 hex
	for ((i = 0; i < 8; i++)); do
		if ((g[i] == 0)); then
			((cur < 0)) && cur=$i curlen=0
			((curlen++))
			if ((curlen > bestlen)); then best=$cur bestlen=$curlen; fi
		else
			cur=-1
		fi
	done
	((bestlen < 2)) && best=-1
	REPLY=""
	for ((i = 0; i < 8; i++)); do
		if ((i == best)); then
			REPLY+="::"
			((i += bestlen - 1))
			continue
		fi
		[[ -n $REPLY && $REPLY != *:: ]] && REPLY+=":"
		printf -v hex '%x' "${g[i]}"
		REPLY+=$hex
	done
}

# ---------------------------------------------------------- target sources --
# Targets are emitted as NUL-terminated records "TYPE<TAB>IP<TAB>ORIGIN",
# TYPE being ip, cidr or domain (domains are resolved by the worker).

emit() { printf '%s\t%s\t%s\0' "$1" "$2" "$3"; }

# is_cidr STR -> CIDR_IP (IPH), CIDR_BITS, CIDR_IS4 (dotted IPv4 form) ;
# follows net.ParseCIDR. Sets CIDR_BAD to the netip.ParsePrefix error, if any.
is_cidr() {
	local s=$1 a b
	[[ $s == */* ]] || return 1
	a=${s%%/*}
	b=${s#*/}
	parse_ip "$a" || return 1
	[[ $b =~ ^[0-9]+$ ]] || return 1
	CIDR_IS4=false
	[[ $a != *:* ]] && CIDR_IS4=true
	local max=128
	[[ $CIDR_IS4 == true ]] && max=32
	((${#b} > 3 || 10#$b > max)) && return 1
	CIDR_BITS=$((10#$b))
	CIDR_IP=("${IPH[@]}")
	CIDR_BAD=""
	if [[ ${#b} -gt 1 && $b == 0* ]]; then
		CIDR_BAD="netip.ParsePrefix(\"$s\"): bad bits after slash: \"$b\""
	fi
	return 0
}

# Every address of a CIDR, like the netip.Prefix loop in Go's Iterate().
emit_cidr() {
	local line=$1 i
	if [[ $CIDR_IS4 == true ]]; then
		local v=$(((CIDR_IP[6] << 16) | CIDR_IP[7])) n
		n=$((1 << (32 - CIDR_BITS)))
		v=$((v & ~(n - 1) & 0xffffffff))
		for ((i = 0; i < n; i++)); do
			emit cidr "$(((v >> 24) & 255)).$(((v >> 16) & 255)).$(((v >> 8) & 255)).$((v & 255))" "$line"
			((v++))
		done
		return
	fi
	# IPv6 prefix (IPv4-mapped included)
	local -a g=("${CIDR_IP[@]}") net
	local bits=$CIDR_BITS mask
	for ((i = 0; i < 8; i++)); do
		if ((bits >= 16)); then
			mask=65535
		elif ((bits <= 0)); then
			mask=0
		else
			mask=$(((65535 << (16 - bits)) & 65535))
		fi
		((bits -= 16))
		g[i]=$((g[i] & mask))
	done
	net=("${g[@]}")
	local fixed=$((CIDR_BITS / 16)) part=$((CIDR_BITS % 16))
	while :; do
		format_ip "${g[@]}"
		emit cidr "$REPLY" "$line"
		# increment, stop when the address leaves the prefix
		for ((i = 7; i >= 0; i--)); do
			g[i]=$(((g[i] + 1) & 65535))
			((g[i] != 0)) && break
		done
		((i < 0)) && return
		for ((i = 0; i < fixed; i++)); do
			((g[i] != net[i])) && return
		done
		if ((part > 0)); then
			mask=$(((65535 << (16 - part)) & 65535))
			(((g[fixed] & mask) != net[fixed])) && return
		fi
	done
}

# Go's ValidateDomainName
valid_domain() { [[ $1 =~ ^[A-Za-z0-9.-]+$ ]]; }

# Go's Iterate(): one target per line from stdin.
iterate() {
	local line
	while IFS= read -r line || [[ -n $line ]]; do
		line=${line#"${line%%[![:space:]]*}"}
		line=${line%"${line##*[![:space:]]}"}
		[[ -z $line ]] && continue
		if parse_ip "$line" && { is_v4 "${IPH[@]}" || [[ $enableIPv6 == true ]]; }; then
			format_ip "${IPH[@]}"
			emit ip "$REPLY" "$line"
			continue
		fi
		if is_cidr "$line"; then
			if [[ -n $CIDR_BAD ]]; then
				log WARN "Invalid cidr" cidr "$line" err "$CIDR_BAD"
				continue
			fi
			[[ $CIDR_IS4 != true && $enableIPv6 != true ]] && continue
			emit_cidr "$line"
			continue
		fi
		if valid_domain "$line"; then
			emit domain - "$line"
			continue
		fi
		log WARN "Not a valid IP, IP CIDR or domain" line "$line"
	done
}

# Go's IterateAddr() infinite mode: ip, ip-1, ip+1, ip-2, ip+2, ...
iterate_infinite() {
	local origin=$1 i
	local -a low=("${@:2}") high=("${@:2}")
	format_ip "${low[@]}"
	log INFO "Enable infinite mode" init "$REPLY"
	emit ip "$REPLY" "$origin"
	local high_ok=true
	while :; do
		for ((i = 7; i >= 0; i--)); do
			low[i]=$(((low[i] - 1) & 65535))
			((low[i] != 65535)) && break
		done
		# below "::" Go's big.Int arithmetic yields ::1 again (abs(-1))
		((i < 0)) && low=(0 0 0 0 0 0 0 1)
		format_ip "${low[@]}"
		emit ip "$REPLY" "$REPLY"
		# above ffff:...:ffff Go panics; here only the upward half stops
		[[ $high_ok == true ]] || continue
		for ((i = 7; i >= 0; i--)); do
			high[i]=$(((high[i] + 1) & 65535))
			((high[i] != 0)) && break
		done
		if ((i < 0)); then
			high_ok=false
			continue
		fi
		format_ip "${high[@]}"
		emit ip "$REPLY" "$REPLY"
	done
}

# ---------------------------------------------------------------------- DNS --

# lookup_ip NAME -> REPLY = first address (IPv4 only unless -46), like Go's LookupIP
lookup_ip() {
	local name=$1 list="" a ns=""
	LOOKUP_ERR=""
	if [[ -r /etc/resolv.conf ]]; then
		ns=$(awk '$1=="nameserver"{print $2; exit}' /etc/resolv.conf 2>/dev/null)
		[[ $ns == *:* ]] && ns="[$ns]"
		[[ -n $ns ]] && ns=" on $ns:53"
	fi
	# Go refuses names with an all-numeric last label ("01.2.3.4", "127.1"),
	# while getaddrinfo would accept inet_aton() forms like these.
	local last=${name%.}
	last=${last##*.}
	if [[ $last =~ ^[0-9]+$ ]]; then
		LOOKUP_ERR="failed to lookup: lookup $name: no such host"
		return 1
	fi
	if command -v getent >/dev/null 2>&1; then
		if [[ $enableIPv6 == true ]]; then
			list=$(getent ahosts "$name" 2>/dev/null | awk '$2=="STREAM"{print $1}')
		else
			list=$(getent ahostsv4 "$name" 2>/dev/null | awk '$2=="STREAM"{print $1}')
		fi
	elif command -v dig >/dev/null 2>&1; then
		list=$(dig +short +search A "$name" 2>/dev/null)
		[[ $enableIPv6 == true ]] && list+=$'\n'$(dig +short +search AAAA "$name" 2>/dev/null)
	elif command -v host >/dev/null 2>&1; then
		list=$(host "$name" 2>/dev/null | awk '/has (IPv6 )?address/{print $NF}')
	elif command -v nslookup >/dev/null 2>&1; then
		# e.g. Git Bash on Windows; the answer follows the server block, and
		# the labels may be localized, so just take every address after it
		list=$(nslookup "$name" 2>/dev/null | tr -d '\r' |
			awk 'seen{for(i=1;i<=NF;i++) if($i ~ /^[0-9a-fA-F.:]+$/ && $i ~ /[.:]/) print $i} /^[ \t]*$/{seen=1}')
	else
		LOOKUP_ERR="failed to lookup: no resolver tool found (getent, dig, host or nslookup)"
		return 1
	fi
	while IFS= read -r a; do
		parse_ip "$a" || continue
		if is_v4 "${IPH[@]}" || [[ $enableIPv6 == true ]]; then
			LOOKUP_IPH=("${IPH[@]}")
			format_ip "${IPH[@]}"
			return 0
		fi
	done <<<"$list"
	if [[ -z ${list//[[:space:]]/} ]]; then
		LOOKUP_ERR="failed to lookup: lookup $name$ns: no such host"
	else
		LOOKUP_ERR="no IP found"
	fi
	return 1
}

# resolve_all NAME -> REPLY = every address of NAME (IPv4 and IPv6), one per line
resolve_all() {
	local name=$1
	REPLY=""
	if command -v getent >/dev/null 2>&1; then
		REPLY=$(getent ahosts "$name" 2>/dev/null | awk '$2=="STREAM"{print $1}')
	elif command -v dig >/dev/null 2>&1; then
		REPLY=$(dig +short A "$name" 2>/dev/null)$'\n'$(dig +short AAAA "$name" 2>/dev/null)
	elif command -v host >/dev/null 2>&1; then
		REPLY=$(host "$name" 2>/dev/null | awk '/has (IPv6 )?address/{print $NF}')
	elif command -v nslookup >/dev/null 2>&1; then
		REPLY=$(nslookup "$name" 2>/dev/null | tr -d '\r' |
			awk 'seen{for(i=1;i<=NF;i++) if($i ~ /^[0-9a-fA-F.:]+$/ && $i ~ /[.:]/) print $i} /^[ \t]*$/{seen=1}')
	fi
}

# dns_check DOMAIN IP ORIGIN -> REPLY = "ok", or "proxy:FIRST_ADDRESS" when the
# certificate's domain resolves somewhere else ("proxy:" when it does not
# resolve). The domain counts as hosted here when one of its addresses is the
# scanned IP or sits in the same /24 (IPv4) or /48 (IPv6). Answers are cached
# in $RTS_TMP, shared by all workers.
dns_check() {
	local domain=${1#\*.} ip=$2 origin=$3 list key a first=""
	domain=${domain%.}
	if [[ ${domain,,} == "${origin,,}" ]]; then # we got here by resolving it
		REPLY=ok
		return
	fi
	key=${domain//[^A-Za-z0-9.-]/_}
	if [[ -f $RTS_TMP/dns_$key ]]; then
		list=$(<"$RTS_TMP/dns_$key")
	elif parse_ip "$domain"; then
		list=$domain
	else
		resolve_all "$domain"
		list=$REPLY
		# a wildcard certificate (*.example.com): try the bare domain, then www
		if [[ -z ${list//[[:space:]]/} && $1 == \*.* ]]; then
			resolve_all "www.$domain"
			list=$REPLY
		fi
		printf '%s\n' "$list" >"$RTS_TMP/dns_$key" 2>/dev/null
	fi
	parse_ip "$ip" || { REPLY=ok; return; }
	local -a s=("${IPH[@]}")
	while IFS= read -r a; do
		[[ -n $a ]] || continue
		parse_ip "$a" || continue
		[[ -z $first ]] && first=$a
		if is_v4 "${s[@]}"; then
			is_v4 "${IPH[@]}" || continue
			if ((IPH[6] == s[6] && IPH[7] >> 8 == s[7] >> 8)); then REPLY=ok; return; fi
		elif ((IPH[0] == s[0] && IPH[1] == s[1] && IPH[2] == s[2])) && ! is_v4 "${IPH[@]}"; then
			REPLY=ok
			return
		fi
	done <<<"$list"
	REPLY="proxy:$first"
}

# --------------------------------------------------------------------- GeoIP --

GEO_MODE=none
PY_CMD=()

# A working Python 3: python3, python or the Windows launcher "py -3"
# (the Microsoft Store stub is rejected by the version check).
find_python() {
	local -a c
	for c in python3 python "py -3"; do
		read -r -a c <<<"$c"
		command -v "${c[0]}" >/dev/null 2>&1 || continue
		if "${c[@]}" -c 'import sys; sys.exit(sys.version_info[0] < 3)' >/dev/null 2>&1; then
			PY_CMD=("${c[@]}")
			return 0
		fi
	done
	return 1
}
GEO_DB=""

geo_init() {
	if [[ ! -e Country.mmdb ]]; then
		log WARN "Cannot open Country.mmdb" err "open Country.mmdb: no such file or directory"
		return
	fi
	if [[ ! -r Country.mmdb || -d Country.mmdb ]]; then
		log WARN "Cannot open Country.mmdb" err "open Country.mmdb: permission denied"
		return
	fi
	GEO_DB="$PWD/Country.mmdb"
	if command -v mmdblookup >/dev/null 2>&1; then
		GEO_MODE=mmdblookup
	elif find_python; then
		GEO_MODE=python
	else
		log WARN "Cannot open Country.mmdb" err "neither mmdblookup (libmaxminddb) nor Python 3 is installed"
		return
	fi
	log INFO "Enabled GeoIP"
}

# Minimal MaxMind DB reader, used only when mmdblookup is not installed.
GEO_PY=$(
	cat <<'PYEOF'
import sys, mmap, ipaddress
def main():
    path, ip = sys.argv[1], sys.argv[2]
    with open(path, 'rb') as f:
        buf = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    marker = buf.rfind(b'\xab\xcd\xefMaxMind.com')
    if marker < 0:
        raise Exception('invalid MaxMind DB file')
    base = [0]
    def be(b): return int.from_bytes(b, 'big')
    def dec(off):
        ctrl = buf[off]; off += 1
        t = ctrl >> 5
        if t == 1:
            ss, v = (ctrl >> 3) & 3, ctrl & 7
            if ss == 0: p = (v << 8) | buf[off]; off += 1
            elif ss == 1: p = ((v << 16) | be(buf[off:off+2])) + 2048; off += 2
            elif ss == 2: p = ((v << 24) | be(buf[off:off+3])) + 526336; off += 3
            else: p = be(buf[off:off+4]); off += 4
            return dec(base[0] + p)[0], off
        if t == 0:
            t = buf[off] + 7; off += 1
        size = ctrl & 0x1f
        if size == 29: size = 29 + buf[off]; off += 1
        elif size == 30: size = 285 + be(buf[off:off+2]); off += 2
        elif size == 31: size = 65821 + be(buf[off:off+3]); off += 3
        if t == 7:
            d = {}
            for _ in range(size):
                k, off = dec(off); v, off = dec(off); d[k] = v
            return d, off
        if t == 11:
            a = []
            for _ in range(size):
                v, off = dec(off); a.append(v)
            return a, off
        if t == 14: return bool(size), off
        raw = buf[off:off+size]; off += size
        if t == 2: return raw.decode('utf-8', 'replace'), off
        if t in (5, 6, 9, 10): return be(raw), off
        if t == 8: return int.from_bytes(raw.rjust(4, b'\0'), 'big', signed=True), off
        return raw, off
    base[0] = marker + 14
    meta = dec(marker + 14)[0]
    nodes, rs, ipver = meta['node_count'], meta['record_size'], meta['ip_version']
    tree = rs * 2 // 8 * nodes
    base[0] = tree + 16
    def rec(node, bit):
        o = node * rs * 2 // 8
        if rs == 24: return be(buf[o+3*bit:o+3*bit+3])
        if rs == 28:
            m = buf[o+3]
            if bit == 0: return ((m & 0xf0) << 20) | be(buf[o:o+3])
            return ((m & 0x0f) << 24) | be(buf[o+4:o+7])
        if rs == 32: return be(buf[o+4*bit:o+4*bit+4])
        raise Exception('unsupported record size %d' % rs)
    addr = ipaddress.ip_address(ip)
    if addr.version == 6 and addr.ipv4_mapped is not None:
        addr = addr.ipv4_mapped
    node = 0
    if addr.version == 4:
        nbits = 32
        if ipver == 6:
            for _ in range(96):
                if node >= nodes: break
                node = rec(node, 0)
    else:
        if ipver == 4:
            raise Exception("error looking up '%s': you attempted to look up an IPv6 address in an IPv4-only database" % ip)
        nbits = 128
    val = int(addr)
    for i in range(nbits):
        if node >= nodes: break
        node = rec(node, (val >> (nbits - 1 - i)) & 1)
    if node > nodes:
        data = dec(tree + node - nodes)[0]
        c = data.get('country') if isinstance(data, dict) else None
        if isinstance(c, dict):
            print(c.get('iso_code', '')); return
    elif node < nodes:
        raise Exception('invalid node in search tree')
    print('')
try:
    main()
except Exception as e:
    print(e, file=sys.stderr); sys.exit(1)
PYEOF
)

# geo_lookup IP -> REPLY = ISO country code ("" when unknown, N/A on errors)
geo_lookup() {
	local ip=$1 res
	case $GEO_MODE in
	mmdblookup)
		if ! res=$(mmdblookup --file "$GEO_DB" --ip "$ip" country iso_code 2>&1 | tr -d '\r'; exit "${PIPESTATUS[0]}"); then
			log DEBUG "Error reading geo" err "${res//$'\n'/ }"
			REPLY="N/A"
			return
		fi
		local re='"([^"]*)" <utf8_string>'
		if [[ $res =~ $re ]]; then
			REPLY=${BASH_REMATCH[1]}
		elif [[ $res == *"Could not find"* || $res == *"No data was found"* || -z ${res//[[:space:]]/} ]]; then
			REPLY=""
		else
			log DEBUG "Error reading geo" err "${res//$'\n'/ }"
			REPLY="N/A"
		fi
		;;
	python)
		if res=$("${PY_CMD[@]}" -I -c "$GEO_PY" "$GEO_DB" "$ip" 2>&1); then
			REPLY=${res//$'\r'/}
		else
			log DEBUG "Error reading geo" err "${res//$'\n'/ }"
			REPLY="N/A"
		fi
		;;
	*) REPLY="N/A" ;;
	esac
}

# --------------------------------------------------------------------- TLS --

TIMEOUT_CMD=""
OPENSSL_GROUPS="X25519"
OPENSSL_EXTRA=()

tls_init() {
	# s_client must leave right after the handshake. Waiting for EOF on stdin
	# does not work everywhere (e.g. Windows builds), so prefer -no-interactive
	# (OpenSSL 3.2+); older versions get a "Q" (quit) command on stdin instead.
	if openssl s_client -help 2>&1 | grep -q -e '-no-interactive'; then
		OPENSSL_EXTRA=(-no-interactive)
	fi
	if command -v timeout >/dev/null 2>&1; then
		TIMEOUT_CMD=timeout
	elif command -v gtimeout >/dev/null 2>&1; then
		TIMEOUT_CMD=gtimeout
	fi
	# Go offers X25519 and X25519MLKEM768 (only those); use the PQ hybrid when
	# the local OpenSSL knows it (3.5+). Probing via a unix socket sends nothing.
	local g
	for g in '*X25519MLKEM768:*X25519' 'X25519MLKEM768:X25519'; do
		if ! openssl s_client -groups "$g" -unix /nonexistent/realitlscanner </dev/null 2>&1 |
			grep -q -e 'SSL_CONF_cmd' -e 'cannot be set' -e 'Error with command'; then
			OPENSSL_GROUPS=$g
			break
		fi
	done
}

# run_with_timeout SECONDS CMD... (kills CMD after SECONDS). Meant to be run
# in a subshell of its own: it replaces it, and a SIGTERM to it stops CMD too.
run_with_timeout() {
	local t=$1
	shift
	((t <= 0)) && t=0.001
	if [[ -n $TIMEOUT_CMD ]]; then
		exec "$TIMEOUT_CMD" -k 1 "$t" "$@"
	fi
	"$@" &
	local pid=$!
	trap 'kill -TERM "$pid" 2>/dev/null; exit 143' TERM
	(
		sleep "$t"
		kill -TERM "$pid" 2>/dev/null
		sleep 1
		kill -KILL "$pid" 2>/dev/null
	) </dev/null >/dev/null 2>&1 &
	local watcher=$!
	wait "$pid"
	local rc=$?
	kill "$watcher" 2>/dev/null
	wait "$watcher" 2>/dev/null
	return $rc
}

# Go's x509.SignatureAlgorithm.String()
sig_name() {
	local alg=$1 hash=$2
	case ${alg,,} in
	md2withrsaencryption) REPLY=MD2-RSA ;;
	md5withrsaencryption) REPLY=MD5-RSA ;;
	sha1withrsaencryption | sha1withrsa) REPLY=SHA1-RSA ;;
	sha256withrsaencryption) REPLY=SHA256-RSA ;;
	sha384withrsaencryption) REPLY=SHA384-RSA ;;
	sha512withrsaencryption) REPLY=SHA512-RSA ;;
	rsassapss)
		case ${hash,,} in
		sha256) REPLY=SHA256-RSAPSS ;;
		sha384) REPLY=SHA384-RSAPSS ;;
		sha512) REPLY=SHA512-RSAPSS ;;
		*) REPLY=0 ;;
		esac
		;;
	dsawithsha1 | dsa-sha1 | dsa_with_sha1) REPLY=DSA-SHA1 ;;
	dsa_with_sha256) REPLY=DSA-SHA256 ;;
	ecdsa-with-sha1) REPLY=ECDSA-SHA1 ;;
	ecdsa-with-sha256) REPLY=ECDSA-SHA256 ;;
	ecdsa-with-sha384) REPLY=ECDSA-SHA384 ;;
	ecdsa-with-sha512) REPLY=ECDSA-SHA512 ;;
	ed25519) REPLY=Ed25519 ;;
	*) REPLY=0 ;;
	esac
}

# Go's x509.PublicKeyAlgorithm.String()
pubkey_name() {
	case ${1,,} in
	rsaencryption) REPLY=RSA ;;
	dsaencryption | dsa) REPLY=DSA ;;
	id-ecpublickey) REPLY=ECDSA ;;
	ed25519) REPLY=Ed25519 ;;
	*) REPLY=0 ;;
	esac
}

# Go's tls.CurveID.String()
curve_name() {
	case $1 in
	X25519 | x25519) REPLY=X25519 ;;
	X25519MLKEM768) REPLY=X25519MLKEM768 ;;
	SecP256r1MLKEM768) REPLY=SecP256r1MLKEM768 ;;
	SecP384r1MLKEM1024) REPLY=SecP384r1MLKEM1024 ;;
	prime256v1 | secp256r1 | P-256) REPLY=CurveP256 ;;
	secp384r1 | P-384) REPLY=CurveP384 ;;
	secp521r1 | P-521) REPLY=CurveP521 ;;
	"") REPLY="CurveID(0)" ;;
	*) REPLY=$1 ;;
	esac
}

# Reads one PEM certificate (CERT_PEM) and sets C_LEN, C_CN, C_ORG, C_DNS,
# C_SIG and C_PUB.
cert_info() {
	local b64 text line section="" pad sig="" hash="" pub="" want_san=false
	b64=$(printf '%s\n' "$CERT_PEM" | sed '/-----/d' | tr -d ' \r\n\t')
	pad=${b64##*[!=]}
	C_LEN=$((${#b64} / 4 * 3 - ${#pad}))
	C_CN=""
	C_ORG=()
	C_DNS=false
	text=$(printf '%s\n' "$CERT_PEM" |
		openssl x509 -noout -subject -issuer -nameopt multiline,utf8,-esc_msb -text 2>/dev/null)
	text=${text//$'\r'/}
	while IFS= read -r line; do
		case $line in
		subject=*) section=subject; continue ;;
		issuer=*) section=issuer; continue ;;
		Certificate:*) section=body; continue ;;
		esac
		case $section in
		subject)
			if [[ $line =~ ^[[:space:]]+commonName[[:space:]]+=\ (.*)$ ]]; then
				C_CN=${BASH_REMATCH[1]}
			fi
			;;
		issuer)
			if [[ $line =~ ^[[:space:]]+organizationName[[:space:]]+=\ (.*)$ ]]; then
				C_ORG+=("${BASH_REMATCH[1]}")
			fi
			;;
		body)
			if [[ $want_san == true ]]; then
				[[ $line == *DNS:* ]] && C_DNS=true
				want_san=false
			elif [[ -z $sig && $line =~ Signature\ Algorithm:\ *([^ ]+) ]]; then
				sig=${BASH_REMATCH[1]}
			elif [[ -z $hash && -z $pub && $line =~ Hash\ Algorithm:\ *([^ ]+) ]]; then
				hash=${BASH_REMATCH[1]}
			elif [[ -z $pub && $line =~ Public\ Key\ Algorithm:\ *([^ ]+) ]]; then
				pub=${BASH_REMATCH[1]}
			elif [[ $line == *"X509v3 Subject Alternative Name:"* ]]; then
				want_san=true
			fi
			;;
		esac
	done <<<"$text"
	sig_name "$sig" "$hash"
	C_SIG=$REPLY
	pubkey_name "$pub"
	C_PUB=$REPLY
}

# Go's ScanTLS(): one target record.
scan_one() {
	local type ip origin hostport res line
	# Ctrl-C is handled by run_pool, which stops the workers with SIGTERM
	trap '' INT
	IFS=$'\t' read -r type ip origin <<<"$1"
	[[ $PRETTY == true ]] && printf . >>"$RTS_TMP/checked"
	if [[ $LIVE == true ]]; then
		if [[ $type == domain ]]; then printf '%s' "$origin" >"$RTS_TMP/current"; else printf '%s' "$ip" >"$RTS_TMP/current"; fi
	fi
	if [[ $type == domain ]]; then
		if ! lookup_ip "$origin"; then
			log DEBUG "Failed to get IP from the origin" origin "$origin" err "$LOOKUP_ERR"
			return
		fi
		ip=$REPLY
	fi
	if [[ $ip == *:* ]]; then hostport="[$ip]:$port"; else hostport="$ip:$port"; fi
	local -a sni=(-noservername)
	[[ $type == domain ]] && sni=(-servername "$origin")

	# The handshake runs behind a process substitution so that its pid is known:
	# when the worker is stopped (Ctrl-C), it stops openssl as well.
	# stderr goes to its own file: mixed into stdout it could split PEM lines
	local fd cpid errf="$RTS_TMP/$BASHPID" err=""
	exec {fd}< <(run_with_timeout "$timeout" openssl s_client -connect "$hostport" "${sni[@]}" \
		-showcerts -state -alpn h2,http/1.1 -groups "$OPENSSL_GROUPS" -min_protocol TLSv1.2 \
		-cipher 'ECDHE+AESGCM:ECDHE+CHACHA20:ECDHE+AES' "${OPENSSL_EXTRA[@]}" \
		< <(((${#OPENSSL_EXTRA[@]})) || printf 'Q\n') 2>"$errf")
	cpid=$!
	trap 'kill -TERM "$cpid" 2>/dev/null; exit 143' INT TERM
	res=""
	IFS= read -r -d '' -u "$fd" res
	# native Windows builds of openssl (Git Bash, MSYS2) print CRLF
	res=${res//$'\r'/}
	exec {fd}<&-
	[[ -f $errf ]] && err=$(<"$errf")
	rm -f "$errf"
	# s_client prints SSL_connect:* (unbuffered, stderr) once TCP is connected
	[[ $err == *SSL_connect:* ]] && res="CONNECTED(stderr)"$'\n'$res
	trap '' INT
	trap - TERM

	local connected=false version="" alpn="" curve="" group="" in_cert=false pem=""
	local -a certs=()
	while IFS= read -r line; do
		case $line in
		CONNECTED\(*) connected=true ;;
		-----BEGIN\ CERTIFICATE-----)
			in_cert=true
			pem=$line$'\n'
			;;
		-----END\ CERTIFICATE-----)
			if [[ $in_cert == true ]]; then
				certs+=("$pem$line")
				in_cert=false
			fi
			;;
		"New, "*)
			[[ $line =~ ^New,\ (TLSv1\.[0-9]|SSLv3),\ Cipher\ is\ (.*)$ && ${BASH_REMATCH[2]} != "(NONE)" ]] &&
				version=${BASH_REMATCH[1]}
			;;
		"ALPN protocol: "*) alpn=${line#ALPN protocol: } ;;
		"Negotiated TLS1.3 group: "*) group=${line#Negotiated TLS1.3 group: } ;;
		"Server Temp Key: "* | "Peer Temp Key: "*)
			# "X25519, 253 bits" or "ECDH, prime256v1, 256 bits"
			line=${line#*Temp Key: }
			if [[ $line == "ECDH, "* ]]; then
				line=${line#ECDH, }
				curve=${line%%,*}
			elif [[ $line != DH,* ]]; then
				curve=${line%%,*}
			fi
			;;
		*) [[ $in_cert == true ]] && pem+=$line$'\n' ;;
		esac
	done <<<"$res"

	if [[ $connected != true ]]; then
		log DEBUG "Cannot dial" target "$hostport"
		return
	fi
	if [[ -z $version || ${#certs[@]} -eq 0 ]]; then
		log DEBUG "TLS handshake failed" target "$hostport"
		return
	fi
	# the certificate chain as sent by the server (s_client -showcerts)
	local tlsver="TLS ${version#TLSv}"
	[[ $version == SSLv3 ]] && tlsver="SSLv3"
	[[ -n $group ]] && curve=$group
	curve_name "$curve"
	curve=$REPLY

	local length=0 domain="" issuers="" leaf_sig="" leaf_pub="" i
	for ((i = 0; i < ${#certs[@]}; i++)); do
		CERT_PEM=${certs[i]}
		cert_info
		length=$((length + C_LEN))
		if ((i == 0)); then
			domain=$C_CN
			issuers=""
			local o first=true
			for o in "${C_ORG[@]}"; do
				if [[ $first == true ]]; then issuers=$o; first=false; else issuers+=" | $o"; fi
			done
			leaf_sig=$C_SIG
			leaf_pub=$C_PUB
		fi
		if [[ $C_DNS == true ]]; then
			leaf_sig=$C_SIG
			leaf_pub=$C_PUB
		fi
	done
	local certlen="${length}(certs count: ${#certs[@]})"

	geo_lookup "$ip"
	local geo=$REPLY
	local level=INFO feasible=true
	if [[ $tlsver != "TLS 1.3" || $alpn != h2 || -z $domain || -z $issuers ]]; then
		level=DEBUG
		feasible=false
	elif [[ -n $OUT_FILE ]]; then
		printf '%s\n' "$ip,$origin,$tlsver,$alpn,$curve,$certlen,$leaf_sig,$leaf_pub,$domain,\"$issuers\",$geo" >>"$OUT_FILE"
	fi
	# DNS check is only shown on the terminal: -raw logs and the CSV stay as in the original
	local -a dnskv=()
	if [[ $PRETTY == true && $checkdns == true && $feasible == true ]]; then
		dns_check "$domain" "$ip" "$origin"
		dnskv=(dns "$REPLY")
	fi
	log "$level" "Connected to target" feasible "$feasible" \
		ip "$ip" \
		origin "$origin" \
		tls "$tlsver" \
		alpn "$alpn" \
		curve "$curve" \
		cert-length "$certlen" \
		cert-signature "$leaf_sig" \
		cert-publickey "$leaf_pub" \
		cert-domain "$domain" \
		cert-issuer "$issuers" \
		geo "$geo" \
		${dnskv[@]+"${dnskv[@]}"}
}

# Worker pool: run scan_one for every record on stdin, $thread at a time.
run_pool() {
	local rec pid
	local -a pids=() alive
	# Ctrl-C: stop the workers (async jobs ignore SIGINT), then die by SIGINT
	# so that the main shell stops as well, like the Go binary does.
	trap '((${#pids[@]})) && kill -TERM "${pids[@]}" 2>/dev/null; trap - INT; kill -INT $BASHPID' INT TERM
	while IFS= read -r -d '' rec; do
		while ((${#pids[@]} >= thread)); do
			wait -n
			alive=()
			for pid in "${pids[@]}"; do
				kill -0 "$pid" 2>/dev/null && alive+=("$pid")
			done
			pids=("${alive[@]}")
		done
		scan_one "$rec" &
		pids+=($!)
	done
	wait
}

# -------------------------------------------------------------------- main --

main() {
	local utf8=false
	[[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] && utf8=true
	# byte-wise matching everywhere; some locales (e.g. on Windows) break classes
	export LC_ALL=C
	shopt -s extglob
	exec 3>&1
	# like the Go version (which only clears the upper-case variables)
	unset ALL_PROXY HTTP_PROXY HTTPS_PROXY NO_PROXY all_proxy

	parse_flags "$@"
	if [[ $raw != true && -t 1 ]]; then
		PRETTY=true
		pretty_init "$utf8"
	fi

	local n=0
	[[ -n $addr ]] && ((n++))
	[[ -n $in ]] && ((n++))
	[[ -n $url ]] && ((n++))
	if ((n != 1)); then
		log ERROR "You must specify and only specify one of \`addr\`, \`in\`, or \`url\`"
		print_defaults
		return 0
	fi
	if ! command -v openssl >/dev/null 2>&1; then
		log ERROR "openssl is required but was not found in PATH"
		return 1
	fi

	OUT_FILE=""
	if [[ -n $out ]]; then
		if ! { printf 'IP,ORIGIN,TLS,ALPN,CURVE,CERT_LENGTH,CERT_SIGNATURE,CERT_PUBLICKEY,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n' >"$out"; } 2>/dev/null; then
			log ERROR "Error opening file" path "$out"
			return 0
		fi
		OUT_FILE=$out
	fi

	local src_kind="" source_data="" infinite_origin=""
	local -a infinite_ip=()
	if [[ -n $addr ]]; then
		if is_cidr "$addr"; then
			src_kind=lines
			source_data=$addr
		elif parse_ip "$addr"; then
			src_kind=infinite
			infinite_ip=("${IPH[@]}")
		elif lookup_ip "$addr"; then
			src_kind=infinite
			infinite_ip=("${LOOKUP_IPH[@]}")
		else
			log ERROR "Not a valid IP, IP CIDR or domain" addr "$addr"
			src_kind=none
		fi
		infinite_origin=$addr
	elif [[ -n $in ]]; then
		if [[ ! -r $in || -d $in ]]; then
			log ERROR "Error reading file" path "$in"
			return 0
		fi
		src_kind="file"
	else
		log INFO "Fetching url..."
		local tmp rc=0 err=""
		tmp=$(mktemp -d "${TMPDIR:-/tmp}/realitlscanner.XXXXXX") || return 1
		# the same up-front checks as Go's http.Get
		local scheme=""
		[[ $url =~ ^([A-Za-z][A-Za-z0-9+.-]*): ]] && scheme=${BASH_REMATCH[1]}
		if [[ ${scheme,,} != http && ${scheme,,} != https ]]; then
			err="unsupported protocol scheme \"$scheme\""
		elif [[ ! $url =~ ^[A-Za-z]+://[^/?#]+ ]]; then
			err="http: no Host in request URL"
		elif command -v curl >/dev/null 2>&1; then
			local -a copts=(-sS -L --max-redirs 10 -A "Go-http-client/1.1" -o "$tmp/body")
			curl -V 2>/dev/null | grep -qi 'libz' && copts+=(--compressed)
			curl "${copts[@]}" -- "$url" 2>"$tmp/err" || rc=$?
		elif command -v wget >/dev/null 2>&1; then
			wget -q -O "$tmp/body" --max-redirect=10 -U "Go-http-client/1.1" -- "$url" 2>"$tmp/err" || rc=$?
			# wget exits 8 on HTTP errors; Go's http.Get still returns the body
			((rc == 8)) && rc=0
		else
			err="curl or wget is required for -url"
		fi
		if ((rc != 0)); then
			err=$(tr '\n' ' ' <"$tmp/err")
			err=${err% }
			err=${err:-exit status $rc}
		fi
		if [[ -n $err ]]; then
			rm -rf "$tmp"
			log ERROR "Error fetching url" err "Get \"$url\": $err"
			return 0
		fi
		# Go: regexp (http|https)://(.*?)[/"<>\s]+ , then de-duplicate
		# (newlines become spaces, so they still terminate a match as \s does)
		source_data=$(LC_ALL=C tr '\n\0' ' ' <"$tmp/body" |
			LC_ALL=C grep -aoE '(http|https)://[^/"<>[:space:]]*[/"<>[:space:]]' |
			LC_ALL=C sed -E 's#^https?://##; s#.$##' |
			awk '!seen[$0]++')
		rm -rf "$tmp"
		local count=0
		[[ -n $source_data ]] && count=$(printf '%s\n' "$source_data" | wc -l)
		# an empty domain survives de-duplication as one entry in Go as well
		log INFO "Parsed domains" count "$((count))"
		src_kind=lines
	fi

	RTS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/realitlscanner.XXXXXX") || return 1
	trap 'rm -rf "$RTS_TMP"' EXIT
	tls_init
	geo_init

	if ((thread < 0)); then
		printf 'panic: sync: negative WaitGroup counter\n' >&2
		exit 2
	fi

	now_us
	local start=$REPLY
	now_rfc3339
	log INFO "Started all scanning threads" time "$REPLY"

	# pretty mode only: after Ctrl-C still print the summary
	local interrupted=false
	[[ $PRETTY == true ]] && trap 'interrupted=true' INT
	local ticker=""
	if [[ $PRETTY == true && ${TERM:-} != dumb ]]; then
		LIVE=true
		SECONDS=0
		status_ticker &
		ticker=$!
		trap 'kill -TERM "$ticker" 2>/dev/null; rm -rf "$RTS_TMP"' EXIT
	fi
	if ((thread > 0)); then
		case $src_kind in
		lines) iterate <<<"$source_data" | run_pool ;;
		file) iterate <"$in" | run_pool ;;
		infinite) iterate_infinite "$infinite_origin" "${infinite_ip[@]}" | run_pool ;;
		esac
	fi

	if [[ -n $ticker ]]; then
		kill -TERM "$ticker" 2>/dev/null
		wait "$ticker" 2>/dev/null
		printf '\r\e[K' >&3
		LIVE=false
	fi

	now_us
	go_duration $((REPLY - start))
	local elapsed=$REPLY
	now_rfc3339
	if [[ $interrupted == true ]]; then
		log INFO "Scanning stopped" time "$REPLY" elapsed "$elapsed"
		exit 130
	fi
	log INFO "Scanning completed" time "$REPLY" elapsed "$elapsed"
}

main "$@"
