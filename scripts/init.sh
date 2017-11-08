#!/bin/bash

set -x

info () {
    echo "[INFO] $@"
}

configureODBC () {

# Configure Asterisk database in MYSQL

    info "get list of databases"
    DB=$(echo "show databases;" | mysql -h ${MYSQLSERVER} -p${MYSQLPASSWORD} --user=${MYSQLUSER} | grep asteriskcdrdb)
echo DB=${DB}
    if [ -z $DB ] ; then
        info "create database"
        mysql -h ${MYSQLSERVER} -p${MYSQLPASSWORD} --user=${MYSQLUSER} << EOFDBCREATION
	create database asterisk; 
	create database asteriskcdrdb;
	create user asterisk;
	GRANT ALL PRIVILEGES ON asterisk.* TO asterisk@'%' IDENTIFIED BY '';
	GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO asterisk@'%' IDENTIFIED BY '';
	flush privileges;
EOFDBCREATION
    fi

# Configure ODBC
    cat >> /etc/odbcinst.ini << EOF
[MySQL]
Description = ODBC for MySQL
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmyodbc5w.so
Setup = /usr/lib/x86_64-linux-gnu/odbc/libodbcmyS.so
FileUsage = 1
EOF

    cat >> /etc/odbc.ini << EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
driver=MySQL
server=${MYSQLSERVER}
database=asteriskcdrdb
Port=3306
address=${MYSQLSERVER}:3306
user=${MYSQLUSER}
password=${MYSQLPASSWORD}
  
EOF

}

setupcdrdb() {

    sed -i "s/CDRDBHOST=.*$/CDRDBHOST=${MYSQLSERVER}/g" /etc/amportal.conf
    sed -i "s/CDRDBNAME=.*$/CDRDBNAME=asteriskcdrdb/g" /etc/amportal.conf
    sed -i "s/CDRDBPASS=.*$/CDRDBPASS=${MYSQLPASSWORD}/g" /etc/amportal.conf
    sed -i "s/CDRDBTYPE=.*$/CDRDBTYPE=mysql/g" /etc/amportal.conf
    sed -i "s/CDRDBUSER=.*$/CDRDBUSER=${MYSQLUSER}/g" /etc/amportal.conf


    sed -i "s/;hostname=database.host.name/hostname=${MYSQLSERVER}/g" /etc/asterisk/cdr_mysql.conf
    sed -i "s/;dbname=asteriskcdrdb/dbname=asteriskcdrdb/g" /etc/asterisk/cdr_mysql.conf
    sed -i "s/;table=cdr/table=cdr/g" /etc/asterisk/cdr_mysql.conf
    sed -i "s/;password=password/password=${MYSQLPASSWORD}/g" /etc/asterisk/cdr_mysql.conf
    sed -i "s/;user=asteriskcdruser/user=${MYSQLUSER}/g" /etc/asterisk/cdr_mysql.conf
    sed -i "s/;port=3306/port=3306/g" /etc/asterisk/cdr_mysql.conf

}
extendhelptext() {
#   the parking module uses a helptext longer than 250 chars
    mysql -h ${MYSQLSERVER} -p${MYSQLPASSWORD} --user=${MYSQLUSER} << EOFINPUT
    ALTER TABLE `asterisk`.`featurecodes` CHANGE COLUMN `helptext` `helptext` VARCHAR(350) NOT NULL DEFAULT '' ;
EOFINPUT
}

