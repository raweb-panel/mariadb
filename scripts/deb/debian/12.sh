#!/bin/bash
set -e
CORES=${BUILD_CORES:-$(nproc)}

if [ -z "$UPLOAD_USER" ] || [ -z "$UPLOAD_PASS" ]; then
    echo "Missing UPLOAD_USER or UPLOAD_PASS"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
echo "Updating..." && apt-get update -y > /dev/null 2>&1
echo "Upgrading..." && apt-get upgrade -y > /dev/null 2>&1
echo "Installing curl..." && apt-get install curl -y > /dev/null 2>&1
# -------------------------------------------------------------
DEB_PACKAGE_NAME="raweb-mariadb"
DEB_ARCH="amd64"
DEB_DIST="$BUILD_CODE"
# -------------------------------------------------------------
VERSION_URL="https://raw.githubusercontent.com/MariaDB/server/refs/heads/$SQL_VERSION_MAJOR/VERSION"
VERSION_CONTENT=$(curl -fsSL "$VERSION_URL")
DEB_VERSION="$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_MAJOR | cut -d= -f2).$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_MINOR | cut -d= -f2).$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_PATCH | cut -d= -f2)"
DEB_PACKAGE_FILE_NAME="${DEB_PACKAGE_NAME}_${DEB_VERSION}_${DEB_DIST}_${DEB_ARCH}.deb"
DEB_REPO_URL="https://$DOMAIN/$UPLOAD_USER/$BUILD_REPO/${DEB_DIST}/"
if curl -s "$DEB_REPO_URL" | grep -q "$DEB_PACKAGE_FILE_NAME"; then
    echo "✅ Package $DEB_PACKAGE_FILE_NAME already exists. Skipping build."
    exit 0
fi
# -------------------------------------------------------------
echo "Installing requirements..." && apt-get install -y build-essential cmake libssl-dev libpcre2-dev bison libreadline-dev zlib1g-dev libpcre3-dev libncurses5-dev libncursesw5-dev libaio-dev libcurl4-openssl-dev pkg-config git sudo wget zip unzip jq rsync >/dev/null 2>&1

git clone --depth=1 --branch $SQL_VERSION_MAJOR https://github.com/MariaDB/server.git > /dev/null 2>&1
cd server/; git submodule update --init --recursive > /dev/null 2>&1
id raweb 2>/dev/null || useradd -m raweb

cmake . \
  -DCMAKE_INSTALL_PREFIX=/raweb/apps/mariadb/core \
  -DSYSCONFDIR=/raweb/apps/mariadb/core/etc \
  -DMYSQL_DATADIR=/raweb/apps/mariadb/data \
  -DMYSQL_UNIX_ADDR=/raweb/apps/mariadb/data/mariadb.sock \
  -DMYSQL_TCP_PORT=13306 \
  -DWITH_SSL=system \
  -DWITH_READLINE=1 \
  -DWITH_ZLIB=system \
  -DWITH_INNODB_DISALLOW_WRITES=ON \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DWITH_PCRE=system \
  -DPKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig \
  -DWITHOUT_TOKUDB=1 \
  -DWITH_WSREP=OFF > /dev/null 2>&1

make -j${CORES} > /dev/null 2>&1
make install > /dev/null 2>&1

mkdir -p /raweb/apps/mariadb/data
chown -R raweb: /raweb/apps/mariadb/data
cat > /raweb/apps/mariadb/core/my.cnf <<EOF
[client]
socket=/raweb/apps/mariadb/data/mariadb.sock

[mysqld]
basedir=/raweb/apps/mariadb/core
datadir=/raweb/apps/mariadb/data
socket=/raweb/apps/mariadb/data/mariadb.sock
pid-file=/raweb/apps/mariadb/data/mysqld.pid
user=raweb
bind-address=127.0.0.1
port=13306
log-error=/raweb/apps/mariadb/data/mysqld.log
EOF

mkdir -p /etc/systemd/system
cat > /etc/systemd/system/raweb-mariadb.service <<EOF
[Unit]
Description=RAWEB MariaDB Server
After=network.target

[Service]
ExecStart=/raweb/apps/mariadb/core/bin/mariadbd \\
  --defaults-file=/raweb/apps/mariadb/core/my.cnf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

