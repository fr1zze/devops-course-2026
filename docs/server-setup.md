# Конфигурация виртуальной машины devops-vm

Практическая работа № 5. Удалённый сервер и безопасный доступ: SSH, sudo, UFW, DNS.
Документ описывает полученную конфигурацию и команды её восстановления после отката на снимок `01-clean-install`.
Команды Linux выполняются в Ubuntu; команды с пометкой PowerShell выполняются в Windows.
Пароли и содержимое закрытых ключей в документ и репозиторий не помещаются.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Средство виртуализации | Oracle VirtualBox |
| ОС хоста | Windows |
| ОС гостя | Ubuntu Server 24.04.5 LTS, x86_64 |
| Имя виртуальной машины | devops-vm |
| Короткое имя узла | devops-vm |
| Полное имя узла | devops-vm.devops.local |
| Оперативная память | Около 2 ГиБ; команда `free -h` показывает 1.9Gi |
| Виртуальные процессоры | 2; подтверждено `nproc` |
| Диск | `/dev/sda`, 25G по `lsblk` |
| Раздел /boot | `/dev/sda2`, 2G |
| Раздел для LVM | `/dev/sda3`, 23G |
| Корневой логический том | `ubuntu--vg-ubuntu--lv`, 11.5G, точка монтирования `/` |
| Swap | 2.2Gi по `free -h` |

Размер корневого тома меньше полного диска: в системе применяется LVM. Для выполнения этой работы увеличивать том не требовалось.

Проверка параметров:

```bash
free -h
nproc
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Интерфейс Ubuntu | Адрес | Назначение |
| --- | --- | --- | --- |
| Адаптер 1: NAT | enp0s3 | 10.0.2.15/24 | Доступ в Интернет и SSH через проброс портов |
| Адаптер 2: Host-only | enp0s8 | 192.168.56.101/24 | Прямая связь Windows с гостевой системой |

Адрес Windows в сегменте Host-only: `192.168.56.1`, подтверждён полем SRC в журнале UFW.
Адреса получаются по DHCP. Если адрес Host-only изменится, запись Windows hosts необходимо привести в соответствие с новым адресом.

Оба адаптера включены в VirtualBox; кабель подключён. Для Host-only выбрана сеть виртуального адаптера хоста.

Восстановление настроек Ubuntu при необходимости:

```bash
sudo netplan set ethernets.enp0s3.dhcp4=true
sudo netplan set ethernets.enp0s8.dhcp4=true
sudo netplan set ethernets.enp0s8.dhcp4-overrides.use-routes=false
sudo netplan apply
ip -brief address
```

Параметр `use-routes=false` запрещает принимать маршруты DHCP с Host-only; выход в Интернет сохраняется через NAT.
Изменения `netplan set` сохраняются в YAML-файлах каталога `/etc/netplan/`.

## 3. Правило проброса портов

VirtualBox: «Настроить → Сеть → Адаптер 1 (NAT) → Дополнительно → Проброс портов».

| Параметр | Итоговое значение |
| --- | --- |
| Имя правила | ssh |
| Протокол | TCP |
| IP хоста | 127.0.0.1 |
| Порт хоста | 2222 |
| IP гостя | Поле не заполняется |
| Порт гостя | 2222 |

В снимке `01-clean-install` использовался проброс `127.0.0.1:2222 → гость:22`.
При восстановлении первоначально подключаются через него; после смены порта службы SSH меняют порт гостя в правиле с 22 на 2222.
Порт хоста остаётся 2222.

## 4. Учётные записи

| Пользователь | UID | Назначение и доступ |
| --- | --- | --- |
| sa | 1000 | Исходная учётная запись импортированного образа; итоговый SSH-доступ запрещён правилом AllowUsers |
| student | 1001 | Учебная учётная запись, состоит в sudo; может входить через консоль VirtualBox |
| devops | 1002 | Основная учётная запись администрирования, состоит в sudo; SSH-вход по ключу Ed25519 |

Вход root по SSH запрещён. Повышение привилегий выполняется через `sudo`.
Отключение пароля для SSH не отменяет пароль учётной записи, запрашиваемый `sudo`.

После отката на `01-clean-install` войти как student и создать devops:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Задать пароль devops; дополнительные сведения Full Name, Room Number и телефоны можно оставить пустыми.
Если пользователь уже существует, повторно создавать его не требуется.

Пара ключей хранится в Windows:

- закрытый ключ: `C:\Users\user\.ssh\devops_vm`;
- открытый ключ: `C:\Users\user\.ssh\devops_vm.pub`;
- комментарий ключа: `devops-vm-key`.

Существующий ключ при откате ВМ сохраняется на Windows и используется повторно.
Если пары ещё нет, создать её в PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
ssh-keygen -t ed25519 -C "devops-vm-key" -f "$env:USERPROFILE\.ssh\devops_vm"
```

