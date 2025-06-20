#!/bin/bash
set -euo pipefail
#set -x

CONFIG_FILE="/etc/ipset-blacklist-firewalld.conf"
LOG_FILE="/var/log/ipset-blacklist.log"
DRY_RUN=false
USE_IPRANGE=false

IPSET_NAME="blacklist"
IPSET_V6_NAME="blacklist-v6"
IPSET_TIMEOUT="86400"
MAXELEM="65536"
FIREWALLD_ZONE="public"
BLACKLIST_URLS=(
    "https://lists.blocklist.de/lists/all.txt"
)
BLACKLIST_V6_URLS=()
WHITELIST=()
WHITELIST_V6=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log "Loaded config from $config_file"
    else
        log "Using default configuration"
    fi
}

parse_arguments() {
    while (( $# )); do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

check_dependencies() {
    local missing=()
    
    for cmd in curl ipset firewall-cmd; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if (( ${#missing[@]} > 0 )); then
        die "Missing required commands: ${missing[*]}"
    fi

    if command_exists iprange; then
        USE_IPRANGE=true
    fi
}

download_blacklist() {
    local url="$1" output_file="$2"
    local max_retries=3 retry_delay=5

    echo $url
    for ((i=1; i<=max_retries; i++)); do
        if curl -L -A "blacklist-update/script/github" --connect-timeout 20 --max-time 60 -o "$output_file" "$url"; then
            return 0
        fi
        sleep "$retry_delay"
    done
    die "Failed to download $url after $max_retries attempts"
}

process_ips() {
    local input_file="$1" output_file="$2" version="$3"
    local pattern

    case "$version" in
        4) pattern='([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' ;;
        6) pattern='([a-f0-9:]+:+)+[a-f0-9]+(/\d{1,3})?' ;;
        *) die "Invalid IP version: $version" ;;
    esac

    grep -Eo "$pattern" "$input_file" > "$output_file.tmp"

    if [[ "$USE_IPRANGE" == true ]]; then
        iprange --optimize "$output_file.tmp" > "$output_file.opt"
        mv "$output_file.opt" "$output_file.tmp"
    fi

    local whitelist=()
    if [[ "$version" == 4 ]] && (( ${#WHITELIST[@]} > 0 )); then
        whitelist=("${WHITELIST[@]}")
    elif [[ "$version" == 6 ]] && (( ${#WHITELIST_V6[@]} > 0 )); then
        whitelist=("${WHITELIST_V6[@]}")
    fi

    if (( ${#whitelist[@]} > 0 )); then
        if [[ "$USE_IPRANGE" == true ]]; then
            printf "%s\n" "${whitelist[@]}" > "$output_file.wl"
            iprange --except "$output_file.wl" "$output_file.tmp" > "$output_file"
            rm -f "$output_file.wl"
        else
            grep -vFf <(printf "%s\n" "${whitelist[@]}") "$output_file.tmp" > "$output_file"
        fi
    else
        mv "$output_file.tmp" "$output_file"
    fi

    [[ -s "$output_file" ]] || die "No valid IPs remaining after processing"
}

atomic_ipset_update() {
    local ipset_name="$1" ips_file="$2" ip_version="$3"
    local family="inet"
    [[ "$ip_version" == 6 ]] && family="inet6"
    
    local temp_set="${ipset_name}-temp-$(date +%s)"

    {
        echo "create ${temp_set} hash:net family ${family} hashsize 16384 maxelem ${MAXELEM} timeout ${IPSET_TIMEOUT}"
        awk "{print \"add ${temp_set} \" \$0}" "$ips_file"
    } | ipset restore -! 2>/dev/null || {
        ipset destroy "${temp_set}" 2>/dev/null
        die "Failed to create temporary ipset ${temp_set}"
    }

    if ! ipset swap "${temp_set}" "${ipset_name}"; then
        ipset destroy "${temp_set}" 2>/dev/null
        die "IPset swap failed - ${ipset_name} remains unchanged"
    fi

    ipset destroy "${temp_set}" 2>/dev/null
}

ensure_ipset_exists() {
    local ipset_name="$1" family="$2"
    
    if ! ipset list -n "${ipset_name}" >/dev/null 2>&1; then
        ipset create "${ipset_name}" hash:net \
            family "${family}" \
            hashsize 1024 \
            maxelem "${MAXELEM}" \
            timeout "${IPSET_TIMEOUT}" || die "Failed to create ${ipset_name}"
            
        if ! firewall-cmd --zone="${FIREWALLD_ZONE}" --query-rich-rule="rule source ipset=${ipset_name} drop" 2>/dev/null; then
            firewall-cmd --permanent --zone="${FIREWALLD_ZONE}" \
                --add-rich-rule="rule source ipset=${ipset_name} drop" >/dev/null
            firewall-cmd --reload >/dev/null
        fi
    fi
}

update_blacklist() {
    local ipset_name="$1" ip_version="$2"
    local tmp_file=$(mktemp)
    
    local url_array="BLACKLIST_URLS"
    [[ "$ip_version" == 6 ]] && url_array="BLACKLIST_V6_URLS"
    
    eval "local urls=(\"\${${url_array}[@]}\")"
    (( ${#urls[@]} == 0 )) && return 0

    for url in "${urls[@]}"; do
        local dl_file=$(mktemp)
        download_blacklist "$url" "$dl_file"
        process_ips "$dl_file" "$tmp_file" "$ip_version"
        rm -f "$dl_file"
    done

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry-run: Would update ${ipset_name} with $(wc -l < "$tmp_file") IPv${ip_version} ranges (maxelem=${MAXELEM})"
        return 0
    fi

    atomic_ipset_update "$ipset_name" "$tmp_file" "$ip_version"
    rm -f "$tmp_file"
}

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--help]

Options:
  -c, --config FILE   Specify config file (default: /etc/ipset-blacklist-firewalld.conf)
  --dry-run    Validate config without applying changes
  --help       Show this help message
EOF
    exit 0
}

main() {
    parse_arguments "$@"
    load_config "$CONFIG_FILE"
    check_dependencies

    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    ensure_ipset_exists "$IPSET_NAME" "inet"
    (( ${#BLACKLIST_V6_URLS[@]} > 0 )) && ensure_ipset_exists "$IPSET_V6_NAME" "inet6"

    update_blacklist "$IPSET_NAME" 4
    (( ${#BLACKLIST_V6_URLS[@]} > 0 )) && update_blacklist "$IPSET_V6_NAME" 6
}

main "$@"