DEB_VERSION="$(/raweb/apps/mariadb/core/bin/mariadbd --version | head -n1 | awk '{print $3}' | cut -d'-' -f1)"
DEB_BUILD_DIR="$GITHUB_WORKSPACE/debbuild"
DEB_ROOT="$DEB_BUILD_DIR/${DEB_PACKAGE_NAME}_${DEB_VERSION}_${DEB_ARCH}"

rm -rf "$DEB_BUILD_DIR"
mkdir -p "$DEB_ROOT/raweb/apps/mariadb"
mkdir -p "$DEB_ROOT/etc/systemd/system"
mkdir -p "$DEB_ROOT/DEBIAN"

cp -a /raweb/apps/mariadb/core "$DEB_ROOT/raweb/apps/mariadb/"
cp /etc/systemd/system/raweb-mariadb.service "$DEB_ROOT/etc/systemd/system/"

cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: $DEB_PACKAGE_NAME
Version: $DEB_VERSION
Section: database
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Raweb Panel <cd@julio.al>
Description: Custom MariaDB $DEB_VERSION for Raweb Panel.
Depends: libssl3, libreadline8, zlib1g, libpcre3, libncurses6, libaio1, libcurl4, libpcre2-dev
EOF

cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
mkdir -p /raweb; id raweb &>/dev/null || useradd -m -d /raweb raweb; chown -R raweb:raweb /raweb

# Only initialize if data directory is empty
if [ ! -d /raweb/apps/mariadb/data/mysql ] || [ -z "$(ls -A /raweb/apps/mariadb/data/mysql 2>/dev/null)" ]; then
    echo "Initializing MariaDB data directory..."
    mkdir -p /raweb/apps/mariadb/data
    chown -R raweb: /raweb/apps/mariadb/data
    sudo -u raweb /raweb/apps/mariadb/core/scripts/mariadb-install-db \
      --basedir=/raweb/apps/mariadb/core \
      --datadir=/raweb/apps/mariadb/data \
      --user=raweb
fi

    systemctl daemon-reload || true
    systemctl enable raweb-mariadb || true
    systemctl restart raweb-mariadb || true
    for i in {1..60}; do
      if /raweb/apps/mariadb/core/bin/mariadb \
          --socket=/raweb/apps/mariadb/data/mariadb.sock \
          -u root -e "SELECT 1;" &>/dev/null; then
        echo "MariaDB is up."
        break
      fi
      echo "Waiting for MariaDB to be ready..."
      sleep 1
    done
    # Generate random root password
    ROOT_PASSWORD=$(openssl rand -base64 32)

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "DROP USER 'raweb'@'localhost';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "CREATE DATABASE raweb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "CREATE USER 'root'@'127.0.0.1' IDENTIFIED BY '$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "CREATE USER 'root'@'%' IDENTIFIED BY '$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \
      --socket=/raweb/apps/mariadb/data/mariadb.sock \
      -u root \
      -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';" 2>/dev/null || true

    cat > /raweb/.my.cnf <<MYCNF
[client]
user=root
password=$ROOT_PASSWORD
host=127.0.0.1
port=13306
socket=/raweb/apps/mariadb/data/mariadb.sock
MYCNF

    chmod 600 /raweb/.my.cnf
    if [ -f /raweb/web/panel/.env ]; then
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$ROOT_PASSWORD/" /raweb/web/panel/.env
        echo ".env file updated with new MariaDB root password."
    fi
    echo "$(date): MariaDB Root Password: $ROOT_PASSWORD" >> /raweb/apps/mariadb/data/root_password.log
    chmod 600 /raweb/apps/mariadb/data/root_password.log

exit 0
EOF

chmod 755 "$DEB_ROOT/DEBIAN"
chmod 755 "$DEB_ROOT/DEBIAN/control"
chmod 755 "$DEB_ROOT/DEBIAN/postinst"

DEB_PACKAGE_FILE="$DEB_BUILD_DIR/${DEB_PACKAGE_NAME}_${DEB_VERSION}_${BUILD_CODE}_${DEB_ARCH}.deb"
dpkg-deb --build "$DEB_ROOT" "$DEB_PACKAGE_FILE"

echo "$UPLOAD_PASS" > $GITHUB_WORKSPACE/.rsync
chmod 600 $GITHUB_WORKSPACE/.rsync
rsync -avz --password-file=$GITHUB_WORKSPACE/.rsync $DEB_PACKAGE_FILE rsync://$UPLOAD_USER@$DOMAIN/$BUILD_FOLDER/$BUILD_REPO/$BUILD_CODE/
