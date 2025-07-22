# Mariadb

- Debian 12/11.
- Ubuntu 24.04/22.04.
- AlmaLinux 9/8.

Debian/Ubuntu.
```bash
apt update; apt-get -y upgrade; apt-get -y install wget apt-transport-https ca-certificates gnupg2 sudo
echo "deb [arch=amd64 trusted=yes] https://repo.julio.al/ $(cat /etc/os-release | grep VERSION_CODENAME= | cut -d= -f2) main" | sudo tee /etc/apt/sources.list.d/raweb.list
sudo apt update; sudo apt install -y raweb-mariadb

```

AlmaLinux 9.
```bash
dnf -y update; dnf install -y wget ca-certificates gnupg2 epel-release sudo

sudo tee /etc/yum.repos.d/raweb.repo << 'EOF'
[raweb-alma9]
name=Raweb Panel Repository for AlmaLinux 9
baseurl=https://repo.julio.al/rpm/alma9/x86_64
enabled=1
gpgcheck=0
EOF

# Install
sudo dnf makecache; sudo dnf -y install raweb-mariadb
```

AlmaLinux 8.
```bash
dnf -y update; dnf install -y wget ca-certificates gnupg2 epel-release sudo

sudo tee /etc/yum.repos.d/raweb.repo << 'EOF'
[raweb-alma8]
name=Raweb Panel Repository for AlmaLinux 8
baseurl=https://repo.julio.al/rpm/alma8/x86_64
enabled=1
gpgcheck=0
EOF

# Install
sudo dnf makecache; sudo dnf -y install raweb-mariadb
```

---

## To-Do List

- [ ] Custom build libs to avoid conflicts with system libs.