До отключения парольной аутентификации передать открытый ключ из PowerShell:

```powershell
Get-Content "$env:USERPROFILE\.ssh\devops_vm.pub" | ssh devops@127.0.0.1 -p 2222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Ввести пароль devops. Затем проверить вход:

```powershell
ssh -i "$env:USERPROFILE\.ssh\devops_vm" -o IdentitiesOnly=yes -p 2222 devops@127.0.0.1
```

В Ubuntu проверить права:

```bash
stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys
```

Ожидаются `700 /home/devops/.ssh` и `600 /home/devops/.ssh/authorized_keys`.

## 5. Служба SSH

Основной файл: `/etc/ssh/sshd_config`.
Резервная копия основного файла: `/etc/ssh/sshd_config.backup`.
Изменённые параметры размещены в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Действующее значение `KbdInteractiveAuthentication` также равно `no`; оно проверено командой `sshd -T`.

Восстановление файлов:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

Вставить приведённую выше конфигурацию и сохранить файл.

В образе присутствовал `/etc/ssh/sshd_config.d/50-cloud-init.conf` со строкой `PasswordAuthentication yes`.
Она имела приоритет над файлом 99-hardening.conf. Перед изменением создана копия `50-cloud-init.conf.backup`.
Для устранения конфликта строка закомментирована:

```text
#PasswordAuthentication yes
```

Команды для восстановления этого исправления:

```bash
sudo cp /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/50-cloud-init.conf.backup
sudo nano /etc/ssh/sshd_config.d/50-cloud-init.conf
```

Проверить синтаксис и действующие параметры до перезапуска:

```bash
sudo sshd -t
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|maxauthtries|allowusers) '
```

Ожидаются port 2222, permitrootlogin no, passwordauthentication no, kbdinteractiveauthentication no, maxauthtries 3 и allowusers devops.
Существующий SSH-сеанс оставить открытым до проверки нового подключения.

Отключить активацию SSH через сокет и включить обычную службу:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Служба должна слушать `0.0.0.0:2222` и `[::]:2222`.
Теперь изменить порт гостя в правиле VirtualBox на 2222 и проверить вход в отдельном окне PowerShell.

Файл клиента Windows `C:\Users\user\.ssh\config` содержит блок:

```text
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Имя файла — `config`, без расширения `.txt`. Остальные блоки этого файла сохраняются.

Проверки из PowerShell:

```powershell
ssh devops
ssh -p 2222 root@127.0.0.1
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
```

Первая команда должна выполнять вход по ключу. Две последние должны завершаться отказом.
В журнале зарегистрирован отказ root: учётная запись не перечислена в AllowUsers.

```bash
sudo journalctl -u ssh --since "10 min ago" --no-pager
```

### Локальное имя

В Windows файлу `C:\Windows\System32\drivers\etc\hosts` добавлена запись:

```text
192.168.56.101 devops.local
```

Редактирование и проверки из PowerShell, запущенного от имени администратора:

```powershell
notepad C:\Windows\System32\drivers\etc\hosts
ipconfig /flushdns
ping -n 2 devops.local
ssh -i "$env:USERPROFILE\.ssh\devops_vm" -o IdentitiesOnly=yes -p 2222 devops@devops.local
```

Перед подтверждением нового ключа хоста сверить отпечаток с выводом в консоли Ubuntu:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

На сервере короткое имя установлено командой:

```bash
sudo hostnamectl set-hostname devops-vm
sudo nano /etc/hosts
```

В `/etc/hosts` строка локального имени имеет вид:

```text
127.0.1.1 devops-vm.devops.local devops-vm
```

Остальные строки файла сохранены. Проверка `hostname -f` выводит `devops-vm.devops.local`.
Записи hosts являются локальными сопоставлениями имён; публичная DNS-зона не создавалась.

## 6. Правила межсетевого экрана

UFW активен и включается при загрузке. Журналирование: medium.
Политики: deny incoming, allow outgoing, deny routed.

