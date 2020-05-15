# Automatey

### Disclaimer

This is very much a work in progress. I'm using this repo to store rough form notes and bits of useful config. Don't expect anything described here to work, quite the contrary. Expect it to delete your C: drive, advertise your house on AirBnB and feed your dog chocolate. You've been warned!

### Introduction

Automatey aims to get you quickly set up with a RHEL 7 server running a bunch of useful automation tools in docker containers. It assumes you've got a reasonable RHEL 7 build that's registered with subscription-manager. The build I'm working on has also been hardened to CIS 2.2 standards...more or less. Ultimately AUTOMATEY will be a series of scripts, config files and docker stuff that lets you get from RHEL ISO to useful automation tooling as quickly and as cheaply as possible.

## How to accomplish this by hand

### Hardening Notes
Docker requires net.ipv4.ip_forward to be set to 1 in the kernel params, otherwise you don't get any networking. CIS generally disables this, so we have to make an exception.

### Kickstart Build

This uses a pretty basic RHEL 7 kickstart configuration. We pre-configure some of the filesystems to be CIS compliant right from the get go. Here's an example...

```
#version=DEVEL
# System authorization information
auth --enableshadow --passalgo=sha512
repo --name="Server-HighAvailability" --baseurl=file:///run/install/repo/addons/HighAvailability
repo --name="Server-ResilientStorage" --baseurl=file:///run/install/repo/addons/ResilientStorage
# Use CDROM installation media
cdrom
# Use graphical install
graphical
# Run the Setup Agent on first boot
firstboot --enable
ignoredisk --only-use=sda
# Keyboard layouts
keyboard --vckeymap=gb --xlayouts='gb'
# System language
lang en_GB.UTF-8

# Network information
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
network  --hostname=automatey.example.com

# Root password
rootpw --iscrypted CHANGEME
# System services
services --enabled="chronyd"
# System timezone
timezone Europe/London --isUtc
# System bootloader configuration
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=sda
# Partition clearing information
clearpart --none --initlabel
# Disk partitioning information
part /boot --fstype="xfs" --ondisk=sda --size=1024
part pv.1156 --fstype="lvmpv" --ondisk=sda --size=101375
volgroup vg00 --pesize=4096 pv.1156
logvol /tmp  --fstype="xfs" --size=5120 --name=tmp --vgname=vg00
logvol /var/log  --fstype="xfs" --size=5120 --name=var_log --vgname=vg00
logvol /opt  --fstype="xfs" --size=32768 --name=opt --vgname=vg00
logvol /var  --fstype="xfs" --size=32768 --name=var --vgname=vg00
logvol swap  --fstype="swap" --size=7163 --name=swap --vgname=vg00
logvol /var/log/audit  --fstype="xfs" --size=2048 --name=var_log_audit --vgname=vg00
logvol /home  --fstype="xfs" --size=4096 --name=home --vgname=vg00
logvol /var/tmp  --fstype="xfs" --size=2048 --name=var_tmp --vgname=vg00
logvol /usr  --fstype="xfs" --size=5120 --name=usr --vgname=vg00
logvol /  --fstype="xfs" --size=5120 --name=root --vgname=vg00

%packages
@^minimal
@core
chrony
kexec-tools

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
```

Could put some %post stuff in, but meh.

### Post OS Install

First off, generate an SSH keypair: `ssh-keygen -t rsa -b 2048 -N "" -C "" -f /root/.ssh/id_rsa`

#### RHN Subscription

```
# subscription-manager register
# subscription-manager attach
# subscription-manager status
```

This is probably going to be slightly different in an environment with Satellite.

#### 1-packages.sh

This part is scripted, but the 1-packages.sh script does some simple stuff...

Enables a bunch of required repos, namely:
```
rhel-7-server-ansible-2.9-rpms 
rhel-7-server-extras-rpms 
rhel-7-server-optional-rpms 
rhel-7-server-rh-common-rpms 
rhel-7-server-rpms 
rhel-7-server-supplementary-rpms 
rhel-server-rhscl-7-rpms 
rhel-server-rhscl-7-eus-rpms
```

It then installs a bunch of packages we need:

```
docker 
wget 
ansible 
make 
automake 
git 
gcc 
mlocate 
python-devel 
python27-python-devel 
sysstat 
net-tools 
bind-utils 
python3 
python3-pip 
libselinux-python3 
tree 
screen 
unzip 
policycoreutils-python 
openssl
```
Then we install epel-release direct from the URL:
```
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y
```
Followed by installing `docker-compose`

Finally we enable and start the docker engine service.

### Configure a Certificate Authority

Reference: https://www.centlinux.com/2019/01/configure-certificate-authority-ca-centos-7.html

We want to be able to easily generate some self-signed certificates. We aren't so much bothered about proving identity of services, more preventing sensitive information getting sniffed on the network, so where we can we'll want to use TLS certs unless someone can provide us with a proper trusted CA somewhere in the environment.

