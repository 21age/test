#!/bin/bash

# Оновлюємо індекси пакетів системи
sudo apt update

# Встановлюємо OpenJDK 17, необхідний для роботи Jenkins
sudo apt install openjdk-17-jdk -y

# Встановлюємо Maven для управління залежностями та збіркою проектів
sudo apt install maven -y

# Завантажуємо Jenkins GPG ключ для перевірки підпису пакета Jenkins
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

# Додаємо офіційний репозиторій Jenkins в систему
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
/etc/apt/sources.list.d/jenkins.list > /dev/null

# Оновлюємо індекси пакетів з урахуванням нового репозиторію Jenkins
sudo apt-get update

# Встановлюємо Jenkins
sudo apt-get install jenkins -y

# Виводимо повідомлення про успішну установку
echo "Jenkins, OpenJDK 17, Maven successfully installed"
