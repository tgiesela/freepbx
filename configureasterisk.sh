#!/bin/bash
docker build . -t tgiesela/asterisk:v0.1

read -p "Password for mysql root user (leave empty for existing DB): " MYSQL_PASSWORD
if [ -z ${MYSQL_PASSWORD} ]; then
    MYSQLPASSWORD=""
else
    MYSQLPASSWORD="${MYSQL_PASSWORD}"
fi

read -p "Custom network name : " CUSTOMNETWORKNAME

read -p "Ip-address mysql server: " MYSQL_IP_ADDRESS

read -p "Fixed ip-address asterisk: " FIXED_IP_ADDRESS
if [ -z $FIXED_IP_ADDRESS ]; then
    FIXED_IP_ADDRESS=;
else
    FIXED_IP_ADDRESS=--ip=${FIXED_IP_ADDRESS};
fi

docker rm -f asterisk
docker run --name asterisk \
--net=tginet \
-p 8080:80 \
-p 5060:5060/udp \
-p 15160:5160/udp \
--hostname=asterisk \
${FIXED_IP_ADDRESS} \
-e MYSQLSERVER=${MYSQL_IP_ADDRESS} \
-e MYSQLUSER=root \
-e MYSQLPASSWORD=${MYSQLPASSWORD} \
-d tgiesela/asterisk:v0.1

