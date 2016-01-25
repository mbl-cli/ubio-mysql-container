MySQL Container
===============

Container for uBio MySQL databsases

Install
-------

It assumes to run from an SSD drive mounted on /opt/ubio

```
sudo mkdir -p /opt/ubio/backup
sudo mkdir /opt/ubio/mysql
sudo mkdir /opt/ubio/log
sudo mkdir /opt/ubio/config
cd /opt/ubio
sudo chown 301:301 -R mysql
sudo chown 301:301 -R log

Copy start/restart/stop scripts from script directory to
/usr/local/bin directory on the host

copy my.cnf and production.env to /opt/ubio/conf

run ubio-mysql-start script
```

Create databases:

Copy uBio backup `*.sql.gz` files to /opt/ubio/backup on the node

```
docker exec ubio-mysql /create-ubio-db.sh
```

