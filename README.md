# Оффлайн установка Docker, Registry, Kubernetes и Flannel

## 📋 Описание
Данный набор скриптов позволяет выполнить полную офлайн установку следующих компонентов на сервер без доступа к интернету:

| Компонент | Версия |
|-----------|--------|
| Docker CE | 29.4.0 |
| Docker Compose | 2.29.7 |
| Docker Registry | 2 (локальный) |
| Kubernetes | 1.33.10 |
| Flannel (CNI) | v0.26.1 (host-gw) |
| containerd | 2.2.2 |
| CNI plugins | 1.6.2 |
| crictl | v1.33.0 |

> **Особенности:**
> - Все Docker образы загружаются в локальный registry (`localhost:5000`)
> - Kubernetes использует образы из локального registry
> - Flannel работает в режиме `host-gw` (не требует VXLAN)
> - Автоматическое определение сетевого интерфейса

## 📁 Структура пакета

```bash
all-offline-YYYYMMDD/
├── packages/                    # RPM пакеты и бинарные файлы
│   ├── docker-ce-*.rpm
│   ├── docker-ce-cli-*.rpm
│   ├── containerd.io-*.rpm
│   ├── docker-buildx-plugin-*.rpm
│   ├── docker-compose-plugin-*.rpm
│   ├── kubeadm-*.rpm
│   ├── kubelet-*.rpm
│   ├── kubectl-*.rpm
│   ├── socat-*.rpm
│   ├── conntrack-tools-*.rpm
│   ├── ebtables-*.rpm
│   ├── ethtool-*.rpm
│   ├── ipset-*.rpm
│   ├── iptables-nft-*.rpm
│   ├── docker-compose-linux-x86_64
│   ├── cni-plugins-linux-amd64-*.tgz
│   └── crictl-*.tar.gz
├── images/                      # Docker образы (.tar)
│   ├── k8s-core-images.tar      # Образы Kubernetes
│   ├── flannel-images.tar       # Образ Flannel
│   ├── flannel-cni-images.tar   # Образ CNI плагина Flannel
│   └── registry-2.tar           # Образ Docker Registry
├── manifests/                   # YAML манифесты
│   └── kube-flannel.yml
├── registry-config/             # Конфигурация Registry
│   └── config.yml
├── install-all.sh               # Главный установочный скрипт (master)
├── install-worker.sh            # Установка worker узла (интерактивный)
├── install-worker-auto.sh       # Установка worker узла (автоматический)
└── clean-all.sh                 # Полная очистка системы
```
## 🚀 Предварительная подготовка
Этап 0: Подготовка на машине с интернетом
```bash
# Установка Docker на подготовительной машине
dnf install -y docker-ce docker-ce-cli containerd.io

# Запуск Docker
systemctl enable --now docker

# Опционально: аутентификация в репозитории образов docker (если нужно)
docker login
```
## 🚀 Ход работы
Этап 1: Подготовка на машине с интернетом
```bash
# 1. Скачать скрипт prepare-all-offline.sh
# 2. Дать права на выполнение
chmod +x prepare-all-offline.sh

# 3. Запустить подготовку (требуется Docker и доступ в интернет)
./prepare-all-offline.sh
```
Что происходит на этом этапе:
| Шаг | Действие |
|-----|----------|
| 1   | Добавление репозиториев Kubernetes и Docker |
| 2   | Скачивание RPM пакетов всех компонентов |
| 3   | Скачивание бинарных файлов (Docker Compose, CNI plugins, crictl) |
| 4   | Скачивание Docker образов (K8s, Flannel, Registry) |
| 5   | Создание конфигурации для Registry |
| 6   | Скачивание манифеста Flannel |
| 7   | Создание установочных скриптов (master, worker, очистка) |
| 8   | Упаковка всего в архив /tmp/all-offline-YYYYMMDD.tar.gz |

## Этап 2: Перенос архива на целевую ВМ
```bash
# Используйте scp, USB-накопитель или другой способ
scp /tmp/all-offline-YYYYMMDD.tar.gz root@target-vm:/opt/
```
## Этап 3: Установка Master узла (без интернета)
```bash
# 1. Распаковать архив
cd /opt
tar -xzf all-offline-YYYYMMDD.tar.gz
cd all-offline-*

# 2. Дать права на выполнение
chmod +x install-all.sh

# 3. Запустить установку (от root)
./install-all.sh
```
Что происходит на этапе установки master узла:

