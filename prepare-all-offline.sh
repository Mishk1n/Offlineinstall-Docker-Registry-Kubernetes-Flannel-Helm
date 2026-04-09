#!/bin/bash
# prepare-all-offline.sh
# Запустить на машине с доступом в интернет
# Создаёт полный офлайн пакет: Docker + Compose + Registry + K8s + Flannel

set -e

# ============================================
# НАСТРОЙКА ПЕРЕМЕННЫХ
# ============================================
K8S_VERSION="1.33.10"
FLANNEL_VERSION="v0.26.1"
FLANNEL_CNI_VERSION="v1.6.0-flannel1"
DOCKER_COMPOSE_VERSION="v2.29.7"
CNI_PLUGINS_VERSION="v1.6.2"
CRICTL_VERSION="v1.33.0"
CONTAINERD_VERSION="1.7.27"
ARCH="amd64"
WORK_DIR="/tmp/all-offline-prepare"
OUTPUT_ARCHIVE="all-offline-$(date +%Y%m%d).tar.gz"

# Цветной вывод
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Создание рабочей директории
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"/{rpms,images/k8s-core,images/flannel,manifests,registry-config}
cd "${WORK_DIR}"

log_info "=== НАЧАЛО ПОДГОТОВКИ ПОЛНОГО ОФЛАЙН ПАКЕТА ==="

# ============================================
# 1. НАСТРОЙКА РЕПОЗИТОРИЕВ
# ============================================
log_info "1. Настройка репозиториев..."

cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=*.aarch64 *.ppc64le *.s390x
EOF

if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
fi

dnf makecache

# ============================================
# 2. СКАЧИВАНИЕ RPM ПАКЕТОВ
# ============================================
log_info "2. Скачивание RPM пакетов..."

dnf download --arch=x86_64 --destdir="${WORK_DIR}/rpms" \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
    log_warn "Некоторые Docker пакеты не найдены"

dnf download --arch=x86_64 --destdir="${WORK_DIR}/rpms" \
    kubeadm-${K8S_VERSION} kubelet-${K8S_VERSION} kubectl-${K8S_VERSION} 2>/dev/null || \
    log_warn "K8s пакеты не найдены"

dnf download --arch=x86_64 --destdir="${WORK_DIR}/rpms" \
    socat conntrack-tools ebtables ethtool ipset iptables-nft 2>/dev/null || true

# ============================================
# 3. СКАЧИВАНИЕ БИНАРНЫХ ФАЙЛОВ
# ============================================
log_info "3. Скачивание бинарных файлов..."

curl -L -o "${WORK_DIR}/rpms/docker-compose-linux-${ARCH}" \
    "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" 2>/dev/null
chmod +x "${WORK_DIR}/rpms/docker-compose-linux-${ARCH}"

curl -L -o "${WORK_DIR}/rpms/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" \
    "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" 2>/dev/null

curl -L -o "${WORK_DIR}/rpms/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" \
    "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" 2>/dev/null

# ============================================
# 4. СКАЧИВАНИЕ DOCKER ОБРАЗОВ
# ============================================
log_info "4. Скачивание Docker образов..."

# Образ Registry
docker pull registry:2
docker save registry:2 -o "${WORK_DIR}/images/registry-2.tar"

# Образы Kubernetes
log_info "  Скачивание образов Kubernetes..."
docker pull registry.k8s.io/kube-apiserver:v${K8S_VERSION}
docker pull registry.k8s.io/kube-controller-manager:v${K8S_VERSION}
docker pull registry.k8s.io/kube-scheduler:v${K8S_VERSION}
docker pull registry.k8s.io/kube-proxy:v${K8S_VERSION}
docker pull registry.k8s.io/coredns/coredns:v1.12.0
docker pull registry.k8s.io/pause:3.10
docker pull registry.k8s.io/etcd:3.5.21-0

# Сохранение K8s образов
docker save registry.k8s.io/kube-apiserver:v${K8S_VERSION} \
              registry.k8s.io/kube-controller-manager:v${K8S_VERSION} \
              registry.k8s.io/kube-scheduler:v${K8S_VERSION} \
              registry.k8s.io/kube-proxy:v${K8S_VERSION} \
              registry.k8s.io/coredns/coredns:v1.12.0 \
              registry.k8s.io/pause:3.10 \
              registry.k8s.io/etcd:3.5.21-0 \
              -o "${WORK_DIR}/images/k8s-core-images.tar"