#### Generate Private Key Passphrase
`openssl rand -base64 16` This will generate us a nice random string to protect our private key. Don't lose this!
```
cd /etc/pki/CA/private
openssl genrsa -aes256 -out ca.key 2048
openssl req -new -x509 -days 3650 -key /etc/pki/CA/private/ca.key -out /etc/pki/CA/certs/ca.crt
```
The above commands will generate the key and the CA cert.

#### Certificate Generation Process

If we want to generate a certificate to encrypt another service, the process is pretty simple. In reality, because all containers are running on the same host, we should be able to re-use the same single key and cert on everything, so in theory, we should only need to do this once.

First, generate a key: `openssl genra -out /etc/pki/tls/private/hostname.key 2048`  
Next, create a certificate signing request: `mkdir -p /etc/pki/CA/csr`  
Then `openssl req -new -key /etc/pki/tls/private/hostname.key 2048 -out /etc/pki/CA/csr/hostname.csr`  
Fill in the stuff. Now we have the CSR, we need the CA to sign it: `openssl x509 -req -in /etc/pki/CA/csr/hostname.csr -CA /etc/pki/CA/certs/ca.crt -CAkey /etc/pki/CA/private/ca.key -CAcreateserial -out /etc/pki/CA/newcerts/hostname.crt -days 365`  
You'll need to specify the CA key passphrase when you run the above command.

### TLS-ifying a Containerised App

This appears to be a bit of a dark art. Exactly what you do depends on the app in question, although it seems that the steps are fairly similar. So, here is an example of making Consul do HTTPS.

This is my example Consul docker-compose.yml...

```
version: '3.2'

services:

  consul:
    image: consul:1.7.3
    container_name: consul
    volumes:
      - /opt/automatey/consul/data:/consul/data:Z
      - /opt/automatey/consul/config:/consul/config:Z
    ports:
      - '8300:8300'
      - '8301:8301'
      - '8301:8301/udp'
      - '8500:8500'
      - '8501:8501'
      - '8600:8600'
      - '8600:8600/udp'
    command: agent -server -bootstrap -ui -client=0.0.0.0 -config-file=/consul/config/consul-config.json
```

The options we need to specify to enable HTTPS and point Consul at the right certificates etc can't be passed on the command line, but they can be presented within a config file which we can point to on the command line.

So we have to put what we need into: `/opt/automatey/consul/config` on the host which is mounted under `/consul/config` within the container. 

Here's my `consul-config.json` example:
```
{
  "datacenter": "North",
  "data_dir": "/consul/data",
  "log_level": "INFO",
  "node_name": "automatey",
  "server": true,
  "addresses": {
    "https": "0.0.0.0"
  },
  "ports": {
    "https": 8501
  },
  "key_file": "/consul/config/tls/private/my.key",
  "cert_file": "/consul/config/tls/certs/my.crt",
  "ca_file": "/consul/config/tls/certs/ca-bundle.crt"
}
```

You can see that when we run the container pointing at this config, we've managed to get it running over TLS on the 8501 HTTPS port, we've renamed the DC to "North" and the node to "automatey". W00t!