| Шаг | Действие |
|-----|----------|
| 1   | Предварительная настройка (отключение swap, SELinux, firewall) |
| 2   | Автоматическое определение IP адреса сервера |
| 3   | Установка crictl |
| 4   | Установка Docker и Docker Compose из RPM пакетов |
| 5   | Загрузка образа Docker Registry |
| 6   | Запуск локального Docker Registry на порту 5000 |
| 7   | Загрузка всех образов (K8s, Flannel) в локальный Registry |
| 8   | Установка Kubernetes (kubeadm, kubelet, kubectl) |
| 9   | Установка CNI плагинов в /opt/cni/bin |
| 10  | Настройка containerd (cgroup, sandbox image, registry mirror) |
| 11  | Инициализация Kubernetes кластера через kubeadm init |
| 12  | Автоматическое определение сетевого интерфейса |
| 13  | Установка Flannel CNI (режим host-gw) |
| 14  | Установка kube-proxy |
| 15  | Настройка маршрутизации и iptables |
| 16  | Снятие taints с master узла |
| 17  | Перезапуск CoreDNS |
| 18  | Проверка работоспособности |

## ✅ Проверка установки master узла
После завершения скрипта выполните:
```bash
# Статус узлов
kubectl get nodes

# Статус подов в системном namespace
kubectl get pods -n kube-system

# Статус Flannel
kubectl get pods -n kube-flannel

# Список образов в локальном registry
curl http://localhost:5000/v2/_catalog

# Статус Docker Registry
docker ps | grep registry
```
Ожидаемый результат:
```bash
# kubectl get nodes
NAME              STATUS   ROLES           AGE   VERSION
master-node       Ready    control-plane   5m    v1.33.10

# kubectl get pods -n kube-system
NAME                                      READY   STATUS    RESTARTS   AGE
coredns-xxx                               1/1     Running   0          2m
etcd-master-node                          1/1     Running   0          5m
kube-apiserver-master-node                1/1     Running   0          5m
kube-controller-manager-master-node       1/1     Running   0          5m
kube-proxy-xxx                            1/1     Running   0          5m
kube-scheduler-master-node                1/1     Running   0          5m

# kubectl get pods -n kube-flannel
NAME                    READY   STATUS    RESTARTS   AGE
kube-flannel-ds-xxx     1/1     Running   0          1m

# curl http://localhost:5000/v2/_catalog
{"repositories":["coredns","etcd","flannel","flannel-cni-plugin","kube-apiserver","kube-controller-manager","kube-proxy","kube-scheduler","pause","registry"]}
```
## 🔧 Присоединение worker узлов
### На master узле получите join-команду:
```bash
kubeadm token create --print-join-command
```
Пример вывода:
```text
kubeadm join 192.168.1.100:6443 --token abc123.def456 --discovery-token-ca-cert-hash sha256:...
```
### Вариант 1: Интерактивная установка worker
```bash
# Скопируйте архив с master узла на worker
scp /tmp/all-offline-*.tar.gz root@worker-ip:/opt/

# На worker узле
cd /opt
tar -xzf all-offline-*.tar.gz
cd all-offline-*
chmod +x install-worker.sh

# Запустите установку
./install-worker.sh

# Введите IP master узла при запросе
# Затем выполните join команду, полученную с master
```
### Вариант 2: Автоматическая установка worker
```bash
# Скопируйте архив с master узла на worker
scp /tmp/all-offline-*.tar.gz root@worker-ip:/opt/

# На worker узле
cd /opt
tar -xzf all-offline-*.tar.gz
cd all-offline-*
chmod +x install-worker-auto.sh

# Запустите с параметрами
./install-worker-auto.sh <master-ip> 'kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>'
```
Что делает скрипт worker узла
| Шаг | Действие |
|-----|----------|
| 1   | Предварительная настройка (swap, SELinux, firewall) |
| 2   | Настройка /etc/hosts (добавление master узла) |
| 3   | Установка crictl |
| 4   | Установка Docker и Docker Compose |
| 5   | Установка Kubernetes (kubeadm, kubelet, kubectl) |
| 6   | Установка CNI плагинов |
| 7   | Настройка containerd (cgroup, sandbox image, registry mirror) |
| 8   | Присоединение к кластеру через kubeadm join |

