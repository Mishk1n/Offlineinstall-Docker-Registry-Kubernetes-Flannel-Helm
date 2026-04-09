# README: Офлайн установка Docker, Registry, Kubernetes и Flannel
## 📋 Описание
Данный набор скриптов позволяет выполнить полную офлайн установку следующих компонентов на сервер без доступа к интернету:
| Компонент | Версия |
|-----------|--------|
| Docker CE | 29.4.0 |
| Docker Compose | 2.29.7 |
| Docker Registry | 2 (локальный) |
| Kubernetes | 1.33.10 |
| Flannel (CNI) | v0.26.1 |
| containerd | 2.2.2 |
| CNI plugins | 1.6.2 |

> **Особенность:** Все Docker образы загружаются в локальный registry (`localhost:5000`), Kubernetes использует образы из этого registry.

## 📁 Структура пакета
```bash
all-offline-YYYYMMDD/
├── packages/          # RPM пакеты и бинарные файлы
│   ├── docker-ce-*.rpm
│   ├── docker-ce-cli-*.rpm
│   ├── containerd.io-*.rpm
│   ├── kubeadm-*.rpm
│   ├── kubelet-*.rpm
│   ├── kubectl-*.rpm
│   ├── docker-compose-linux-x86_64
│   ├── cni-plugins-linux-amd64-*.tgz
│   └── crictl-*.tar.gz
├── images/            # Docker образы (.tar)
│   ├── k8s-core-images.tar      # Образы Kubernetes
│   ├── flannel-images.tar       # Образ Flannel
│   ├── flannel-cni-images.tar   # Образ CNI плагина Flannel
│   └── registry-2.tar           # Образ Docker Registry
├── manifests/         # YAML манифесты
│   └── kube-flannel.yml
├── registry-config/   # Конфигурация Registry
│   └── config.yml
└── install-all.sh     # Главный установочный скрипт
```
## 🚀 Предварительная подготовка
```bash
# Добавление официального репозитория docker
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

# Установка Docker на подготовительной машине
dnf install -y docker-ce docker-ce-cli containerd.io

# Запуск Docker
systemctl enable --now docker

# Аутентификация в репозитории образов docker
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
- Добавляются репозитории Kubernetes и Docker
- Скачиваются RPM пакеты всех компонентов
- Скачиваются бинарные файлы (Docker Compose, CNI plugins, crictl)
- Скачиваются Docker образы (K8s, Flannel, Registry)
- Создаётся конфигурация для Registry
- Скачивается манифест Flannel
- Создаётся установочный скрипт install-all.sh
- Всё упаковывается в архив /tmp/all-offline-YYYYMMDD.tar.gz

Этап 2: Перенос архива на целевую ВМ
```bash
# Используйте scp, USB-накопитель или другой способ
scp /tmp/all-offline-YYYYMMDD.tar.gz root@target-vm:/opt/
```
Этап 3: Установка на целевой ВМ (без интернета)
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
Что происходит на этом этапе:
| Шаг | Действие |
|:----:|:---------|
| 1 | Предварительная настройка (отключение swap, SELinux, firewall) |
| 2 | Установка Docker и Docker Compose из RPM пакетов |
| 3 | Запуск локального Docker Registry на порту 5000 |
| 4 | Загрузка всех образов в локальный Registry |
| 5 | Установка Kubernetes (kubeadm, kubelet, kubectl) |
| 6 | Установка CNI плагинов в `/opt/cni/bin` |
| 7 | Настройка containerd (cgroup, sandbox image) |
| 8 | Инициализация Kubernetes кластера через `kubeadm init` |
| 9 | Установка Flannel CNI |
| 10 | Проверка работоспособности |

## ✅ Проверка установки
После завершения скрипта выполните:
```bash
# Статус узлов
kubectl get nodes

# Статус подов в системном namespace
kubectl get pods -n kube-system

# Список образов в локальном registry
curl http://localhost:5000/v2/_catalog

# Статус Docker Registry
docker ps | grep registry
```
Ожидаемый результат:

```bash
# kubectl get nodes
NAME              STATUS   ROLES           AGE   VERSION
mishkin-test-vm   Ready    control-plane   5m    v1.33.10

# kubectl get pods -n kube-system
NAME                                      READY   STATUS    RESTARTS   AGE
coredns-xxx                               1/1     Running   0          2m
etcd-mishkin-test-vm                      1/1     Running   0          5m
kube-apiserver-mishkin-test-vm            1/1     Running   0          5m
kube-controller-manager-mishkin-test-vm   1/1     Running   0          5m
kube-flannel-ds-xxx                       1/1     Running   0          1m
kube-proxy-xxx                            1/1     Running   0          5m
kube-scheduler-mishkin-test-vm            1/1     Running   0          5m

