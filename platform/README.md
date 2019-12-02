# Prerequisites

We run our mini-Internet on Ubuntu 18.04.

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

```

# Install OpenVPN

You also need to install `easy-rsa` to generate keys and certificate.
```
sudo apt-get install openvpn
```