### Проверка после установки worker
На master узле выполните:
```bash
kubectl get nodes
```
| Узел     | Статус | Роль           | Возраст | Версия    |
|----------|--------|----------------|---------|-----------|
| master   | Ready  | control-plane  | 10m     | v1.33.10  |
| worker1  | Ready  | \<none\>       | 2m      | v1.33.10  |
| worker2  | Ready  | \<none\>       | 2m      | v1.33.10  |

## 🔄 Полная очистка системы
Если что-то пошло не так или нужно переустановить:
```bash
# Запустите скрипт очистки (входит в архив)
chmod +x clean-all.sh
./clean-all.sh

# Или выполните ручную очистку
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /root/.kube
rm -rf /etc/cni/net.d /opt/cni/bin
docker stop docker-registry && docker rm docker-registry
rm -rf /opt/registry/data
systemctl restart containerd docker kubelet

# Рекомендуется перезагрузить сервер
reboot
```
## ❗ Возможные проблемы и решения
| Проблема | Решение |
|----------|---------|
| docker: command not found на этапе подготовки | Установите Docker на машине с интернетом: `dnf install -y docker-ce` |
| IP не определился автоматически | Скрипт автоматически определяет IP через несколько методов. Если не помогло - задайте вручную: `export MASTER_IP=ваш_ип && ./install-all.sh` |
| connection refused при kubectl get nodes | Проверьте: `export KUBECONFIG=/etc/kubernetes/admin.conf` |
| CoreDNS в статусе ContainerCreating | Проверьте установку Flannel: `kubectl get pods -n kube-flannel` |
| Registry не доступен | Проверьте: `docker ps \| grep registry`, перезапустите: `docker restart docker-registry` |
| Flannel в статусе CrashLoopBackOff | Проверьте интерфейс: `ip link show`. Скрипт автоматически определяет интерфейс, но может потребоваться ручная настройка |
| kube-proxy в статусе CrashLoopBackOff | Скрипт использует admin.conf вместо kubelet.conf. Если проблема осталась - проверьте логи: `kubectl logs -n kube-system kube-proxy-xxx` |
| containerd не запускается | Проверьте конфиг: `cat /etc/containerd/config.toml`. Скрипт создает правильную конфигурацию |

## 📊 Версии компонентов
| Компонент | Версия |
|-----------|--------|
| Kubernetes | 1.33.10 |
| Docker CE | 29.4.0 |
| Docker Compose | 2.29.7 |
| containerd | 2.2.2 |
| Flannel | v0.26.1 |
| Flannel CNI plugin | v1.6.0-flannel1 |
| CNI plugins | 1.6.2 |
| crictl | v1.33.0 |
| etcd | 3.5.21-0 |
| CoreDNS | 1.12.0 |
| pause | 3.10 |

## 📝 Дополнительная информация

Автоматическое определение интерфейса
- Скрипт автоматически определяет сетевой интерфейс в следующем порядке:
- Интерфейс маршрута по умолчанию (ip route get default)
- Первый не-loopback интерфейс из ip link show
- Первый интерфейс из /sys/class/net/
- Значение по умолчанию: ens192

Режим работы Flannel

Скрипт использует Flannel в режиме host-gw (host gateway), который:
- Не требует VXLAN туннелей
- Работает быстрее на физических серверах
- Требует прямого L2 соединения между узлами
- Использует стандартную маршрутизацию

## Сервис Kubernetes API
Скрипт добавляет специальное правило iptables для доступа к API серверу:
```bash
iptables -t nat -A OUTPUT -d 10.96.0.1 -p tcp --dport 443 -j DNAT --to-destination ${MASTER_IP}:6443
```
### Сохранение join команды

Для удобства, join команда выводится в конце установки master узла. Сохраните её для последующего добавления worker узлов.

```bash
# Пример вывода в конце установки:
# Для добавления worker узлов используйте команду:
# kubeadm token create --print-join-command
```
## 📋 Скрипты в составе пакета
| Скрипт | Назначение | Использование |
|--------|------------|---------------|
| install-all.sh | Полная установка master узла | `./install-all.sh` |
| install-worker.sh | Интерактивная установка worker узла | `./install-worker.sh` (запрашивает IP master) |
| install-worker-auto.sh | Автоматическая установка worker узла | `./install-worker-auto.sh <MASTER_IP> '<JOIN_COMMAND>'` |
| clean-all.sh | Полная очистка системы | `./clean-all.sh` |

