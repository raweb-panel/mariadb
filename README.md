# Mariadb

---

- [X] Debian 12.
- [X] Ubuntu 24.04.

---

Debian/Ubuntu step 1 add repository:
```bash
apt update; apt-get -y upgrade; apt-get -y install wget apt-transport-https ca-certificates gnupg2 sudo
echo "deb [arch=amd64 trusted=yes] https://repo.raweb.al/ $(cat /etc/os-release | grep VERSION_CODENAME= | cut -d= -f2) main" | sudo tee /etc/apt/sources.list.d/raweb.list
```

Step 2 install mariadb:
```bash
sudo apt update; sudo apt install -y raweb-mariadb
```

---

## To-Do List

- [ ] Add support for Alma Linux 9.
- [ ] Custom build libs to avoid conflicts with system libs.

---