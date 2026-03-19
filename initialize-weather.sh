#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1091
    source "${CONFIG_FILE}"
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo -e "\e[91mPlease launch this script as root user.\e[0m"
    exit 1
fi

if [[ -z "${SUDO_USER:-}" ]]; then
    echo -e "\e[91mPlease run the script with sudo so the target user can be detected.\e[0m"
    exit 1
fi

if [[ -z "${ANYPWD:-}" ]]; then
    echo -e "\e[91mPlease set an AnyDesk password in variable ANYPWD or config.env.\e[0m"
    exit 1
fi

WS_USER="${WS_USER:-$SUDO_USER}"
WS_HOME="$(getent passwd "${WS_USER}" | cut -d: -f6)"
if [[ -z "${WS_HOME}" ]]; then
    echo -e "\e[91mUnable to determine the home directory for user ${WS_USER}.\e[0m"
    exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-${WS_HOME}/weather-initialization}"
VANTAGE_PUBLISHER_DIR="${VANTAGE_PUBLISHER_DIR:-${WS_HOME}/vantage-publisher}"
HOTSPOT_CONNECTION_NAME="${HOTSPOT_CONNECTION_NAME:-Weather}"
HOTSPOT_SSID="${HOTSPOT_SSID:-weather-parthenope}"
HOTSPOT_BAND="${HOTSPOT_BAND:-bg}"
HOTSPOT_CHANNEL="${HOTSPOT_CHANNEL:-11}"
VPN_CONNECTION_NAME="${VPN_CONNECTION_NAME:-}"
CONNECTIVITY_HOST="${CONNECTIVITY_HOST:-8.8.8.8}"
WEATHER_DEVICE_URL="${WEATHER_DEVICE_URL:-tcp:127.0.0.1:22222}"
WEATHER_SERIAL_DEVICE="${WEATHER_SERIAL_DEVICE:-/dev/ttyUSB0}"
STORAGE_GROUP="${STORAGE_GROUP:-vantagepro}"
STORAGE_DIR="${STORAGE_DIR:-/storage}"
AUTHORIZED_KEYS_FILE="${AUTHORIZED_KEYS_FILE:-}"

APT_PACKAGES=(
    curl
    gdm3
    make
    openssh-server
    python3-pip
    ser2net
    vim
    wget
    xserver-xorg-video-dummy
)

log_step() {
    echo -e "\e[91m---- $1 ----\e[0m"
}

ensure_directory() {
    install -d -m "$1" "$2"
}

append_authorized_keys() {
    local ssh_dir="${WS_HOME}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    ensure_directory 700 "${ssh_dir}"
    touch "${auth_keys}"
    chmod 600 "${auth_keys}"
    chown -R "${WS_USER}:${WS_USER}" "${ssh_dir}"

    if [[ -n "${AUTHORIZED_KEYS_FILE}" && -f "${AUTHORIZED_KEYS_FILE}" ]]; then
        while IFS= read -r key_line; do
            [[ -z "${key_line}" ]] && continue
            grep -Fqx "${key_line}" "${auth_keys}" || echo "${key_line}" >> "${auth_keys}"
        done < "${AUTHORIZED_KEYS_FILE}"
    fi
}

render_template() {
    local template="$1"
    local destination="$2"

    sed \
        -e "s|__WS_USER__|${WS_USER}|g" \
        -e "s|__INSTALL_DIR__|${INSTALL_DIR}|g" \
        -e "s|__VANTAGE_PUBLISHER_DIR__|${VANTAGE_PUBLISHER_DIR}|g" \
        "${template}" > "${destination}"
}

write_runtime_env() {
    cat > /etc/default/weather-initialization <<EOF
WS_USER=${WS_USER}
INSTALL_DIR=${INSTALL_DIR}
VANTAGE_PUBLISHER_DIR=${VANTAGE_PUBLISHER_DIR}
VPN_CONNECTION_NAME=${VPN_CONNECTION_NAME}
CONNECTIVITY_HOST=${CONNECTIVITY_HOST}
WEATHER_DEVICE_URL=${WEATHER_DEVICE_URL}
STORAGE_DIR=${STORAGE_DIR}
EOF
}

setup_hotspot() {
    log_step "SETTING HOTSPOT"
    if nmcli connection show "${HOTSPOT_CONNECTION_NAME}" >/dev/null 2>&1; then
        nmcli connection modify "${HOTSPOT_CONNECTION_NAME}" \
            802-11-wireless.ssid "${HOTSPOT_SSID}" \
            802-11-wireless.band "${HOTSPOT_BAND}" \
            802-11-wireless.channel "${HOTSPOT_CHANNEL}" \
            wifi-sec.key-mgmt wpa-psk \
            wifi-sec.psk "${ANYPWD}" \
            connection.autoconnect yes \
            802-11-wireless-security.pmf 1
    else
        nmcli device wifi hotspot \
            con-name "${HOTSPOT_CONNECTION_NAME}" \
            ssid "${HOTSPOT_SSID}" \
            band "${HOTSPOT_BAND}" \
            channel "${HOTSPOT_CHANNEL}" \
            password "${ANYPWD}"
        nmcli connection modify "${HOTSPOT_CONNECTION_NAME}" connection.autoconnect yes
        nmcli connection modify "${HOTSPOT_CONNECTION_NAME}" 802-11-wireless-security.pmf 1
    fi
    nmcli con up "${HOTSPOT_CONNECTION_NAME}"
}

