# weather-initialization
A script to initialize a new system based on ubuntu 

## Installation
Preliminary
```sh
sudo apt update
sudo apt upgrade -y

sudo apt install git -y
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

Run the script
```sh
sudo -E ./initialize-weather.sh
```
