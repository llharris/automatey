#!/bin/bash

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
source ~/.bashrc
nvm install 8
nvm use 8

mkdir -p /opt/automatey
cd /opt/automatey
git clone https://github.com/ansible/awx
cd /opt/automatey/awx
git clone https://github.com/ansible/awx-logos
mkdir -p /opt/automatey/postgresql

sed -i 's:postgres_data_dir=/tmp/pgdocker:postgres_data_dir=/opt/automatey/postgresql:g' /opt/automatey/awx/installer/inventory

sed -i 's:awx_official=false:awx_official=true:g' /opt/automatey/awx/installer/inventory

cd /opt/automatey/awx/installer

pip3 install --upgrade pip
pip3 install docker-compose
pip3 install docker

ansible-playbook -i inventory install.yml

