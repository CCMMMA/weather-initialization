#!/bin/bash

set -euo pipefail

VPN_CONNECTION_NAME="${VPN_CONNECTION_NAME:-}"
CONNECTIVITY_HOST="${CONNECTIVITY_HOST:-8.8.8.8}"
PREV_STATE="INIT"

get_vpn_state() {
    if [[ -z "${VPN_CONNECTION_NAME}" ]]; then
        echo "LAN"
        return
    fi

    if ! nmcli connection show "${VPN_CONNECTION_NAME}" >/dev/null 2>&1; then
        echo "LAN"
        return
    fi

    local vpn_state
    vpn_state="$(nmcli -t -f GENERAL.STATE connection show "${VPN_CONNECTION_NAME}" | cut -d: -f2)"
    case "${vpn_state}" in
        activated)
            echo "VPN"
            ;;
        activating)
            echo "CONNECTING"
            ;;
        *)
            echo "LAN"
            ;;
    esac
}

restart_anydesk_if_needed() {
    local current_state="$1"
    if [[ "${PREV_STATE}" != "INIT" && "${PREV_STATE}" != "${current_state}" ]]; then
        echo "Connectivity state changed from ${PREV_STATE} to ${current_state}, restarting AnyDesk"
        systemctl restart anydesk
    fi
}

while true; do
    sleep 30

    if ! ping -c2 -q -W 3 "${CONNECTIVITY_HOST}" >/dev/null 2>&1; then
        echo "No connection detected"
        CURRENT_STATE="DISCONNECTED"
        restart_anydesk_if_needed "${CURRENT_STATE}"
        PREV_STATE="${CURRENT_STATE}"
        continue
    fi

    CURRENT_STATE="$(get_vpn_state)"
    if [[ "${CURRENT_STATE}" == "LAN" && -n "${VPN_CONNECTION_NAME}" ]]; then
        echo "VPN is down, trying to reconnect ${VPN_CONNECTION_NAME}"
        nmcli connection up "${VPN_CONNECTION_NAME}" || true
        CURRENT_STATE="$(get_vpn_state)"
    fi

    echo "Connection state: ${CURRENT_STATE}"
    restart_anydesk_if_needed "${CURRENT_STATE}"
    PREV_STATE="${CURRENT_STATE}"
done