# Образы Flannel
log_info "  Скачивание образов Flannel..."
docker pull docker.io/flannel/flannel:${FLANNEL_VERSION}
docker pull docker.io/flannel/flannel-cni-plugin:${FLANNEL_CNI_VERSION}

docker save docker.io/flannel/flannel:${FLANNEL_VERSION} \
              -o "${WORK_DIR}/images/flannel-images.tar"
docker save docker.io/flannel/flannel-cni-plugin:${FLANNEL_CNI_VERSION} \
              -o "${WORK_DIR}/images/flannel-cni-images.tar"

# ============================================
# 5. СОЗДАНИЕ КОНФИГУРАЦИИ REGISTRY
# ============================================
log_info "5. Создание конфигурации Registry..."

cat > "${WORK_DIR}/registry-config/config.yml" << 'EOF'
version: 0.1
log:
  level: info
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :5000
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

# ============================================
# 6. СКАЧИВАНИЕ YAML МАНИФЕСТОВ
# ============================================
log_info "6. Скачивание YAML манифестов..."

curl -L -o "${WORK_DIR}/manifests/kube-flannel.yml" \
    https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml 2>/dev/null

# ============================================
# 7. СОЗДАНИЕ УСТАНОВОЧНОГО СКРИПТА (ИСПРАВЛЕННАЯ ВЕРСИЯ)
# ============================================
log_info "7. Создание установочного скрипта..."

cat > "${WORK_DIR}/install-all.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
# install-all.sh - ИСПРАВЛЕННАЯ ВЕРСИЯ
# Запускать от root на целевой машине

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен запускаться от root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="localhost:5000"
K8S_VERSION="1.33.10"
FLANNEL_VERSION="v0.26.1"
FLANNEL_CNI_VERSION="v1.6.0-flannel1"

log_info "=== ПОЛНАЯ ОФЛАЙН УСТАНОВКА ==="

# 1. Предварительная настройка
log_info "1. Предварительная настройка..."
swapoff -a
sed -i '/swap/d' /etc/fstab
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF
sysctl --system

# ============================================
# АВТОМАТИЧЕСКОЕ ОПРЕДЕЛЕНИЕ MASTER IP
# ============================================
log_info "Определение IP адреса сервера..."

MASTER_IP=$(ip -4 route get 1 2>/dev/null | awk '{print $NF;exit}')

if [[ -z "$MASTER_IP" ]] || [[ "$MASTER_IP" == "0" ]] || [[ "$MASTER_IP" == "0.0.0.0" ]]; then
    MASTER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

if [[ -z "$MASTER_IP" ]] || [[ "$MASTER_IP" == "0" ]] || [[ "$MASTER_IP" == "0.0.0.0" ]]; then
    MASTER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
fi

if [[ -z "$MASTER_IP" ]] || [[ "$MASTER_IP" == "0" ]] || [[ "$MASTER_IP" == "0.0.0.0" ]]; then
    if command -v ifconfig &> /dev/null; then
        MASTER_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
fi

if [[ -z "$MASTER_IP" ]] || [[ "$MASTER_IP" == "0" ]] || [[ "$MASTER_IP" == "0.0.0.0" ]]; then
    log_error "Не удалось определить IP адрес сервера!"
    log_error "Пожалуйста, укажите IP вручную:"
    log_error "  export MASTER_IP=ваш_ип"
    log_error "  затем запустите скрипт снова"
    exit 1
fi

if ! echo "$MASTER_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    log_error "Определён некорректный IP: $MASTER_IP"
    exit 1
fi

log_info "Master IP: ${MASTER_IP}"

# Настройка /etc/hosts
if ! grep -q "$MASTER_IP" /etc/hosts; then
    echo "$MASTER_IP $(hostname)" >> /etc/hosts
    log_info "Добавлена запись в /etc/hosts: $MASTER_IP $(hostname)"
fi
if ! grep -q "127.0.0.1 $(hostname)" /etc/hosts; then
    echo "127.0.0.1 $(hostname)" >> /etc/hosts
fi

# 2. Установка Docker
log_info "2. Установка Docker..."
cd "${SCRIPT_DIR}/packages"
rpm -ivh --force --nodeps containerd.io*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-ce*.rpm docker-ce-cli*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-buildx-plugin*.rpm docker-compose-plugin*.rpm 2>/dev/null || true