| Назначение | Порт | Итоговое правило |
| --- | --- | --- |
| SSH с ограничением частоты подключений | 2222/tcp | LIMIT IN |
| HTTP | 80/tcp | ALLOW IN |
| HTTPS | 443/tcp | ALLOW IN |

Правила действуют для IPv4 и IPv6. Старое разрешение 22/tcp удалено.

Последовательность восстановления после исходного снимка:

```bash
sudo ufw status verbose
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
```

Подтвердить `y`. Проверить новое подключение `ssh devops` в отдельном окне.
В уже открытом SSH-сеансе заменить обычное разрешение на LIMIT и удалить оставшееся правило порта 22:

```bash
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw delete allow 22/tcp
sudo ufw logging medium
sudo ufw status verbose
```

Если при повторном выполнении команда удаления сообщает об отсутствии правила, проверить итоговый перечень: нужное правило могло быть удалено раньше.

Проверка закрытого порта из PowerShell Windows:

```powershell
curl.exe --noproxy "*" -m 3 http://192.168.56.101:8080
```

Получен тайм-аут. Блокировка подтверждена журналом ядра Ubuntu:

```bash
sudo journalctl -k --since "10 min ago" --no-pager | grep 'UFW BLOCK' | grep 'DPT=8080' | tail -5
```

| Поле подтверждённой записи | Значение |
| --- | --- |
| IN | enp0s8 |
| SRC | 192.168.56.1 — Windows |
| DST | 192.168.56.101 — Ubuntu |
| PROTO | TCP |
| DPT | 8080 — заблокированный порт назначения |

## 7. Снимки состояния и контроль конфигурации

| Снимок | Момент создания |
| --- | --- |
| 01-clean-install | После подготовки ОС, учётной записи student, сети и первоначального SSH-доступа |
| 02-keys-configured | После создания devops, установки открытого ключа и настройки команды ssh devops |
| 03-ssh-hardened | После усиления защиты SSH, смены порта и проверки запрещённых подключений |

Снимок 03 создан до настройки UFW, полного имени узла и скрипта аудита; эти изменения находятся в текущем состоянии машины.
Перед учебным откатом сохранить scripts/audit.sh и docs/server-setup.md в репозитории GitLab, чтобы они были доступны независимо от состояния ВМ.

Рабочий каталог на ВМ: `/home/devops/devops-course-2026`.
Скрипт: `scripts/audit.sh`. Настоящий документ: `docs/server-setup.md`.

Запуск в Ubuntu:

```bash
cd ~/devops-course-2026
chmod +x scripts/audit.sh
./scripts/audit.sh
echo $?
```

Скрипт проверяет запрет root, отключение парольного SSH-входа, нестандартный порт, MaxAuthTries=3, активность UFW и запрет входящих соединений по умолчанию.

| Состояние файлов конфигурации | Ожидаемый результат |
| --- | --- |
| MaxAuthTries 3, остальные параметры соответствуют работе | 6 проверок пройдено, 0 не пройдено; код 0 |
| Временная замена MaxAuthTries 3 на MaxAuthTries 10 | 5 проверок пройдено, 1 не пройдена; код 1 |
| Возврат MaxAuthTries 3 | Снова 6 проверок пройдено; код 0 |

При намеренном изменении MaxAuthTries служба SSH не перезапускается: скрипт читает параметры с диска через sshd -T.
После теста обязательно вернуть MaxAuthTries 3 и повторить синтаксическую проверку и аудит.
Аудит проверяет перечисленные параметры конфигурации; фактический порт и возможность нового подключения дополнительно подтверждаются командами ss и ssh.
## 8. Веб-сервер

Установлен пакет nginx. Служба включена в автозагрузку:

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

### Конфигурация сайта

- Файл конфигурации: `/etc/nginx/sites-available/devops-site`.
- Ссылка на него: `/etc/nginx/sites-enabled/devops-site`.
- Стандартный сайт `/etc/nginx/sites-enabled/default` отключён удалением ссылки.
- Имя сайта: `devops.local`.
- HTTP, порт 80: перенаправление на HTTPS с кодом 301.
- HTTPS, порт 443: публикация статических файлов.
- Разрешённые версии TLS: 1.2 и 1.3.
- Каталог сайта: `/var/www/devops-site`.
- Владелец и группа: `devops:devops`.
- Права каталогов: 755, файлов: 644.
- Главная страница: `index.html`.
- Страница ошибки 404: `404.html`.
- Журнал запросов HTTPS: `/var/log/nginx/devops-site.access.log`.
- Журнал ошибок HTTPS: `/var/log/nginx/devops-site.error.log`.

