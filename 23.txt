#!/bin/bash

# Резервне копіювання оригінальних конфігураційних файлів
cp /etc/sysctl.conf /root/sysctl.conf_backup
cp /etc/security/limits.conf /root/sec_limit.conf_backup

# Налаштування системних параметрів
cat <<EOT > /etc/sysctl.conf
# Максимальна кількість пам'яті мап для Elasticsearch/SonarQube
vm.max_map_count=262144
# Максимальна кількість відкритих файлів для системи
fs.file-max=65536
EOT

# Налаштування обмежень для користувача sonarqube
cat <<EOT > /etc/security/limits.conf
# Обмеження для користувача sonarqube
sonarqube   -   nofile   65536
sonarqube   -   nproc    4096
EOT

# Оновлення списків пакетів
sudo apt-get update -y

# Встановлення Java (необхідна для SonarQube)
sudo apt-get install openjdk-11-jdk -y

# Перевірка версії Java
java -version

# Додавання ключа для PostgreSQL
wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -

# Додавання репозиторію PostgreSQL до списку джерел
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'

# Оновлення списків пакетів і установка PostgreSQL
sudo apt update
sudo apt install postgresql postgresql-contrib -y

# Увімкнення та запуск служби PostgreSQL
sudo systemctl enable postgresql.service
sudo systemctl start postgresql.service

# Змінюємо пароль для користувача postgres
sudo sh -c "echo 'postgres:admin123' | chpasswd"

# Створення користувача для SonarQube
sudo -u postgres createuser sonar

# Налаштування пароля для користувача sonar
sudo -u postgres psql -c "ALTER USER sonar WITH ENCRYPTED PASSWORD 'admin123';"

# Створення бази даних для SonarQube
sudo -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonar;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube to sonar;"

# Перезавантаження служби PostgreSQL для застосування змін
systemctl restart postgresql

# Створення каталогу для SonarQube
sudo mkdir -p /sonarqube/
cd /sonarqube/

# Завантаження та розпакування SonarQube
sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-8.3.0.34182.zip
sudo apt-get install zip -y
sudo unzip -o sonarqube-8.3.0.34182.zip -d /opt/
sudo mv /opt/sonarqube-8.3.0.34182/ /opt/sonarqube

# Створення групи та користувача для SonarQube
sudo groupadd sonar
sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar
sudo chown sonar:sonar /opt/sonarqube/ -R

# Резервне копіювання конфігураційного файлу SonarQube
cp /opt/sonarqube/conf/sonar.properties /root/sonar.properties_backup

# Налаштування конфігураційного файлу SonarQube
cat <<EOT > /opt/sonarqube/conf/sonar.properties
# Налаштування підключення до бази даних
sonar.jdbc.username=sonar
sonar.jdbc.password=admin123
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
# Налаштування веб-сервера SonarQube
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.log.level=INFO
sonar.path.logs=logs
EOT

# Налаштування служби SonarQube для systemd
cat <<EOT > /etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOT

# Оновлення systemd для нових служб
systemctl daemon-reload

# Увімкнення служби SonarQube при завантаженні системи
systemctl enable sonarqube.service

# Встановлення Nginx для проксування запитів до SonarQube
sudo apt-get install nginx -y
# Видалення стандартних конфігурацій Nginx
rm -rf /etc/nginx/sites-enabled/default
rm -rf /etc/nginx/sites-available/default

# Налаштування конфігурації Nginx для SonarQube
cat <<EOT > /etc/nginx/sites-available/sonarqube
server {
    listen      80;
    server_name sonarqube.groophy.in;

    access_log  /var/log/nginx/sonar.access.log;
    error_log   /var/log/nginx/sonar.error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass  http://127.0.0.1:9000;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_redirect off;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
}
EOT

# Створення символічного посилання для активації конфігурації
ln -s /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube

# Увімкнення Nginx для запуску при завантаженні системи
systemctl enable nginx.service

# Дозволити трафік на порти 80 (HTTP), 9000 (SonarQube) та 9001 (SonarQube Web API)
sudo ufw allow 80,9000,9001/tcp

# Повідомлення про перезавантаження системи
echo "System reboot in 30 sec"
sleep 30
reboot