# curl http://localhost:5000/v2/_catalog
{"repositories":["coredns","etcd","flannel","flannel-cni-plugin","kube-apiserver","kube-controller-manager","kube-proxy","kube-scheduler","pause","registry"]}
```

## 🔧 Присоединение worker узлов

- Создайте файл install-worker.sh на целевой worker машине
- Если вы хотите передать join команду заранее, используйте этот вариант install-worker-auto.sh


На master узле получите join-команду:
```bash
kubeadm token create --print-join-command
```
На каждом worker узле выполните полученную команду:
```bash
kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
Вариант 1: Интерактивный (ручной ввод)
```bash
# Скопируйте архив с master узла на worker
scp /tmp/all-offline-*.tar.gz root@worker-ip:/opt/

# Распакуйте
cd /opt
tar -xzf all-offline-*.tar.gz
cd all-offline-*

# Создайте скрипт install-worker.sh (содержимое выше)
chmod +x install-worker.sh

# Запустите установку
./install-worker.sh

# Введите IP master узла при запросе
# Затем выполните join команду, полученную с master
```
Вариант 2: Автоматический (с передачей параметров)
```bash
# Скопируйте архив
scp /tmp/all-offline-*.tar.gz root@worker-ip:/opt/

# На worker узле
cd /opt
tar -xzf all-offline-*.tar.gz
cd all-offline-*

# Создайте скрипт install-worker-auto.sh (содержимое выше)
chmod +x install-worker-auto.sh

# Запустите с параметрами
./install-worker-auto.sh 5.42.106.202 'kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>'
```

## 📌 Что делает скрипт worker узла

| Шаг | Действие |
|:----:|:---------|
| 1 | Предварительная настройка (swap, SELinux, firewall) |
| 2 | Настройка `/etc/hosts` (добавление master узла) |
| 3 | Установка Docker и Docker Compose |
| 4 | Установка Kubernetes (kubeadm, kubelet, kubectl) |
| 5 | Установка CNI плагинов |
| 6 | Настройка containerd (cgroup, sandbox image) |
| 7 | Присоединение к кластеру через `kubeadm join` |

### Проверка после установки
На master узле выполните:
```bash
kubectl get nodes
```
Ожидаемый вывод:

## Статусы узлов

| Узел | Статус | Роль | Возраст | Версия |
|:-----|:-------|:-----|:--------|:-------|
| master | `Ready` | control-plane | 10m | v1.33.10 |
| worker1 | `Ready` | `<none>` | 2m | v1.33.10 |
| worker2 | `Ready` | `<none>` | 2m | v1.33.10 |

## ❗ Возможные проблемы и решения

| Проблема | Решение |
|:---------|:--------|
| `docker: command not found` на этапе подготовки | Установите Docker на машине с интернетом: `dnf install -y docker-ce` |
| IP не определился автоматически | Задайте вручную перед запуском: `export MASTER_IP=ваш_ип && ./install-all.sh` |
| `connection refused` при `kubectl get nodes` | Проверьте: `export KUBECONFIG=/etc/kubernetes/admin.conf` |
| CoreDNS в статусе `ContainerCreating` | Проверьте установку Flannel: `kubectl get pods -n kube-system \| grep flannel` |
| Registry не доступен | Проверьте: `docker ps \| grep registry`, перезапустите: `docker restart docker-registry` |

## 📊 Версии компонентов

| Компонент | Версия |
|:----------|:-------|
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

## 🔄 Полный сброс (если что-то пошло не так)
```bash
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /root/.kube
rm -rf /etc/cni/net.d /opt/cni/bin
docker stop docker-registry && docker rm docker-registry
rm -rf /opt/registry/data
systemctl restart containerd docker kubelet
```
### Если IP всё равно не определяется - укажите вручную
```bash
# Вручную задайте IP перед запуском
export MASTER_IP="5.42.106.202"
```
Или измените скрипт - добавьте ручной ввод
```bash
# Вставьте этот блок после определения IP, если IP не найден
if [[ -z "$MASTER_IP" ]] || [[ "$MASTER_IP" == "0" ]]; then
    log_warn "Не удалось автоматически определить IP"
    read -p "Введите IP адрес сервера вручную: " MASTER_IP
fi

# Затем запустите скрипт
./install-all.sh
```
