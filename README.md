# weather-initialization

Provision an Ubuntu-based weather station host with hotspot access, AnyDesk, Docker, `ser2net`, PyVantagePro, and the `vantage-publisher` stack.

## What changed

The original repository was tightly coupled to a single machine layout. It has been updated to:

- use `config.env` for machine-specific values
- generate systemd and GDM config files from templates instead of copying placeholders
- stop assuming the target user is always `weather`
- remove the hard-coded SSH key injection
- avoid world-writable `/storage`
- fix the EEPROM backup path typo and make helper scripts read shared runtime settings

## Prerequisites

Before running the installer on a fresh Ubuntu system:

```sh
sudo apt update
sudo apt upgrade -y
sudo reboot
sudo apt install -y git openssh-server
```

Clone the repository:

```sh
cd "$HOME"
git clone https://github.com/CCMMMA/weather-initialization.git
cd weather-initialization
```

## Configuration

Copy the example configuration and edit it for the target machine:

```sh
cp config.env.example config.env
vim config.env
```

At minimum, set:

- `ANYPWD`: password used for AnyDesk and the hotspot

Useful optional settings:

- `WS_USER`: Linux user that will own the weather station services and files
- `VPN_CONNECTION_NAME`: NetworkManager VPN connection to keep alive
- `AUTHORIZED_KEYS_FILE`: file containing public SSH keys to append to `authorized_keys`
- `WEATHER_DEVICE_URL`: device URL used by PyVantagePro, default `tcp:127.0.0.1:22222`
- `WEATHER_SERIAL_DEVICE`: serial device exported by `ser2net`, default `/dev/ttyUSB0`
- `STORAGE_DIR`: archive/log root, default `/storage`

## Install

Make the installer executable and run it with `sudo` so it can detect the target user:

```sh
chmod +x ./initialize-weather.sh
sudo -E ./initialize-weather.sh
```

The script will:

- configure the hotspot
- install packages and AnyDesk
- install Docker and the Docker Compose plugin
- configure `ser2net`
- install the network recovery service
- install PyVantagePro
- clone and start `vantage-publisher`
- schedule weekly reboots and hourly EEPROM backups

At the end it prints the AnyDesk ID and offers to reboot.

## Files

- `initialize-weather.sh`: main installer
- `config.env.example`: editable machine-specific configuration
- `util/connection-status.service.template`: templated systemd unit for connectivity checks
- `util/custom.conf.template`: templated GDM autologin config
- `util/eeprom.sh`: hourly EEPROM backup helper
- `util/vpn-checker.sh`: connectivity watchdog
- `util/backup-eeprom.py`: export archive data from PyVantagePro to CSV

## Notes

- This installer expects an Ubuntu host with NetworkManager and `systemd`.
- Network downloads are part of the install flow because Docker, AnyDesk, PyVantagePro, and `vantage-publisher` are fetched during setup.
- Review `config.env` before each deployment rather than relying on repository defaults.