## 🐛 Диагностика проблем
```bash
# Статус узлов
kubectl get nodes -o wide

# Все поды во всех namespace
kubectl get pods --all-namespaces

# Статус сервисов
systemctl status kubelet containerd docker

# Логи kubelet
journalctl -u kubelet -n 50 --no-pager

# Логи containerd
journalctl -u containerd -n 50 --no-pager
```
## Проверка сетевой connectivity
```bash
# Проверка интерфейсов
ip link show
ip addr show
ip route show

# Проверка iptables правил
iptables -t nat -L -n | head -20
iptables -L -n | head -20

# Проверка доступа к API серверу
curl -k https://127.0.0.1:6443/version
curl -k https://${MASTER_IP}:6443/version

# Проверка доступа к registry
curl http://localhost:5000/v2/_catalog
```
## Проверка Flannel
```bash
# Статус подов Flannel
kubectl get pods -n kube-flannel

# Логи Flannel
kubectl logs -n kube-flannel -l app=flannel --tail=50

# Проверка конфигурации CNI
cat /etc/cni/net.d/10-flannel.conflist
ls -la /opt/cni/bin/flannel

# Проверка созданного интерфейса
ip link show flannel.1
```
## 📌 Важные замечания

#### 1. **Режим Flannel host-gw:**
- Требует прямого L2 соединения между узлами
- Не работает через роутеры (требуется L2 доступ)
- Для многосетевой конфигурации измените Backend на vxlan
#### 2. Изменение Backend Flannel:
```bash
# Если нужен VXLAN вместо host-gw
kubectl edit configmap -n kube-flannel kube-flannel-cfg
# Измените Type с "host-gw" на "vxlan"
kubectl delete pods -n kube-flannel --all
```
#### 3. Статический IP для узлов:
- Рекомендуется настроить статические IP адреса на всех узлах
- Используйте nmcli или настройте в /etc/sysconfig/network-scripts/
#### 4. Сохранение join команды:
- Токен действителен 24 часа
- Для создания нового токена: kubeadm token create --print-join-command
#### 5. Безопасность:
- Скрипт отключает SELinux и firewall для упрощения установки
- Для production рекомендуется настроить их после установки

## 📞 Получение помощи
Если возникли проблемы:
1. Проверьте логи: journalctl -u kubelet -n 100 --no-pager
2. Проверьте статус подов: kubectl describe pod -n kube-system <pod-name>
3. Проверьте конфигурацию containerd: cat /etc/containerd/config.toml
4. Убедитесь что интерфейс определен правильно: ip route show

### Документация актуальна для версий:

- Kubernetes: 1.33.10
- Docker: 29.4.0
- containerd: 2.2.2
- Flannel: v0.26.1
- Дата создания: $(date +%Y-%m-%d)

## 💻 Требования к операционной системе

### Поддерживаемые ОС

| Операционная система | Версия | Архитектура | glibc | Статус |
|:---------------------|:-------|:------------|:------|:-------|
| **AlmaLinux** | 10.x | x86_64 | 2.39 | ✅ Полностью поддерживается |
| **Rocky Linux** | 10.x | x86_64 | 2.39 | ✅ Полностью поддерживается |
| **RHEL** (Red Hat Enterprise Linux) | 10.x | x86_64 | 2.39 | ✅ Полностью поддерживается |
| **CentOS Stream** | 10 | x86_64 | 2.39 | ✅ Полностью поддерживается |
| **Fedora** | 40, 41 | x86_64 | 2.38+ **?** | ⚠️ Требует проверки |
| **Debian** | 12+ | x86_64 | 2.36+ **?** | ⚠️ Требует проверки |
| **Ubuntu** | 24+ | x86_64 | 2.35+ **?** | ⚠️ Требует проверки |
| **RedOS** | 8+ | x86_64 | 2.36 | ❌ НЕ поддерживается |

### ⚠️ Важное требование: glibc

