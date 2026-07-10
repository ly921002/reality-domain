#!/bin/sh
set -eu

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
INTERVAL="${INTERVAL:-3600}"
DOMAINS="${DOMAINS:-}"
PING_COUNT="${PING_COUNT:-5}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
TOP="${TOP:-0}"   # 0=全部，5=前5名


[ -n "$DOMAINS" ] || {
    echo "ERROR: DOMAINS is empty."
    exit 1
}

send_tg() {
    curl -s \
        -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$1" >/dev/null
}

score_domain() {

    DOMAIN="$1"

    ################################
    # Ping
    ################################

    PING_RESULT="$(ping -c "$PING_COUNT" "$DOMAIN" 2>/dev/null || true)"

    LOSS=100
    AVG=999

    if echo "$PING_RESULT" | grep -q "min/avg/max"; then
        LOSS="$(echo "$PING_RESULT" | awk -F',' '/packet loss/{
            gsub(/ /,"",$3)
            sub("%packetloss","",$3)
            print $3
        }')"

        AVG="$(echo "$PING_RESULT" |
            awk -F'/' '/min\/avg\/max/{
                print $5
            }')"
    fi

    ################################
    # HTTPS
    ################################

    CURL="$(curl \
        -o /dev/null \
        -s \
        --connect-timeout "$CONNECT_TIMEOUT" \
        -w "%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}" \
        "https://${DOMAIN}" || true)"

    TCP="$(echo "$CURL" | cut -d'|' -f1)"
    TLS="$(echo "$CURL" | cut -d'|' -f2)"
    HTTP="$(echo "$CURL" | cut -d'|' -f3)"
    TOTAL="$(echo "$CURL" | cut -d'|' -f4)"

    [ -z "$TCP" ] && TCP=9
    [ -z "$TLS" ] && TLS=9
    [ -z "$HTTP" ] && HTTP=9
    [ -z "$TOTAL" ] && TOTAL=9

    ################################
    # 转换为 ms
    ################################

    TCP_MS=$(awk "BEGIN{printf \"%.0f\",$TCP*1000}")
    TLS_MS=$(awk "BEGIN{printf \"%.0f\",$TLS*1000}")
    HTTP_MS=$(awk "BEGIN{printf \"%.0f\",$HTTP*1000}")

    ################################
    # 综合评分
    ################################

    SCORE=$(awk \
        -v ping="$AVG" \
        -v tcp="$TCP_MS" \
        -v tls="$TLS_MS" \
        -v http="$HTTP_MS" \
        -v loss="$LOSS" '

BEGIN{

score=100

score-=ping*0.15
score-=tcp*0.25
score-=tls*0.45
score-=http*0.10
score-=loss*2

if(score<0)
    score=0

printf "%.1f",score

}')

    printf "%s|%.1f|%d|%d|%d|%.1f\n" \
        "$DOMAIN" \
        "$AVG" \
        "$TCP_MS" \
        "$TLS_MS" \
        "$HTTP_MS" \
        "$SCORE"
}

while true
do

TMP=$(mktemp)

echo "$DOMAINS" | tr ',' '\n' | while IFS= read -r DOMAIN
do
    [ -z "$DOMAIN" ] && continue

    echo "Testing $DOMAIN..."

    score_domain "$DOMAIN" >> "$TMP"

done

SORTED=$(sort -t'|' -k6 -nr "$TMP")

rm -f "$TMP"

MSG="🌐 Reality Domain Monitor

Host : $(hostname)
Time : $(date '+%F %T')

"

COUNT=0

while IFS='|' read DOMAIN PING TCP TLS HTTP SCORE
do

COUNT=$((COUNT+1))

if [ "$TOP" -gt 0 ] && [ "$COUNT" -gt "$TOP" ]
then
    break
fi

MSG="${MSG}
${COUNT}. ${DOMAIN}

⭐ Score : ${SCORE}
📶 Ping : ${PING} ms
🔌 TCP  : ${TCP} ms
🔒 TLS  : ${TLS} ms
⚡ HTTP : ${HTTP} ms

"

done <<EOF
$SORTED
EOF

send_tg "$MSG"

sleep "$INTERVAL"

done
