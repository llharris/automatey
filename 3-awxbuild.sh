#!/bin/bash
source env.sh

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
source ~/.bashrc
nvm install 8
nvm use 8

mkdir -p ${AUTOMATEY_HOME}
cd ${AUTOMATEY_HOME}
git clone -b 11.2.0 https://github.com/ansible/awx
cd ${AUTOMATEY_HOME}/awx
git clone https://github.com/ansible/awx-logos
mkdir -p ${AUTOMATEY_HOME}/postgresql

sed -i "s:postgres_data_dir=/tmp/pgdocker:postgres_data_dir=${AUTOMATEY_HOME}/postgresql:g" ${AUTOMATEY_HOME}/awx/installer/inventory

sed -i 's:awx_official=false:awx_official=true:g' ${AUTOMATEY_HOME}/awx/installer/inventory

cd ${AUTOMATEY_HOME}/awx/installer

pip3 install --upgrade pip
pip3 install wheel
pip3 install docker-compose
pip3 install docker

#ansible-playbook -i inventory install.yml

