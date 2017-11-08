FROM ubuntu:16.04
MAINTAINER Tonny Gieselaar <tonny@devosverzuimbeheer.nl>

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get upgrade -y

# Stuff for networking and container management

RUN apt-get install -y openssh-server \
                       supervisor \
                       net-tools \
                       nano \
                       apt-utils wget \
                       dnsutils iputils-ping

# Stuff to build and install asterisk
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y build-essential \linux-headers-`uname -r` openssh-server apache2 mysql-server\
			  mysql-client bison flex curl sox\
			  libncurses5-dev libssl-dev libmysqlclient-dev mpg123 libxml2-dev libnewt-dev sqlite3\
			  libsqlite3-dev pkg-config automake libtool autoconf git unixodbc-dev uuid uuid-dev\
			  libasound2-dev libogg-dev libvorbis-dev libicu-dev libcurl4-openssl-dev libical-dev libneon27-dev libsrtp0-dev\
			  libspandsp-dev subversion libtool-bin python-dev

RUN apt-get install -y software-properties-common
RUN export LANG=C.UTF-8 && add-apt-repository -y ppa:ondrej/php
RUN apt-get update \
    && apt-get install -y \ 
	php5.6 php5.6-curl php5.6-cli php5.6-mysql php5.6-gd 

# Install ODBC driver alternative for libmyodbc (missing in Ubuntu 16.04

RUN wget https://dev.mysql.com/get/Downloads/Connector-ODBC/5.3/mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit.tar.gz
RUN tar -xvf 'mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit.tar.gz' \
    && cp mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit/lib/libmyodbc5* /usr/lib/x86_64-linux-gnu/odbc/ \
    && mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit/bin/myodbc-installer -d -a -n "MySQL" -t "DRIVER=/usr/lib/x86_64-linux-gnu/odbc/libmyodbc5w.so;" \
    && mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit/bin/myodbc-installer -s -a -c2 -n "test" -t "DRIVER=MySQL;SERVER=127.0.0.1;DATABASE=mysql;UID=root;PWD=123456"

#Install nodejs

RUN curl -sL https://deb.nodesource.com/setup_8.x | bash -
RUN apt-get install -y nodejs texinfo

#Install iksemel

RUN cd /usr/src && git clone https://github.com/meduketto/iksemel.git && cd /usr/src/iksemel && ./autogen.sh && ./configure && make && make install && ldconfig

#Install and configure asterisk
WORKDIR /usr/src
RUN wget http://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-current.tar.gz
RUN wget http://downloads.asterisk.org/pub/telephony/libpri/libpri-current.tar.gz
RUN wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-14-current.tar.gz
RUN wget -O jansson.tar.gz https://github.com/akheron/jansson/archive/v2.7.tar.gz

# Compile and Install jansson
RUN tar vxfz jansson.tar.gz && rm -f jansson.tar.gz
RUN cd jansson-* && autoreconf -i && ./configure && make && make install

#Compile and install Asterisk
RUN tar xvfz asterisk-14-current.tar.gz && rm -f asterisk-14-current.tar.gz
RUN cd asterisk-* && sh -c '/bin/echo -e "Y\n" |contrib/scripts/get_mp3_source.sh && contrib/scripts/install_prereq install \
	&& sh -c '/bin/echo -e "Y\n" | ./configure --with-pjproject-bundled && make && make install && make config && ldconfig \
        && update-rc.d -f asterisk remove

# Download freePBX 
RUN wget -O freepbx.tgz http://mirror.freepbx.org/modules/packages/freepbx/freepbx-14.0-latest.tgz

#Install apache php 5.60 modules

RUN apt-get update && apt-get install -y libapache2-mod-php5.6 \
		       php-pear \
		       php5.6-cli \
		       php5.6-common \
		       php5.6-mbstring \
		       php5.6-gd \
		       php5.6-intl \
		       php5.6-xml \ 
		       php5.6-mysql \
		       php5.6-mcrypt \
		       php5.6-zip

ADD config/asterisk.service /etc/systemd/system/
ADD scripts/init.sh /
ADD config/supervisord.conf /etc/supervisor/conf.d/
RUN chmod +x /init.sh

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

EXPOSE 80 5060 16384-16394
ENTRYPOINT ["/init.sh"]
CMD ["app:start"]
WORKDIR /

