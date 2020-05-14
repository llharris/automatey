# Automatey

Automatey aims to get you quickly set up with a RHEL 7 server running a bunch of useful automation tools in docker containers. It assumes you've got a reasonable RHEL 7 build that's registered with subscription-manager. The build I'm working on has also been hardened to CIS 2.2 standards...more or less.

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

For Consul we should build our own image which incorporates the config.json along with the certificates and keys required for TLS to be enabled.

# OTHER NOTES

From messing about with this, here is some of the other stuff we already know or which may prove useful in future.

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
