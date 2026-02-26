# weather-initialization
A script to initialize a new system based on Ubuntu 

## Installation
Preliminary: upgrade to the latest and reboot
```sh
sudo apt update
sudo apt upgrade -y
sudo reboot
```

If needed at this tage, install the minimal software requirements and enable SSH access
```sh
sudo apt install git openssh-server -y
```

Clone the weather station installation repository
```sh
cd $HOME
git clone https://github.com/ccmmma/weather-initialization.git
cd weather-initialization/
```

Set a password for ANYDESK and hotspot:
```sh
export ANYPWD=<my password>
```

Set permissions
```sh
chmod +x ./initialize-weather.sh
```

Run the script as root
```sh
sudo -E ./initialize-weather.sh
```
