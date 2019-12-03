## Prerequisites

The following installation guide works for Ubuntu 18.

#### Install the Docker Engine
```
sudo apt-get update
sudo apt install docker.io
```

For further information, see the [installation guide](https://docs.docker.com/install/linux/docker-ce/ubuntu/).

#### Install OpenVSwitch
```
sudo apt-get install openvswitch-switch
```

For further information, see the [installation guide](http://docs.openvswitch.org/en/latest/intro/install/).

#### Install OpenVPN

```
sudo apt-get install openvpn
```

## Run the mini-Internet

Clone this directory in your server, and go the directory `platform`.
```
cd platform
```

Then run the startup script:
```
sudo startup.sh
```

By default, this will run a mini-Internet with 20ASes. Make sure your server has enough resources to sustain this mini-Internet (e.g., around 64GB of memory are recommended). Otherwise, see in section [configure the mini-Internet](configure-the-mini-internet) how to run a mini-Internet with only one AS.


## Configure the mini-Internet

