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
  ADMIN=${UBIO_DATABASE_ADMIN_USER}
  ADMIN_PASS=${UBIO_DATABASE_ADMIN_PASSWORD}
  UBIO_USER=${UBIO_DATABASE_USER}
  UBIO_USER_PASS=${UBIO_DATABASE_PASSWORD}
  if [ "$UBIO_DATABASE_REPLICATION_ROLE" == "slave" ]; then
    ADMIN=${UBIO_SLAVE_ADMIN_USER}
    ADMIN_PASS=${UBIO_SLAVE_ADMIN_PASSWORD}
    UBIO_USER=${UBIO_SLAVE_USER}
    UBIO_USER_PASS=${UBIO_SLAVE_PASSWORD}
  fi

  echo "========================================================================" >> ${LOG}
  echo "Creating '${ADMIN}' user ..." >> ${LOG}
  mysql -uroot -e "CREATE USER '${ADMIN}'@'%' IDENTIFIED BY '${ADMIN_PASS}'"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${ADMIN}'@'%' WITH GRANT OPTION"
  echo "Creating ${UBIO_USER} user ..." >> ${LOG}
  mysql -uroot -e "CREATE USER '${UBIO_USER}'@'%' IDENTIFIED BY '${UBIO_USER_PASS}'"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON eol_production.* TO '${UBIO_USER}'@'%' WITH GRANT OPTION"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON eol_logging_production.* TO '${UBIO_USER}'@'%' WITH GRANT OPTION"

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
if [ "${UBIO_DATABASE_REPLICATION_ROLE}" == "master" ]; then
  echo "========================================================================" >> ${LOG}
  echo "=> Configuring MySQL replication as master ..." >> ${LOG}
  if [ ! -f $VOLUME_HOME/replication_configured ]; then
    echo "=> Starting MySQL ..." >> ${LOG}
    StartMySQL
    echo "=> Creating a log user ${UBIO_REPLICATION_USER}:${UBIO_REPLICATION_PASSWORD}"
    mysql -uroot -e "CREATE USER '${UBIO_REPLICATION_USER}'@'%' IDENTIFIED BY '${UBIO_REPLICATION_PASSWORD}'"
    mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO '${UBIO_REPLICATION_USER}'@'%'"
    echo "=> Done!" >> ${LOG}
    mysqladmin -uroot shutdown
    touch $VOLUME_HOME/replication_configured
  else
    echo "=> MySQL replication master already configured, skip" >> ${LOG}
  fi
  echo "========================================================================" >> ${LOG}
fi

# Set MySQL REPLICATION - SLAVE
if [ "${UBIO_DATABASE_REPLICATION_ROLE}" == "slave" ]; then
  echo "========================================================================" >> ${LOG}
  echo "=> Configuring MySQL replication as slave ..." >> ${LOG}
  if [ ! -f $VOLUME_HOME/replication_configured ]; then
    RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})" >> ${LOG}
    echo "=> Starting MySQL ..." >> ${LOG}
    StartMySQL
    echo "=> Setting master connection info on slave" >> ${LOG}
    mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='${UBIO_DATABASE_HOST}',MASTER_USER='${UBIO_REPLICATION_USER}',MASTER_PASSWORD='${UBIO_REPLICATION_PASSWORD}',MASTER_PORT=${UBIO_DATABASE_PORT}, MASTER_CONNECT_RETRY=30"
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
