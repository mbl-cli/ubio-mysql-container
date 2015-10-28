#!/bin/bash

VOLUME_HOME="/var/lib/mysql"
CONF_FILE="/etc/mysql/my.cnf"
LOG="/var/log/mysql/error.log"

StartMySQL ()
{
  /usr/bin/mysqld_safe > /dev/null 2>&1 &

  LOOP_LIMIT=30
  echo "========================================================================" >> ${LOG}
  for (( i=0 ; ; i++ )); do
    if [ ${i} -eq ${LOOP_LIMIT} ]; then
      echo "Time out. Error log is shown as below:" >> ${LOG}
      exit 1
    fi
    echo "=> Waiting for confirmation of MySQL service startup, trying ${i}/${LOOP_LIMIT} ..." >> ${LOG}
    sleep 5
    mysql -uroot -e "status" > /dev/null 2>&1 && break
  done
  echo "========================================================================" >> ${LOG}
}

CreateMySQLUsers ()
{
  StartMySQL
  ADMIN=${EOL_DATABASE_ADMIN_USER}
  ADMIN_PASS=${EOL_DATABASE_ADMIN_PASSWORD}
  EOL_USER=${EOL_DATABASE_USER}
  EOL_USER_PASS=${EOL_DATABASE_PASSWORD}
  if [ "$EOL_DATABASE_REPLICATION_ROLE" == "slave" ]; then
    ADMIN=${EOL_SLAVE_ADMIN_USER}
    ADMIN_PASS=${EOL_SLAVE_ADMIN_PASSWORD}
    EOL_USER=${EOL_SLAVE_USER}
    EOL_USER_PASS=${EOL_SLAVE_PASSWORD}
  fi

  echo "========================================================================" >> ${LOG}
  echo "Creating '${ADMIN}' user ..." >> ${LOG}
  mysql -uroot -e "CREATE USER '${ADMIN}'@'%' IDENTIFIED BY '${ADMIN_PASS}'"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${ADMIN}'@'%' WITH GRANT OPTION"
  echo "Creating ${EOL_USER} user ..." >> ${LOG}
  mysql -uroot -e "CREATE USER '${EOL_USER}'@'%' IDENTIFIED BY '${EOL_USER_PASS}'"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON eol_production.* TO '${EOL_USER}'@'%' WITH GRANT OPTION"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON eol_logging_production.* TO '${EOL_USER}'@'%' WITH GRANT OPTION"

  echo "=> Done!" >> ${LOG}

  echo "You can now connect to this MySQL Server using:" >> ${LOG}
  echo "" >> ${LOG}
  echo "    mysql -u$ADMIN -p -h<host> -P<port>" >> ${LOG}
  echo ""
  echo "========================================================================" >> ${LOG}

  mysqladmin -uroot shutdown
}

if [[ ! -d $VOLUME_HOME/mysql ]]; then
  echo "========================================================================" >> ${LOG}
  echo "=> An empty or uninitialized MySQL volume is detected in $VOLUME_HOME" >> ${LOG}
  echo "=> Installing MySQL ..." >> ${LOG}
  if [ ! -f /usr/share/mysql/my-default.cnf ] ; then
    cp $CONF_FILE /usr/share/mysql/my-default.cnf
  fi
  mysql_install_db --user=mysql --ldata=/var/lib/mysql/
  # mysql_install_db > /dev/null 2>&1
  echo "=> Done!" >> ${LOG}
  echo "========================================================================" >> ${LOG}
  CreateMySQLUsers
else
  echo "=> Using an existing volume of MySQL" >> ${LOG}
fi

# Set MySQL REPLICATION - MASTER
if [ "${EOL_DATABASE_REPLICATION_ROLE}" == "master" ]; then
  echo "========================================================================" >> ${LOG}
  echo "=> Configuring MySQL replication as master ..." >> ${LOG}
  if [ ! -f $VOLUME_HOME/replication_configured ]; then
    echo "=> Starting MySQL ..." >> ${LOG}
    StartMySQL
    echo "=> Creating a log user ${EOL_REPLICATION_USER}:${EOL_REPLICATION_PASSWORD}"
    mysql -uroot -e "CREATE USER '${EOL_REPLICATION_USER}'@'%' IDENTIFIED BY '${EOL_REPLICATION_PASSWORD}'"
    mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO '${EOL_REPLICATION_USER}'@'%'"
    echo "=> Done!" >> ${LOG}
    mysqladmin -uroot shutdown
    touch $VOLUME_HOME/replication_configured
  else
    echo "=> MySQL replication master already configured, skip" >> ${LOG}
  fi
  echo "========================================================================" >> ${LOG}
fi

# Set MySQL REPLICATION - SLAVE
if [ "${EOL_DATABASE_REPLICATION_ROLE}" == "slave" ]; then
  echo "========================================================================" >> ${LOG}
  echo "=> Configuring MySQL replication as slave ..." >> ${LOG}
  if [ ! -f $VOLUME_HOME/replication_configured ]; then
    RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})" >> ${LOG}
    echo "=> Starting MySQL ..." >> ${LOG}
    StartMySQL
    echo "=> Setting master connection info on slave" >> ${LOG}
    mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='${EOL_DATABASE_HOST}',MASTER_USER='${EOL_REPLICATION_USER}',MASTER_PASSWORD='${EOL_REPLICATION_PASSWORD}',MASTER_PORT=${EOL_DATABASE_PORT}, MASTER_CONNECT_RETRY=30"
    echo "=> Done!" >> ${LOG}
    mysqladmin -uroot shutdown
    touch $VOLUME_HOME/replication_configured
  else
    echo "=> MySQL replicaiton slave already configured, skip" >> ${LOG}
  fi
  echo "========================================================================" >> ${LOG}
fi

chmod a+rx /
chown mysql:mysql /var/lib/mysql
chown mysql:mysql /var/log/mysql
tail -F $LOG &
exec mysqld_safe
