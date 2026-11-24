# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр                    | Значение                          |
|-----------------------------|-----------------------------------|
| Наименование                | devops-vm                         |
| Тип и версия гостевой ОС    | Linux / Ubuntu (64-bit)           |
| Дистрибутив                 | Ubuntu Server 24.04 LTS           |
| Объём оперативной памяти    | 2048 МБ                           |
| Количество ядер процессора  | 2                                 |
| Объём дискового накопителя  | 25 ГБ, динамически расширяемый    |

## 2. Сетевые интерфейсы

| Адаптер | Тип          | Адрес (типичный)   | Назначение                                      |
|---------|--------------|--------------------|-------------------------------------------------|
| 1       | NAT          | 10.0.2.15          | Доступ гостевой системы в Интернет (репозитории пакетов) |
| 2       | Host-only    | 192.168.56.101     | Доступ с хостовой системы к гостевой (веб-сервер, SSH) |

> Фактический адрес Host-only может отличаться. Узнать его: `ip -brief address`

## 3. Правило проброса портов

Настроено в VirtualBox для **адаптера 1 (NAT)**:

| Параметр                  | Значение     |
|---------------------------|--------------|
| Наименование правила      | ssh          |
| Протокол                  | TCP          |
| Адрес хостовой системы    | 127.0.0.1    |
| Порт хостовой системы     | 2222         |
| Адрес гостевой системы    | (пусто)      |
| Порт гостевой системы     | **2222**     |

> После изменения порта SSH в гостевой системе значение «Порт гостевой системы» изменено с 22 на 2222.

## 4. Учётные записи

| Имя     | Группы          | Способ аутентификации          | Примечание                              |
|---------|-----------------|--------------------------------|-----------------------------------------|
| student | sudo            | пароль (из установки)          | Создана при установке ОС                |
| devops  | sudo, docker*   | только по открытому ключу      | Основная учётная запись для работы      |

\* Группа `docker` добавляется в практической работе № 7.

- Закрытый ключ на хосте: `~/.ssh/devops_vm`
- Открытый ключ размещён в `~/.ssh/authorized_keys` пользователя `devops`
- Права: `~/.ssh` → 700, `authorized_keys` → 600

Конфигурация SSH-клиента на хосте (`~/.ssh/config`):
Host devops
HostName 127.0.0.1
Port 2222
User devops
IdentityFile ~/.ssh/devops_vm
IdentitiesOnly yes


## 5. Служба SSH

- **Порт прослушивания:** 2222
- **Файл основной конфигурации:** `/etc/ssh/sshd_config` (не изменяется)
- **Файл с параметрами hardening:** `/etc/ssh/sshd_config.d/99-hardening.conf`
- **Резервная копия:** `/etc/ssh/sshd_config.backup`

Содержимое `/etc/ssh/sshd_config.d/99-hardening.conf`:

Port 2222PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30AllowUsers devopsX11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2


Дополнительно:
- Юнит `ssh.socket` отключён (`systemctl disable --now ssh.socket`)
- Юнит `ssh.service` включён и используется
- Конфликтующие директивы `PasswordAuthentication yes` в других файлах `sshd_config.d/` закомментированы

Проверка действующей конфигурации:
```bash
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
```

## 6. Правила межсетевого экрана (UFW)Политики по умолчанию:
Incoming: deny
Outgoing: allow

Правила:
| Правило | Комментарий |
| --- | --- |
| 2222/tcp | LIMIT (rate-limited) SSH |
| 80/tcp | HTTP |
| 443/tcp | HTTPS |

Команды для восстановления:

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw enable

Проверка:

sudo ufw status verbose

## 7. Снимки состояния

| Наименование | Момент создания |
| --- | --- |
| 01-clean-install | После установки ОС и обновления пакетов |
| 02-keys-configured | После создания учётной записи devops и настройки ключей |
| 03-ssh-hardened | После hardening SSH (порт 2222, отключение паролей) |

## 8. Веб-сервер

| Параметр                              | Значение                                      |
|---------------------------------------|-----------------------------------------------|
| Пакет                                 | nginx                                         |
| Конфигурация ресурса                  | `/etc/nginx/sites-available/devops-site`      |
| Символическая ссылка                  | `/etc/nginx/sites-enabled/devops-site`        |
| Каталог ресурса                       | `/var/www/devops-site`                        |
| Владелец каталога                     | `devops:devops`                               |
| Права каталога                        | `755`                                         |
| Права файлов                          | `644`                                         |
| Сертификат                            | `/etc/ssl/certs/devops.crt` (права `644`)     |
| Закрытый ключ                         | `/etc/ssl/private/devops.key` (права `600`)   |
| Срок действия сертификата             | 365 дней                                      |

**Команда формирования сертификата:**

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```