systemctl enable --now docker
log_info "Docker: $(docker --version)"

# 3. Запуск Registry
log_info "3. Запуск Registry..."
docker stop docker-registry 2>/dev/null || true
docker rm docker-registry 2>/dev/null || true

mkdir -p /opt/registry/data
docker run -d \
    --name docker-registry \
    --restart unless-stopped \
    -p 5000:5000 \
    -v /opt/registry/data:/var/lib/registry \
    registry:2
sleep 5

# 4. Загрузка образов в Registry
log_info "4. Загрузка образов в Registry..."

if [[ -f "${SCRIPT_DIR}/images/k8s-core-images.tar" ]]; then
    docker load -i "${SCRIPT_DIR}/images/k8s-core-images.tar"
    
    docker tag registry.k8s.io/kube-apiserver:v${K8S_VERSION} ${REGISTRY}/kube-apiserver:v${K8S_VERSION}
    docker push ${REGISTRY}/kube-apiserver:v${K8S_VERSION}
    log_info "  Загружен: kube-apiserver:v${K8S_VERSION}"
    
    docker tag registry.k8s.io/kube-controller-manager:v${K8S_VERSION} ${REGISTRY}/kube-controller-manager:v${K8S_VERSION}
    docker push ${REGISTRY}/kube-controller-manager:v${K8S_VERSION}
    log_info "  Загружен: kube-controller-manager:v${K8S_VERSION}"
    
    docker tag registry.k8s.io/kube-scheduler:v${K8S_VERSION} ${REGISTRY}/kube-scheduler:v${K8S_VERSION}
    docker push ${REGISTRY}/kube-scheduler:v${K8S_VERSION}
    log_info "  Загружен: kube-scheduler:v${K8S_VERSION}"
    
    docker tag registry.k8s.io/kube-proxy:v${K8S_VERSION} ${REGISTRY}/kube-proxy:v${K8S_VERSION}
    docker push ${REGISTRY}/kube-proxy:v${K8S_VERSION}
    log_info "  Загружен: kube-proxy:v${K8S_VERSION}"
    
    docker tag registry.k8s.io/coredns/coredns:v1.12.0 ${REGISTRY}/coredns:v1.12.0
    docker push ${REGISTRY}/coredns:v1.12.0
    log_info "  Загружен: coredns:v1.12.0"
    
    docker tag registry.k8s.io/pause:3.10 ${REGISTRY}/pause:3.10
    docker push ${REGISTRY}/pause:3.10
    log_info "  Загружен: pause:3.10"
    
    docker tag registry.k8s.io/etcd:3.5.21-0 ${REGISTRY}/etcd:3.5.21-0
    docker push ${REGISTRY}/etcd:3.5.21-0
    log_info "  Загружен: etcd:3.5.21-0"
    
    docker tag ${REGISTRY}/etcd:3.5.21-0 ${REGISTRY}/etcd:3.5.24-0
    docker push ${REGISTRY}/etcd:3.5.24-0
    log_info "  Загружен: etcd:3.5.24-0 (доп. тег)"
fi

if [[ -f "${SCRIPT_DIR}/images/flannel-images.tar" ]]; then
    docker load -i "${SCRIPT_DIR}/images/flannel-images.tar"
    docker tag flannel/flannel:${FLANNEL_VERSION} ${REGISTRY}/flannel:${FLANNEL_VERSION}
    docker push ${REGISTRY}/flannel:${FLANNEL_VERSION}
    log_info "  Загружен: flannel:${FLANNEL_VERSION}"
fi

if [[ -f "${SCRIPT_DIR}/images/flannel-cni-images.tar" ]]; then
    docker load -i "${SCRIPT_DIR}/images/flannel-cni-images.tar"
    docker tag flannel/flannel-cni-plugin:${FLANNEL_CNI_VERSION} ${REGISTRY}/flannel-cni-plugin:${FLANNEL_CNI_VERSION}
    docker push ${REGISTRY}/flannel-cni-plugin:${FLANNEL_CNI_VERSION}
    log_info "  Загружен: flannel-cni-plugin:${FLANNEL_CNI_VERSION}"
fi

# 5. Установка Kubernetes
log_info "5. Установка Kubernetes..."
cd "${SCRIPT_DIR}/packages"
rpm -ivh --force --nodeps kubeadm*.rpm kubelet*.rpm kubectl*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps socat*.rpm conntrack*.rpm ebtables*.rpm ethtool*.rpm ipset*.rpm iptables*.rpm 2>/dev/null || true

