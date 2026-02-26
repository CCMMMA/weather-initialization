#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo -e "\e[91mPlease launch this script as root user.\e[0m"
    exit 1
fi

if [ -z "$ANYPWD" ]; then
    echo -e "\e[91mPlease set an anydesk password in variable ANYPWD.\e[0m"
    exit 1
fi

echo -e "\e[91m---- SETTING HOTSPOT ----\e[0m"

nmcli device wifi hotspot con-name Weather ssid weather-parthenope band bg channel 11 password $ANYPWD
nmcli connection modify Weather connection.autoconnect yes
nmcli connection modify Weather 802-11-wireless-security.pmf 1
nmcli con up Weather

echo -e "\e[91m---- INSTALLING PREREQUISITES ----\e[0m"
apt update
apt upgrade -y
apt-get install -y vim openssh-server make curl python3-pip


echo -e "\e[91m---- INSTALLING ANYDESK ----\e[0m"
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
apt update
apt install anydesk -y
echo -e "\e[91mSetting password ...\e[0m"
echo $ANYPWD | sudo anydesk --set-password
cp $HOME/weather-initialization/util/custom.conf /etc/gdm3/custom.conf

echo -e "\e[91mSetting dummy display ...\e[0m"
apt-get install xserver-xorg-video-dummy
cp $HOME/weather-initialization/util/xorg.conf /etc/X11/xorg.conf


echo -e "\e[91m---- INSTALLING DOCKER ----\e[0m"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
groupadd docker
usermod -aG docker $USER
sudo chmod 666 /var/run/docker.sock
systemctl enable docker.service
systemctl enable containerd.service
apt-get install docker-compose -y
chown "$USER":"$USER" /home/"$USER"/.docker -R
sudo chmod g+rwx "$HOME/.docker" -R


echo -e "\e[91m---- INSTALLING SER2NET ----\e[0m"
apt-get install ser2net -y
cp $HOME/weather-initialization/util/ser2net.yaml /etc/ser2net.yaml
cp $HOME/weather-initialization/util/ser2net.service /lib/systemd/system/ser2net.service
echo -e "\e[91mActivating ser2net ...\e[0m"
systemctl restart ser2net.service 

echo -e "\e[91m---- INSTALLING CONNECTION CHECKER DAEMON ----\e[0m"
chmod +x $HOME/weather-initialization/util/vpn-checker.sh
cp $HOME/weather-initialization/util/connection-status.service /etc/systemd/
systemctl enable $HOME/weather-initialization/util/connection-status.service
#sudo systemctl start $HOME/weather-initialization/util/connection-status.service

echo -e "\e[91m---- CREATING STORAGE AND SETTING PERMISSIONS ----\e[0m"
mkdir -p /storage
groupadd vantagepro
chown -R :vantagepro /storage
usermod -aG vantagepro ${USER}
chmod -R 777 /storage
chmod g+s /storage

echo -e "\e[91m---- INSTALLING PyVantagePro AND SETTING VANTAGEPRO DATE ----\e[0m"
sudo -u "$USER" bash -c "
    pip install --upgrade pip
    pip install git+https://github.com/ccmmma/PyVantagePro.git
    current_time=\$(date '+%Y-%m-%d %H:%M:%S')
    pyvantagepro settime tcp:127.0.0.1:22222 \"\$current_time\"
    chmod +x $HOME/weather-initialization/util/backup-eeprom.py
    chmod +x $HOME/weather-initialization/util/eeprom.sh
"

echo -e "\e[91m---- INSTALLING VANTAGE-PUBLISHER ----\e[0m"
sudo -u "$USER" bash -c "
    cd $HOME
    git clone https://github.com/ccmmma/vantage-publisher
    cd vantage-publisher
    chmod +x vantage-updater.sh
    make build
    docker compose up -d
"
cp $HOME/weather-initialization/util/vantage-updater.service /etc/systemd/
systemctl enable $HOME/weather-initialization/util/vantage-updater.service

echo -e "\e[91m---- SETTING CRONTAB ----\e[0m"
{
    crontab -l 2>/dev/null
    echo "0 0 * * 0 /sbin/reboot"
    echo "0 * * * * ${HOME}/weather-initialization/util/eeprom.sh >> /storage/log/eeprom.log 2>&1"
} | crontab -
echo -e "\e[91mCrontab updated successfully!\e[0m"

echo -e "\e[91m---- DONE! ----\e[0m"
anydesk --get-id
echo -e "\e[91mPlease reboot the system. (y/n)\e[0m"
read rb


if [ "$rb" = "y" ]; then
    reboot
else
    echo "Something will not work correctly until reboot..."
fi
