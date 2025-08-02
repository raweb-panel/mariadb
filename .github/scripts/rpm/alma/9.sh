#!/bin/bash
# ====================================================================================
if [ -z "$UPLOAD_USER" ] || [ -z "$UPLOAD_PASS" ]; then
    echo "Missing UPLOAD_USER or UPLOAD_PASS"
    exit 1
fi
echo "Alma 9 is not working properly, anyone is welcome to test build and PR a fix"
exit 0
# ====================================================================================
TOTAL_CORES=$(nproc)
if [[ "$BUILD_CORES" =~ ^[0-9]+$ ]] && [ "$BUILD_CORES" -le 100 ]; then
  CORES=$(( TOTAL_CORES * BUILD_CORES / 100 ))
  [ "$CORES" -lt 1 ] && CORES=1
else
  CORES=${BUILD_CORES:-$TOTAL_CORES}
fi
# ====================================================================================
dnf -y update > /dev/null 2>&1
dnf install --allowerasing -y epel-release curl > /dev/null 2>&1
# ====================================================================================
RPM_PACKAGE_NAME="raweb-mariadb"
RPM_ARCH="x86_64"
RPM_DIST="$BUILD_CODE"
# ====================================================================================
VERSION_URL="https://raw.githubusercontent.com/MariaDB/server/refs/heads/$SQL_VERSION_MAJOR/VERSION"
VERSION_CONTENT=$(curl -fsSL "$VERSION_URL")
RPM_VERSION="$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_MAJOR | cut -d= -f2).$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_MINOR | cut -d= -f2).$(echo "$VERSION_CONTENT" | grep MYSQL_VERSION_PATCH | cut -d= -f2)"
RPM_PACKAGE_FILE_NAME="${RPM_PACKAGE_NAME}-${SQL_PACK_VERSION}-${RPM_DIST}.${RPM_ARCH}.rpm"
RPM_REPO_URL="https://$DOMAIN/$UPLOAD_USER/$BUILD_REPO/${RPM_DIST}/"
if curl -s "$RPM_REPO_URL" | grep -q "$RPM_PACKAGE_FILE_NAME"; then
    echo "✅ Package $RPM_PACKAGE_FILE_NAME already exists. Skipping build."
    exit 0
fi
# ====================================================================================
echo "Installing requirements..." && dnf install --allowerasing -y \
    make gcc gcc-c++ cmake openssl-devel pcre2-devel bison readline-devel zlib-devel \
    pcre-devel ncurses-devel libaio-devel libcurl-devel pkgconfig git sudo wget curl zip unzip jq rsync \
    rpm-build rpmdevtools > /dev/null 2>&1
# ====================================================================================
if ! command -v cmake >/dev/null 2>&1; then
    ln -sf /usr/bin/cmake3 /usr/local/bin/cmake
fi
# ====================================================================================
git clone --depth=1 --branch $SQL_VERSION_MAJOR https://github.com/MariaDB/server.git > /dev/null 2>&1
cd server/; git submodule update --init --recursive > /dev/null 2>&1
id raweb 2>/dev/null || useradd -m raweb
# ====================================================================================
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
  -DPKG_CONFIG_PATH=/usr/lib64/pkgconfig \
  -DWITHOUT_TOKUDB=1 \
  -DWITH_WSREP=OFF > /dev/null 2>&1
# ====================================================================================
make -j${CORES} > /dev/null 2>&1
make install > /dev/null 2>&1
# ====================================================================================
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
# ====================================================================================
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
# ====================================================================================
RPM_VERSION="$(/raweb/apps/mariadb/core/bin/mariadbd --version | head -n1 | awk '{print $3}' | cut -d'-' -f1)"
RPM_BUILD_DIR="$GITHUB_WORKSPACE/rpmbuild"
RPM_ROOT="$RPM_BUILD_DIR/BUILDROOT/${RPM_PACKAGE_NAME}-${SQL_PACK_VERSION}.${RPM_ARCH}"
# ====================================================================================
rm -rf "$RPM_BUILD_DIR"
mkdir -p "$RPM_BUILD_DIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "$RPM_ROOT/raweb/apps/mariadb"
mkdir -p "$RPM_ROOT/etc/systemd/system"
# ====================================================================================
cp -a /raweb/apps/mariadb/core "$RPM_ROOT/raweb/apps/mariadb/"
cp /etc/systemd/system/raweb-mariadb.service "$RPM_ROOT/etc/systemd/system/"
# ====================================================================================
cat > "$RPM_BUILD_DIR/SPECS/${RPM_PACKAGE_NAME}.spec" <<EOF
Name: $RPM_PACKAGE_NAME
Version: $SQL_PACK_VERSION
Release: $BUILD_CODE
Summary: Custom MariaDB for Raweb Panel
License: GPL
BuildArch: ${RPM_ARCH}
Group: Applications/Databases
Requires: openssl readline zlib pcre ncurses libaio curl pcre2

