#!/bin/bash
echo -ne "Setting up repos and installing packages, this might take a while...\n"
for repo in rhel-7-server-ansible-2.9-rpms \
            rhel-7-server-extras-rpms \
            rhel-7-server-optional-rpms \
            rhel-7-server-rh-common-rpms \
            rhel-7-server-rpms \
            rhel-7-server-supplementary-rpms \
            rhel-server-rhscl-7-rpms \
            rhel-server-rhscl-7-eus-rpms
do
repo_enabled=$(yum repolist enabled | awk -F/ '{print $1}' | grep -c ${repo})
if [[ $repo_enabled -eq 1 ]]; then
  echo -ne "Repo $repo already enabled, skipping.\n"
else
  echo -ne "Enabling repo $repo.\n"
  subscription-manager repos --enable=$repo
fi
done

yum makecache fast
yum install docker wget ansible make automake git gcc mlocate python-devel python27-python-devel sysstat net-tools bind-utils python3 python3-pip libselinux-python3 tree screen unzip policycoreutils-python -y
yum upgrade -y
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y

systemctl enable docker && systemctl start docker
