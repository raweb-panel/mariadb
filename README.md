# Mariadb

---

- [X] Debian 12.
- [X] Ubuntu 24.04.

---

Debian/Ubuntu step 1 add repository:
```bash
apt update; apt-get -y upgrade; apt-get -y install wget apt-transport-https ca-certificates gnupg2 sudo
curl -fsSL https://repo.raweb.al/install.sh | sudo bash
```

Step 2 install mariadb:
```bash
sudo apt update; sudo apt install -y raweb-mariadb
```

Follow https://repo.raweb.al for how to add repo, if you don't want to execute install.sh url.

---

## To-Do List

- [ ] Add support for Alma Linux 9.
- [ ] Custom build libs to avoid conflicts with system libs.

---