%description
Custom MariaDB $SQL_PACK_VERSION for Raweb Panel.

%post
#!/bin/bash
set -e
mkdir -p /raweb; id raweb &>/dev/null || useradd -m -d /raweb raweb; chown -R raweb:raweb /raweb

# Only initialize if data directory is empty
if [ ! -d /raweb/apps/mariadb/data/mysql ] || [ -z "\$(ls -A /raweb/apps/mariadb/data/mysql 2>/dev/null)" ]; then
    echo "Initializing MariaDB data directory..."
    mkdir -p /raweb/apps/mariadb/data
    chown -R raweb: /raweb/apps/mariadb/data
    sudo -u raweb /raweb/apps/mariadb/core/scripts/mariadb-install-db \\
      --basedir=/raweb/apps/mariadb/core \\
      --datadir=/raweb/apps/mariadb/data \\
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
    ROOT_PASSWORD=\$(openssl rand -base64 32)

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "DROP USER 'raweb'@'localhost';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "CREATE DATABASE raweb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "CREATE USER 'root'@'127.0.0.1' IDENTIFIED BY '\$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '\$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "CREATE USER 'root'@'%' IDENTIFIED BY '\$ROOT_PASSWORD';" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    /raweb/apps/mariadb/core/bin/mariadb \\
      --socket=/raweb/apps/mariadb/data/mariadb.sock \\
      -u root \\
      -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '\$ROOT_PASSWORD';" 2>/dev/null || true

    cat > /raweb/.my.cnf <<MYCNF
[client]
user=root
password=\$ROOT_PASSWORD
host=127.0.0.1
port=13306
socket=/raweb/apps/mariadb/data/mariadb.sock
MYCNF

    chmod 600 /raweb/.my.cnf
    if [ -f /raweb/web/panel/.env ]; then
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\$ROOT_PASSWORD/" /raweb/web/panel/.env
        echo ".env file updated with new MariaDB root password."
    fi
    echo "\$(date): MariaDB Root Password: \$ROOT_PASSWORD" >> /raweb/apps/mariadb/data/root_password.log
    chmod 600 /raweb/apps/mariadb/data/root_password.log

exit 0

%files
/raweb/apps/mariadb/core
/etc/systemd/system/raweb-mariadb.service

%changelog
* $(date "+%a %b %d %Y") Raweb Panel <cd@julio.al> - $SQL_PACK_VERSION
- Custom MariaDB build for Raweb Panel
EOF
# ====================================================================================
echo "%__make         /usr/bin/make -j $CORES" > ~/.rpmmacros
rpmbuild \
  --define "_topdir $RPM_BUILD_DIR" \
  --define "_smp_mflags -j$CORES" \
  --buildroot "$RPM_ROOT" \
  -bb "$RPM_BUILD_DIR/SPECS/${RPM_PACKAGE_NAME}.spec"
RPM_PACKAGE_FILE="$RPM_BUILD_DIR/RPMS/x86_64/${RPM_PACKAGE_NAME}-${SQL_PACK_VERSION}-${BUILD_CODE}.x86_64.rpm"
# ====================================================================================
echo "$UPLOAD_PASS" > $GITHUB_WORKSPACE/.rsync; chmod 600 $GITHUB_WORKSPACE/.rsync
rsync -avz --password-file=$GITHUB_WORKSPACE/.rsync $RPM_PACKAGE_FILE rsync://$UPLOAD_USER@$DOMAIN/$BUILD_FOLDER/$BUILD_REPO/$BUILD_CODE/; rm -rf $GITHUB_WORKSPACE/.rsync
# ====================================================================================