install_prerequisites() {
    log_step "INSTALLING PREREQUISITES"
    apt update
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
    append_authorized_keys
}

install_anydesk() {
    log_step "INSTALLING ANYDESK"
    if [[ ! -f /etc/apt/sources.list.d/anydesk-stable.list ]]; then
        wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor -o /usr/share/keyrings/anydesk.gpg
        echo "deb [signed-by=/usr/share/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
    fi
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y anydesk
    echo "${ANYPWD}" | anydesk --set-password
    render_template "${INSTALL_DIR}/util/custom.conf.template" /etc/gdm3/custom.conf
    install -m 644 "${INSTALL_DIR}/util/xorg.conf" /etc/X11/xorg.conf
}

install_docker() {
    log_step "INSTALLING DOCKER"
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
    fi
    getent group docker >/dev/null || groupadd docker
    usermod -aG docker "${WS_USER}"
    systemctl enable --now docker.service
    systemctl enable --now containerd.service
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin

    ensure_directory 755 "${WS_HOME}/.docker"
    chown -R "${WS_USER}:${WS_USER}" "${WS_HOME}/.docker"
}

install_ser2net() {
    log_step "INSTALLING SER2NET"
    sed "s|/dev/ttyUSB0|${WEATHER_SERIAL_DEVICE}|g" \
        "${INSTALL_DIR}/util/ser2net.yaml" > /etc/ser2net.yaml
    install -m 644 "${INSTALL_DIR}/util/ser2net.service" /etc/systemd/system/ser2net.service
    systemctl daemon-reload
    systemctl enable --now ser2net.service
}

install_connection_checker() {
    log_step "INSTALLING CONNECTION CHECKER DAEMON"
    chmod +x "${INSTALL_DIR}/util/vpn-checker.sh"
    render_template "${INSTALL_DIR}/util/connection-status.service.template" /etc/systemd/system/connection-status.service
    systemctl daemon-reload
    systemctl enable --now connection-status.service
}

prepare_storage() {
    log_step "CREATING STORAGE AND SETTING PERMISSIONS"
    ensure_directory 2775 "${STORAGE_DIR}"
    getent group "${STORAGE_GROUP}" >/dev/null || groupadd "${STORAGE_GROUP}"
    chown -R "${WS_USER}:${STORAGE_GROUP}" "${STORAGE_DIR}"
    usermod -aG "${STORAGE_GROUP}" "${WS_USER}"
    chmod 2775 "${STORAGE_DIR}"
}

install_pyvantagepro() {
    log_step "INSTALLING PyVantagePro AND SETTING VANTAGEPRO DATE"
    sudo -u "${WS_USER}" env PATH="${PATH}" bash -lc "
        python3 -m pip install --upgrade pip
        python3 -m pip install git+https://github.com/ccmmma/PyVantagePro.git
        current_time=\$(date '+%Y-%m-%d %H:%M:%S')
        pyvantagepro settime \"${WEATHER_DEVICE_URL}\" \"\$current_time\"
        chmod +x '${INSTALL_DIR}/util/backup-eeprom.py'
        chmod +x '${INSTALL_DIR}/util/eeprom.sh'
    "
}

install_vantage_publisher() {
    log_step "INSTALLING VANTAGE-PUBLISHER"
    sudo -u "${WS_USER}" env PATH="${PATH}" bash -lc "
        if [[ ! -d '${VANTAGE_PUBLISHER_DIR}/.git' ]]; then
            git clone https://github.com/ccmmma/vantage-publisher '${VANTAGE_PUBLISHER_DIR}'
        fi
        cd '${VANTAGE_PUBLISHER_DIR}'
        chmod +x vantage-updater.sh
        make build
        docker compose up -d
    "
    render_template "${INSTALL_DIR}/util/vantage-updater.service.template" /etc/systemd/system/vantage-updater.service
    systemctl daemon-reload
    systemctl enable vantage-updater.service
}

configure_cron() {
    log_step "SETTING CRONTAB"
    local eeprom_job="0 * * * * ${INSTALL_DIR}/util/eeprom.sh >> ${STORAGE_DIR}/log/eeprom.log 2>&1"
    ensure_directory 2775 "${STORAGE_DIR}/log"
    chown -R "${WS_USER}:${STORAGE_GROUP}" "${STORAGE_DIR}/log"

    {
        crontab -l 2>/dev/null | grep -Fv "${INSTALL_DIR}/util/eeprom.sh" | grep -Fv "/sbin/reboot" || true
        echo "0 0 * * 0 /sbin/reboot"
        echo "${eeprom_job}"
    } | crontab -
}

main() {
    log_step "SETTING ${WS_USER} AS WS USER IN ${WS_HOME}"
    write_runtime_env
    setup_hotspot
    install_prerequisites
    install_anydesk
    install_docker
    install_ser2net
    install_connection_checker
    prepare_storage
    install_pyvantagepro
    install_vantage_publisher
    configure_cron

    log_step "DONE"
    anydesk --get-id || true
    echo -e "\e[91mPlease reboot the system. (y/n)\e[0m"
    read -r rb

    if [[ "${rb}" == "y" ]]; then
        reboot
    else
        echo "Something may not work correctly until reboot."
    fi
}

main "$@"