# CNI плагины
for tgz in cni-plugins-linux-amd64-*.tgz; do
    if [[ -f "$tgz" ]]; then
        mkdir -p /opt/cni/bin
        tar -xzf "$tgz" -C /opt/cni/bin/
        log_info "CNI плагины установлены"
    fi
done

# 6. Настройка containerd
log_info "6. Настройка containerd..."
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml 2>/dev/null || true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i "s|sandbox_image = .*|sandbox_image = \"${REGISTRY}/pause:3.10\"|" /etc/containerd/config.toml

systemctl restart containerd
systemctl enable --now kubelet

# 7. Инициализация Kubernetes
log_info "7. Инициализация Kubernetes..."

# Очистка перед инициализацией
kubeadm reset -f 2>/dev/null || true
rm -rf /etc/kubernetes /var/lib/etcd 2>/dev/null || true

kubeadm init \
    --kubernetes-version=v${K8S_VERSION} \
    --pod-network-cidr=10.244.0.0/16 \
    --image-repository=${REGISTRY} \
    --apiserver-advertise-address=${MASTER_IP} \
    --ignore-preflight-errors=Hostname

# 8. Настройка kubectl
log_info "8. Настройка kubectl..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Исправляем server в admin.conf (на всякий случай)
if grep -q "server: https://0:" /etc/kubernetes/admin.conf 2>/dev/null; then
    sed -i "s|server: https://0:6443|server: https://${MASTER_IP}:6443|g" /etc/kubernetes/admin.conf
    sed -i "s|server: https://0:6443|server: https://${MASTER_IP}:6443|g" $HOME/.kube/config
fi

# 9. Установка Flannel
log_info "9. Установка Flannel..."
cd "${SCRIPT_DIR}"
cp manifests/kube-flannel.yml /tmp/kube-flannel.yml
sed -i "s|docker.io/flannel/flannel|${REGISTRY}/flannel|g" /tmp/kube-flannel.yml
sed -i "s|docker.io/flannel/flannel-cni-plugin|${REGISTRY}/flannel-cni-plugin|g" /tmp/kube-flannel.yml
kubectl apply -f /tmp/kube-flannel.yml

# 10. Проверка
log_info "10. Ожидание запуска (60 секунд)..."
sleep 60
echo ""
log_info "=== РЕЗУЛЬТАТ ==="
kubectl get nodes
echo ""
kubectl get pods -n kube-system

log_info "=== УСТАНОВКА ЗАВЕРШЕНА ==="
echo ""
echo "Master IP: ${MASTER_IP}"
echo ""
echo "Для проверки:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n kube-system"
echo "  curl http://localhost:5000/v2/_catalog"
INSTALL_SCRIPT

chmod +x "${WORK_DIR}/install-all.sh"

# ============================================
# 8. СОЗДАНИЕ ФИНАЛЬНОГО АРХИВА
# ============================================
log_info "8. Создание финального архива..."

mkdir -p "${WORK_DIR}/final"
mv "${WORK_DIR}/rpms" "${WORK_DIR}/final/packages" 2>/dev/null || mkdir -p "${WORK_DIR}/final/packages"
mv "${WORK_DIR}/images" "${WORK_DIR}/final/images" 2>/dev/null || mkdir -p "${WORK_DIR}/final/images"
mv "${WORK_DIR}/manifests" "${WORK_DIR}/final/manifests" 2>/dev/null || mkdir -p "${WORK_DIR}/final/manifests"
mv "${WORK_DIR}/registry-config" "${WORK_DIR}/final/" 2>/dev/null || true
mv "${WORK_DIR}/install-all.sh" "${WORK_DIR}/final/"

cd "${WORK_DIR}/final"
tar -czf "/tmp/${OUTPUT_ARCHIVE}" .

log_info "=============================================="
log_info "ГОТОВО!"
log_info "Архив создан: /tmp/${OUTPUT_ARCHIVE}"
log_info "Размер: $(du -h /tmp/${OUTPUT_ARCHIVE} 2>/dev/null | cut -f1)"
log_info ""
log_info "Перенесите архив на целевую ВМ и выполните:"
log_info "  tar -xzf ${OUTPUT_ARCHIVE}"
log_info "  ./install-all.sh"
log_info "=============================================="