MySQL Container
===============

Container for EOL MySQL databsases

Install
-------

It assumes to run from an SSD drive mounted on /opt/ubio

```
sudo mkdir -p /opt/ubio/backup
sudo mkdir /opt/ubio/mysql
sudo mkdir /opt/ubio/log
cd /opt/ubio
sudo chown 301:301 -R mysql
sudo chown 301:301 -R log
docker run -d \
  -v /opt/ubio/mysql:/var/lib/mysql \
  -v /opt/ubio/log:/var/log/mysql \
  -v /opt/ubio/backup:/opt/ubio/backup \
  -p 3306:3306 \
  --name ubio-mysql mblab/ubio-mysql
```

Create databases:

Copy uBio backup `*.sql.gz` files to /opt/ubio/backup on the node

```
docker exec ubio-mysql /create-ubio-db.sh
```