appSetup () {

    useradd -m asterisk 
    chown asterisk. /var/run/asterisk
    chown -R asterisk. /etc/asterisk
    chown -R asterisk. /var/{lib,log,spool}/asterisk
    chown -R asterisk. /usr/lib/asterisk
    rm -rf /var/www/html

# Configure apache: A few small modifications to Apache.
    sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/5.6/apache2/php.ini 
    sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/5.6/apache2/php.ini
    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig 
    sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf 
    sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
    a2enmod rewrite
    service apache2 restart

    configureODBC

#    sed -i 's/#AST_USER="asterisk"/AST_USER="asterisk"/g' /etc/default/asterisk
#    sed -i 's/#AST_GROUP="asterisk"/AST_GROUP="asterisk"/g' /etc/default/asterisk
#    chown -R asterisk:asterisk /var/spool/asterisk /var/run/asterisk /etc/asterisk /var/{lib,log,spool}/asterisk /usr/lib/asterisk
#    chmod -R 777 asterisk:asterisk /var/spool/asterisk /var/run/asterisk /etc/asterisk /var/{lib,log,spool}/asterisk /usr/lib/asterisk

    cd /usr/src/asterisk-*
    make samples
    sed -i 's/\[directories\].*$/\[directories\]/g' /etc/asterisk/asterisk.conf

    cd /usr/src/
    tar xfz freepbx.tgz
    cd freepbx 
    # Issue with setCommand in FWHelper class. We remove it.

    ./start_asterisk start

    sed -i "s/$amp_conf\['AMPDBHOST'\] = 'localhost';/$amp_conf['AMPDBHOST'] = '${MYSQLSERVER}';/g" installlib/installcommand.class.php
    sed -i "s/'localhost' IDENTIFIED BY '/'%' IDENTIFIED BY '/g" installlib/installcommand.class.php
    sed -i "s/'0000-00-00 00:00:00'/'0001-01-01 00:00:00'/g" installlib/SQL/cdr.sql
    sed -i "s/0000-00-00 00:00:00/0001-01-01 00:00:00/g" module.xml

    chmod -R 777 /var/www/html/
    sed -i "s/$db_host : \"localhost\"/$db_host : \"${MYSQLSERVER}\"/g" amp_conf/htdocs/admin/modules/cel/Cel.class.php
    sed -i "s/$db_host : \"localhost\"/$db_host : \"${MYSQLSERVER}\"/g" amp_conf/htdocs/admin/modules/cdr/install.php
    sed -i "s/\"rtpstart\" => \"10000\"/\"rtpstart\" => \"16384\"/g" amp_conf/htdocs/admin/modules/sipsettings/Sipsettings.class.php
    sed -i "s/\"rtpend\" => \"20000\"/\"rtpend\" => \"16394\"/g" amp_conf/htdocs/admin/modules/sipsettings/Sipsettings.class.php
    ./install -f -n -vvv --dbuser=${MYSQLUSER} --dbpass=${MYSQLPASSWORD}
    # First install only partially installs and then breaks on permission errors
    # We set the security and run the install again
    ./install -f -n --dbuser=${MYSQLUSER} --dbpass=${MYSQLPASSWORD}
    chown -R asterisk:asterisk /var/www/html/

#   Limit ports used by asterisk, docker can't handle this number of ports
    sed -i "s/rtpstart=10000/rtpstart=16384/g" /etc/asterisk/rtp_additional.conf
    sed -i "s/rtpend=20000/rtpend=16394/g" /etc/asterisk/rtp_additional.conf

    extendhelptext
    fwconsole ma update calendar timeconditions ringgroups queues callforward parking ringgroups

    sed -i 's/Require all denied/Require all granted/' /var/www/html/admin/.htaccess 
    service apache2 restart

    touch /etc/asterisk/.alreadysetup
}

appStart () {
    [ -f /etc/asterisk/.alreadysetup ] && echo "Skipping setup..." || appSetup

    # Start the services
    service apache2 restart
    fwconsole restart
    /usr/bin/supervisord
}

appHelp () {
	echo "Available options:"
	echo " app:start          - Starts all services needed for Samba AD DC"
	echo " app:setup          - First time setup."
	echo " app:help           - Displays the help"
	echo " [command]          - Execute the specified linux command eg. /bin/bash."
}

case "$1" in
	app:start)
		appStart
		;;
	app:setup)
		appSetup
		;;
	app:help)
		appHelp
		;;
	*)
		if [ -x $1 ]; then
			$1
		else
			prog=$(which $1)
			if [ -n "${prog}" ] ; then
				shift 1
				$prog $@
			else
				appHelp
			fi
		fi
		;;
esac

exit 0