Рабочие процессы Nginx выполняются от имени www-data.
Они могут читать файлы сайта, но не изменять их.

Проверка и применение конфигурации:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Сертификат HTTPS

Используется самоподписанный сертификат RSA 2048 бит для devops.local.
Срок действия — 365 дней, до 29 октября 2027 года.

- Сертификат: `/etc/ssl/certs/devops.crt`, владелец root:root, права 644.
- Закрытый ключ: `/etc/ssl/private/devops.key`, владелец root:root, права 600.
- CN: devops.local.
- SAN: DNS:devops.local.

Команда создания нового сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"

sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Команда приведена для восстановления; повторное выполнение создаёт новую пару ключа и сертификата.

### Доставка сайта

Исходные страницы находятся в каталоге site/ репозитория.
Скрипт scripts/deploy.sh запускается на хосте через WSL.
Он проверяет наличие index.html и чистоту рабочего дерева Git,
передаёт файлы через rsync по SSH и устанавливает права D755,F644.

После передачи выполняется HTTPS-проверка с сертификатом
/root/devops.crt в WSL. Режим --dry-run только показывает изменения.

Снимок ВМ после настройки HTTPS: 04-nginx-https.

## 9. Контейнеризация

### Установка Docker

Docker Engine Community установлен из официального APT-репозитория
https://download.docker.com/linux/ubuntu.

Установлены пакеты docker-ce, docker-ce-cli, containerd.io,
docker-buildx-plugin и docker-compose-plugin.

Версия Docker Engine: 29.9.2.
Версия Docker Compose: 5.6.1.

Ранее установленный Docker из Snap остановлен и отключён:

```bash
sudo snap stop --disable docker
```

Официальная служба Docker включена в автозагрузку:

```bash
sudo systemctl enable --now docker
```

Пользователь devops добавлен в группу docker:

```bash
sudo usermod -aG docker devops
```

После изменения групп необходимо заново подключиться по SSH.
Проверка работы без sudo:

```bash
docker version
docker compose version
docker run --rm hello-world
```

### Расположение проекта

Исходные файлы находятся в каталоге app репозитория.
На сервере проект размещён в /home/devops/app.

Для переноса файлов из PowerShell Windows, из корня репозитория:

```powershell
ssh devops "mkdir -p ~/app"
scp .\app\app.py .\app\requirements.txt .\app\Dockerfile .\app\.dockerignore .\app\.env.example .\app\docker-compose.yml devops:app/
```

Здесь devops — SSH-псевдоним сервера из предыдущих разделов.

### Переменные окружения

Файл /home/devops/app/.env создаётся только на сервере.
Он принадлежит пользователю devops и имеет права 600.
В Git хранится только шаблон .env.example.

При первоначальной настройке:

```bash
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
```

При повторном развёртывании существующий .env сохраняется.
Пароль в нём должен соответствовать паролю уже созданной базы.

### Запуск, сеть и хранение данных

```bash
cd ~/app
docker compose up -d --build
docker compose ps
```

Сервисы app и db используют сеть app_backend.
Приложение обращается к PostgreSQL по имени db.
Запуск приложения ожидает состояния healthy у базы данных.

Порт приложения опубликован только на 127.0.0.1:5000.
Порт PostgreSQL 5432 на сервере не опубликован.

Данные PostgreSQL хранятся в именованном томе app_db_data,
подключённом к /var/lib/postgresql/data внутри контейнера.

docker compose down сохраняет том и данные.
docker compose down -v удаляет том и базу данных.
Для обычной остановки флаг -v не используется.

### Обратный прокси-сервер

В HTTPS-блок файла /etc/nginx/sites-available/devops-site добавлено:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Статическая страница в /var/www/devops-site сохранена.
Настройки сертификата и HTTPS описаны в предыдущем разделе.

Проверка и применение конфигурации:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Приложение доступно по https://devops.local/app/.
Проверка работоспособности: https://devops.local/app/health.

При остановке приложения Nginx возвращает 502.
Причина фиксируется в /var/log/nginx/devops-site.error.log.
Восстановление:

```bash
cd ~/app
docker compose start app
```

Создан снимок VM: 05-docker-compose.