![screenshot](https://i.imgur.com/0NKKZX8.png) 

The `ca_file` is a copy of the CA certificate bundle from `/etc/pki/CA/certs/ca.key` just renamed to `ca-bundle.crt` and dropped into the right location.

#### Bind Mounts vs Volumes

The above example is using bind mounts which are somewhat easier to put content into, but aren't managed by Docker and are potentially harder to backup.

The proper way to do it would be to setup docker volumes and then anything the container needs from the word go, like a config file for starting up a service should be built into the container image using an appropriate Dockerfile.

~~For Consul we should build our own image which incorporates the config.json along with the certificates and keys required for TLS to be enabled.~~

ACTUALLY, the way to do this is create docker volumes in the docker compose; consul_data and consul_config. Mount consul_config on /consul/config in the container. Remove the `-config-file=/consul/config/consul-config.json` from the docker-compose.yml, and bring it up. 

Login to the container: `docker exec -it consul /bin/sh`  
Copy the config file, certs and private key from the host: `docker cp [src] consul:/consul/config/foo/bar`  
Bring it down: `docker-compose down`  
Add the config-file argument back into the docker-compose.yml and then start it up again.  

# Vault with Consul as a Backend using TLS

This was quite painful. The main crux is in getting the vault configuration file correct and then making it available in the vault_config volume. I just copied it under /var/lib/docker/volumes/... which I don't think is the proper way to do it, but it seems to work.

Contents of the working vault config look like this...

```
{
  "storage": {
    "consul": {
      "address": "consul:8501",
      "path": "vault/",
      "scheme": "https",
      "tls_skip_verify": "true"
    }
  },
  "listener": {
    "tcp": {
      "address": "0.0.0.0:8200",
      "tls_cert_file": "/vault/config/tls/certs/my.crt",
      "tls_key_file": "/vault/config/tls/private/my.key"
    }
  },
  "ui": true
}
```

We have to do a tls_skip_verify because our original cert was generated with a CN of automatey.fritz.box. Really we need a cert that includes subject alternative names that cover all of the relevant container names, but I can't remember how to do that :/  




# OTHER NOTES

From messing about with this, here is some of the other stuff we already know or which may prove useful in future.

### Virtual Machine Specs

Not an exact science, but from looking at the product recommendations, we need:

- Gitlab CE - 4GB RAM supports up to 100 users
- AWX - Minimum 4GB RAM, more = more better, 2 CPUs, 20GB Disk minimum
- Jenkins - 1 CPU, 1GB RAM, 50GB Disk
- Vault - 2 CPU, 4-8GB RAM, 25GB Disk
- Consul - 2 CPU, 8-16GB RAM, 50GB Disk
- OS - 1 CPU, 4GB RAM, 16GB Disk

#### Total System Requirements - Main Automation Machine/Docker Host

- RAM = 32GB
- CPU Cores = 4 or 8 (probably 4)
- Disk = ~200GB

#### System Requirements for Agent Machines

##### Linux Agent
- RAM = 8GB
- CPU Cores = 2
- Disk = 60GB

###### Windows Agent
- RAM = 8GB
- CPU Cores = 2
- Disk = 100GB

### Consul Network Ports

Before running Consul, you should ensure the following bind ports are accessible.

|Use	|Default Ports
|-------|-------------
|DNS: The DNS server (TCP and UDP)	|8600
|HTTP: The HTTP API (TCP Only)	|8500
|HTTPS: The HTTPs API	|disabled (8501)*
|gRPC: The gRPC API	|disabled (8502)*
|LAN Serf: The Serf LAN port |(TCP and UDP)	8301
|Wan Serf: The Serf WAN port |(TCP and UDP)	8302
|server: Server RPC address |(TCP Only)	8300
|Sidecar Proxy Min: Inclusive min port number to use for automatically assigned sidecar service registrations.	|21000
|Sidecar Proxy Max: Inclusive max port number to use for automatically assigned sidecar service registrations.	|21255
*For HTTPS and gRPC the ports specified in the table are recommendations.


#### Consul Port Info

- DNS Interface Used to resolve DNS queries. - We won't use this.
- HTTP API This is used by clients to talk to the HTTP API. - We probably won't use this, HTTPS ideally
- HTTPS API (Optional) Is off by default, but port 8501 is a convention used by various tools as the default.
- gRPC API (Optional). Currently gRPC is only used to expose the xDS API to Envoy proxies. It is off by default, but port 8502 is a convention used by various tools as the default. Defaults to 8502 in -dev mode. - We probably won't use this either.
- Serf LAN This is used to handle gossip in the LAN. Required by all agents.
- Serf WAN This is used by servers to gossip over the WAN, to other servers. As of Consul 0.8 the WAN join flooding feature requires the Serf WAN port (TCP/UDP) to be listening on both WAN and LAN interfaces. See also: Consul 0.8.0 CHANGELOG and GH-3058
-Server RPC This is used by servers to handle incoming requests from other agents.

Note, the default ports can be changed in the agent configuration.

### Filesystem Sizing RHEL Docker Hosts

Might want to run this past Gary...  

- /boot 1g
- swap 16g (32g physical ram)
- / 5g
- /usr 5g
- /tmp 8g
- /opt 20g
- /home 5g
- /var 100g 
- /var/tmp 2g
- /var/log 5g
- /var/log/audit 2g

This leaves approx 30g to grow filesystems later if needed.

### AWX Build as Containers

Reference: https://mangolassi.it/topic/19300/install-awx-on-centos-7-with-docker 

#### Pull and install Pre-Reqs

```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
source ~/.bashrc
nvm install 8
nvm use 8
```

#### Clone Repos

```
mkdir /opt/awx && cd /opt/awx
git clone -b 11.2.0 https://github.com/ansible/awx
cd awx
git clone https://github.com/ansible/awx-logos
```

Ansible AWX utilises an Ansible playbook as its installer. We have to modify some of the paths in use, otherwise everything ends up in ~/.awx which is kind of plop. As an alternative we can specify a dedicated directory, however this would then utilise bind mounts in the resulting docker-compose.yml which isn't ideal.

#### Bind mounts & SELinux

If we have SELinux enforcing (we will) then we have to either add :Z at the end of volume: arguments in docker-compose.yml files to allow Docker to automatically set the relevant context, or we can do it manually for bind mounts as follows:

```
semanage fcontext -a -t container_file_t "/path/to/some/stuff(/.*)?"
restorecon -Rv /path/to/some/stuff
```
---

# IN PROGRESS

## What does what

1-packages.sh - Enables required repos, installs RPMS (so you get ansible) and enables and starts Docker engine.

2-awxbuild.sh - Builds AWX containers from github source and runs them.

## Setup

After cloning the repo...

```
cd automatey
./1-packages.sh 

```
