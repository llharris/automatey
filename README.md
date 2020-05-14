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


## What does what

1-packages.sh - Enables required repos, installs RPMS (so you get ansible) and enables and starts Docker engine.

2-awxbuild.sh - Builds AWX containers from github source and runs them.

## Setup

After cloning the repo...

```
cd automatey
./1-packages.sh 

```