**Для работы Docker, Kubernetes и containerd требуется glibc версии 2.39.**

```bash
# Проверка версии glibc
ldd --version

# Вывод должен содержать версию 2.29 или выше
# Например: ldd (GNU libc) 2.34
```
## Минимальные системные требования

| Компонент | Минимально | Рекомендуемо |
| :--- | :--- | :--- |
| CPU | 2 ядра | 4+ ядер |
| RAM | 2 GB | 4+ GB |
| Дисковое пространство | 20 GB | 40+ GB |
| Сеть | 100 Mbps | 1 Gbps |
| glibc | 2.39 | 2.39+ |

## Предустановленные пакеты
Скрипт автоматически установит все необходимые зависимости, но рекомендуется иметь следующие пакеты:
```bash
# Базовые утилиты (обычно установлены по умолчанию)
dnf install -y curl wget tar gzip iproute-tc

# Утилиты для работы с сетью
dnf install -y iputils net-tools

# Утилиты для работы с репозиториями
dnf install -y dnf-plugins-core
```
## Полная проверка совместимости перед установкой
```bash
#!/bin/bash
# pre-check.sh - Полная проверка совместимости

echo "=== ПРОВЕРКА СОВМЕСТИМОСТИ ==="

# 1. Проверка glibc
echo ""
echo "1. ПРОВЕРКА GLIBC:"
GLIBC_VERSION=$(ldd --version | head -1 | grep -oP '[0-9]+\.[0-9]+' | head -1)
echo "   Версия glibc: $GLIBC_VERSION"

if [ "$(echo "$GLIBC_VERSION" | cut -d'.' -f1)" -gt 2 ] || \
   ([ "$(echo "$GLIBC_VERSION" | cut -d'.' -f1)" -eq 2 ] && [ "$(echo "$GLIBC_VERSION" | cut -d'.' -f2)" -ge 39 ]); then
    echo "   ✅ glibc версия соответствует требованиям (>= 2.39)"
else
    echo "   ❌ glibc версия НЕ соответствует требованиям!"
    echo "   Требуется glibc 2.39 или выше"
    exit 1
fi

# 2. Проверка ОС
echo ""
echo "2. ПРОВЕРКА ОС:"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "   ОС: $NAME $VERSION"
else
    echo "   ❌ Не удалось определить ОС"
    exit 1
fi

# 3. Проверка архитектуры
echo ""
echo "3. ПРОВЕРКА АРХИТЕКТУРЫ:"
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    echo "   ✅ Архитектура: $ARCH"
else
    echo "   ❌ Неподдерживаемая архитектура: $ARCH"
    exit 1
fi

# 4. Проверка версии ядра
echo ""
echo "4. ПРОВЕРКА ЯДРА:"
KERNEL=$(uname -r | cut -d'-' -f1)
echo "   Версия ядра: $KERNEL"

KERNEL_MAJOR=$(echo "$KERNEL" | cut -d'.' -f1)
if [ "$KERNEL_MAJOR" -ge 5 ]; then
    echo "   ✅ Версия ядра соответствует требованиям (>= 5.4)"
else
    echo "   ⚠️  Версия ядра: $KERNEL (рекомендуется 5.4+)"
fi

# 5. Проверка памяти
echo ""
echo "5. ПРОВЕРКА ПАМЯТИ:"
MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$MEM" -ge 2 ]; then
    echo "   ✅ Оперативная память: ${MEM}GB"
else
    echo "   ⚠️  Оперативная память: ${MEM}GB (рекомендуется 2GB+)"
fi

# 6. Проверка дискового пространства
echo ""
echo "6. ПРОВЕРКА ДИСКА:"
DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$DISK" -ge 20 ]; then
    echo "   ✅ Свободное место: ${DISK}GB"
else
    echo "   ⚠️  Свободное место: ${DISK}GB (рекомендуется 20GB+)"
fi

# 7. Проверка Docker (только для подготовительной машины)
echo ""
echo "7. ПРОВЕРКА DOCKER:"
if command -v docker &> /dev/null; then
    echo "   ✅ Docker установлен: $(docker --version)"
else
    echo "   ⚠️  Docker не установлен (требуется только для подготовки пакета)"
fi

echo ""
echo "=== РЕЗУЛЬТАТ ==="
echo "✅ Система готова к установке"
```
