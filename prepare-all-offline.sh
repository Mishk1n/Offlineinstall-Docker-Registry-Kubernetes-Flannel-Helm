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

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker не установлен! Установите Docker перед запуском скрипта."
    exit 1
fi

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
# 7. СОЗДАНИЕ УСТАНОВОЧНЫХ СКРИПТОВ
# ============================================
log_info "7. Создание установочных скриптов..."

# Копируем install-all.sh (финальная версия)
cat > "${WORK_DIR}/install-all.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
# install-all.sh - ФИНАЛЬНАЯ РАБОЧАЯ ВЕРСИЯ
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

# 2. Определение IP адреса
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
    exit 1
fi

log_info "Master IP: ${MASTER_IP}"

# Настройка /etc/hosts
if ! grep -q "$MASTER_IP" /etc/hosts; then
    echo "$MASTER_IP $(hostname)" >> /etc/hosts
fi

# 3. Установка crictl
log_info "3. Установка crictl..."
if [[ -f "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" ]]; then
    tar -xzf "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" -C /usr/local/bin/
    chmod +x /usr/local/bin/crictl
    log_info "  crictl установлен"
fi

# 4. Установка Docker
log_info "4. Установка Docker..."
cd "${SCRIPT_DIR}/packages"
rpm -ivh --force --nodeps containerd.io*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-ce*.rpm docker-ce-cli*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-buildx-plugin*.rpm docker-compose-plugin*.rpm 2>/dev/null || true

systemctl enable --now docker
sleep 5
log_info "Docker: $(docker --version)"

# 5. Загрузка образа registry
log_info "5. Загрузка образа Registry..."
if [[ -f "${SCRIPT_DIR}/images/registry-2.tar" ]]; then
    docker load -i "${SCRIPT_DIR}/images/registry-2.tar"
else
    log_error "Файл registry-2.tar не найден!"
    exit 1
fi

# 6. Запуск Registry
log_info "6. Запуск Registry..."
docker stop docker-registry 2>/dev/null || true
docker rm docker-registry 2>/dev/null || true

mkdir -p /opt/registry/data
docker run -d \
    --name docker-registry \
    --restart unless-stopped \
    -p 5000:5000 \
    -v /opt/registry/data:/var/lib/registry \
    registry:2
sleep 10

if ! curl -s http://localhost:5000/v2/ > /dev/null; then
    log_error "Registry не запустился!"
    exit 1
fi
log_info "  Registry работает"

# 7. Загрузка образов в Registry
log_info "7. Загрузка образов в Registry..."

if [[ -f "${SCRIPT_DIR}/images/k8s-core-images.tar" ]]; then
    docker load -i "${SCRIPT_DIR}/images/k8s-core-images.tar"
    
    for img in kube-apiserver kube-controller-manager kube-scheduler kube-proxy; do
        docker tag registry.k8s.io/${img}:v${K8S_VERSION} ${REGISTRY}/${img}:v${K8S_VERSION}
        docker push ${REGISTRY}/${img}:v${K8S_VERSION}
        log_info "  Загружен: ${img}:v${K8S_VERSION}"
    done
    
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

log_info "  Все образы загружены в registry"

# 8. Docker оставлен запущенным
log_info "8. Docker оставлен запущенным (registry необходим)"

# 9. Установка Kubernetes
log_info "9. Установка Kubernetes..."
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

# 10. НАСТРОЙКА CONTAINERD
log_info "10. Настройка containerd..."

systemctl stop containerd 2>/dev/null || true

cat > /etc/containerd/config.toml << 'EOF'
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "localhost:5000/pause:3.10"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
          endpoint = ["http://localhost:5000"]
EOF

systemctl start containerd
sleep 5

if ! systemctl is-active --quiet containerd; then
    log_error "containerd не запустился!"
    journalctl -u containerd -n 20 --no-pager
    exit 1
fi
log_info "containerd настроен и запущен"

# 11. Запуск kubelet
log_info "11. Запуск kubelet..."
systemctl enable --now kubelet
sleep 5

# 12. Инициализация Kubernetes
log_info "12. Инициализация Kubernetes..."

kubeadm reset -f 2>/dev/null || true
rm -rf /etc/kubernetes /var/lib/etcd 2>/dev/null || true

kubeadm init \
    --kubernetes-version=v${K8S_VERSION} \
    --pod-network-cidr=10.244.0.0/16 \
    --image-repository=${REGISTRY} \
    --apiserver-advertise-address=${MASTER_IP} \
    --ignore-preflight-errors=Hostname,ImagePull

# 13. Настройка kubectl
log_info "13. Настройка kubectl..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 14. Определяем сетевой интерфейс
log_info "14. Определение сетевого интерфейса..."

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip link show | grep -v lo | grep -E "^[0-9]+:" | head -1 | awk -F': ' '{print $2}')
fi

if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ls /sys/class/net/ | grep -v lo | head -1)
fi

if [[ -z "$INTERFACE" ]]; then
    INTERFACE="ens192"
fi

log_info "  Используемый интерфейс: ${INTERFACE}"

# 15. Установка Flannel
log_info "15. Установка Flannel..."

kubectl delete namespace kube-flannel 2>/dev/null || true
sleep 5

cat > /tmp/kube-flannel-final.yaml << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-flannel
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "host-gw"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      priorityClassName: system-node-critical
      serviceAccountName: flannel
      tolerations:
      - operator: Exists
        effect: NoSchedule
      - operator: Exists
        effect: NoExecute
      containers:
      - name: kube-flannel
        image: localhost:5000/flannel:v0.26.1
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        - --kube-api-url=https://${MASTER_IP}:6443
        - --kubeconfig-file=/etc/kubernetes/admin.conf
        - --iface=${INTERFACE}
        - --iface-regex=${INTERFACE}
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: true
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: kubeconfig
          mountPath: /etc/kubernetes
          readOnly: true
      initContainers:
      - name: install-cni-plugin
        image: localhost:5000/flannel-cni-plugin:v1.6.0-flannel1
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
        image: localhost:5000/flannel:v0.26.1
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: kubeconfig
        hostPath:
          path: /etc/kubernetes
EOF

kubectl apply -f /tmp/kube-flannel-final.yaml

# 16. Установка kube-proxy
log_info "16. Установка kube-proxy..."

kubectl create serviceaccount kube-proxy -n kube-system 2>/dev/null || true

cat > /tmp/kube-proxy-rbac.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-proxy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-proxy
subjects:
- kind: ServiceAccount
  name: kube-proxy
  namespace: kube-system
EOF
kubectl apply -f /tmp/kube-proxy-rbac.yaml

kubectl delete daemonset -n kube-system kube-proxy 2>/dev/null || true

cat > /tmp/kube-proxy-final.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
    spec:
      hostNetwork: true
      serviceAccountName: kube-proxy
      containers:
      - name: kube-proxy
        image: localhost:5000/kube-proxy:v1.33.10
        command:
        - /usr/local/bin/kube-proxy
        args:
        - --proxy-mode=iptables
        - --cluster-cidr=10.244.0.0/16
        - --kubeconfig=/etc/kubernetes/admin.conf
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /run/xtables.lock
          name: xtables-lock
        - mountPath: /etc/kubernetes
          name: kubeconfig
          readOnly: true
      volumes:
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: kubeconfig
        hostPath:
          path: /etc/kubernetes
      tolerations:
      - operator: Exists
EOF

kubectl apply -f /tmp/kube-proxy-final.yaml

# 17. Настройка маршрутизации
log_info "17. Настройка маршрутизации..."

if [[ -n "$INTERFACE" ]]; then
    ip route add 10.96.0.0/12 dev ${INTERFACE} 2>/dev/null || true
fi

iptables -t nat -A OUTPUT -d 10.96.0.1 -p tcp --dport 443 -j DNAT --to-destination ${MASTER_IP}:6443 2>/dev/null || true
iptables -t nat -A PREROUTING -d 10.96.0.1 -p tcp --dport 443 -j DNAT --to-destination ${MASTER_IP}:6443 2>/dev/null || true

# 18. Снятие taints
log_info "18. Снятие ограничений с master узла..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

# 19. Перезапуск CoreDNS
log_info "19. Перезапуск CoreDNS..."
kubectl delete pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || true

# 20. Ожидание и проверка
log_info "20. Ожидание запуска компонентов (120 секунд)..."
sleep 120

echo ""
log_info "=== РЕЗУЛЬТАТ ==="
kubectl get nodes -o wide
echo ""
kubectl get pods -n kube-system
echo ""
kubectl get pods -n kube-flannel 2>/dev/null || echo "Flannel namespace not found"

log_info "=== УСТАНОВКА ЗАВЕРШЕНА ==="
echo ""
echo "Master IP: ${MASTER_IP}"
echo "Интерфейс: ${INTERFACE}"
echo ""
echo "Для добавления worker узлов используйте команду:"
echo "  kubeadm token create --print-join-command"
echo ""
echo "Проверка работоспособности:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n kube-system"
echo "  kubectl get pods -n kube-flannel"
echo ""
echo "Для тестового запуска приложения:"
echo "  kubectl create deployment test --image=localhost:5000/pause:3.10 --replicas=2"
echo "  kubectl get pods"
echo "  kubectl delete deployment test"
INSTALL_SCRIPT

chmod +x "${WORK_DIR}/install-all.sh"

# Создаем install-worker.sh
cat > "${WORK_DIR}/install-worker.sh" << 'WORKER_SCRIPT'
#!/bin/bash
# install-worker.sh
# Установка worker узла для Kubernetes (офлайн)
# Запускать от root на worker машине

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

log_info "=== УСТАНОВКА WORKER УЗЛА ==="

# ============================================
# 1. ПРЕДВАРИТЕЛЬНАЯ НАСТРОЙКА
# ============================================
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
# 2. НАСТРОЙКА HOSTS
# ============================================
log_info "2. Настройка /etc/hosts..."
read -p "Введите IP адрес MASTER узла: " MASTER_IP

if [[ -n "$MASTER_IP" ]]; then
    if ! grep -q "$MASTER_IP" /etc/hosts; then
        echo "$MASTER_IP master" >> /etc/hosts
        log_info "Добавлена запись: $MASTER_IP master"
    fi
fi

# Определяем интерфейс для worker
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip link show | grep -v lo | grep -E "^[0-9]+:" | head -1 | awk -F': ' '{print $2}')
fi
if [[ -z "$INTERFACE" ]]; then
    INTERFACE="ens192"
fi
log_info "Сетевой интерфейс: ${INTERFACE}"

# ============================================
# 3. УСТАНОВКА CRICTL
# ============================================
log_info "3. Установка crictl..."
if [[ -f "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" ]]; then
    tar -xzf "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" -C /usr/local/bin/
    chmod +x /usr/local/bin/crictl
    log_info "  crictl установлен"
fi

# ============================================
# 4. УСТАНОВКА DOCKER
# ============================================
log_info "4. Установка Docker..."

cd "${SCRIPT_DIR}/packages"
rpm -ivh --force --nodeps containerd.io*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-ce*.rpm docker-ce-cli*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-buildx-plugin*.rpm docker-compose-plugin*.rpm 2>/dev/null || true

systemctl enable --now docker
sleep 5
log_info "Docker: $(docker --version)"

# ============================================
# 5. УСТАНОВКА KUBERNETES
# ============================================
log_info "5. Установка Kubernetes компонентов..."

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

# ============================================
# 6. НАСТРОЙКА CONTAINERD
# ============================================
log_info "6. Настройка containerd..."

systemctl stop containerd 2>/dev/null || true

cat > /etc/containerd/config.toml << 'EOF'
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "localhost:5000/pause:3.10"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
          endpoint = ["http://localhost:5000"]
EOF

systemctl start containerd
sleep 5

if ! systemctl is-active --quiet containerd; then
    log_error "containerd не запустился!"
    journalctl -u containerd -n 20 --no-pager
    exit 1
fi
log_info "containerd настроен и запущен"

# ============================================
# 7. ЗАПУСК KUBELET
# ============================================
log_info "7. Запуск kubelet..."
systemctl enable --now kubelet
sleep 5

# ============================================
# 8. ОЖИДАНИЕ JOIN КОМАНДЫ
# ============================================
log_info "8. Ожидание join команды..."

echo ""
echo "=============================================="
echo "УСТАНОВКА WORKER УЗЛА ЗАВЕРШЕНА!"
echo "=============================================="
echo ""
echo "Master IP: ${MASTER_IP}"
echo "Интерфейс: ${INTERFACE}"
echo ""
echo "Теперь выполните на MASTER узле:"
echo "  kubeadm token create --print-join-command"
echo ""
echo "Затем скопируйте полученную команду и выполните её здесь"
echo "Пример команды:"
echo "  kubeadm join ${MASTER_IP}:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo "После присоединения проверьте на master: kubectl get nodes"
echo "=============================================="
WORKER_SCRIPT

chmod +x "${WORK_DIR}/install-worker.sh"

# Создаем install-worker-auto.sh
cat > "${WORK_DIR}/install-worker-auto.sh" << 'WORKER_AUTO_SCRIPT'
#!/bin/bash
# install-worker-auto.sh
# Установка worker узла с автоматическим присоединением
# Запускать от root на worker машине

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен запускаться от root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="localhost:5000"
K8S_VERSION="1.33.10"

log_info "=== УСТАНОВКА WORKER УЗЛА ==="

# Проверка параметров
if [[ -z "$1" ]] || [[ -z "$2" ]]; then
    log_error "Использование: $0 <MASTER_IP> <JOIN_COMMAND>"
    echo ""
    echo "Как получить join команду на master узле:"
    echo "  kubeadm token create --print-join-command"
    echo ""
    echo "Пример:"
    echo "  kubeadm join 192.168.1.100:6443 --token abc123.def456 --discovery-token-ca-cert-hash sha256:..."
    echo ""
    echo "Запуск скрипта:"
    echo "  $0 192.168.1.100 'kubeadm join 192.168.1.100:6443 --token abc123.def456 --discovery-token-ca-cert-hash sha256:...'"
    exit 1
fi

MASTER_IP="$1"
JOIN_COMMAND="$2"

log_info "Master IP: ${MASTER_IP}"

# Определяем интерфейс
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip link show | grep -v lo | grep -E "^[0-9]+:" | head -1 | awk -F': ' '{print $2}')
fi
if [[ -z "$INTERFACE" ]]; then
    INTERFACE="ens192"
fi
log_info "Сетевой интерфейс: ${INTERFACE}"

# ============================================
# 1. ПРЕДВАРИТЕЛЬНАЯ НАСТРОЙКА
# ============================================
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

# Настройка hosts
if ! grep -q "$MASTER_IP" /etc/hosts; then
    echo "$MASTER_IP master" >> /etc/hosts
fi

# ============================================
# 2. УСТАНОВКА CRICTL
# ============================================
log_info "2. Установка crictl..."
if [[ -f "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" ]]; then
    tar -xzf "${SCRIPT_DIR}/packages/crictl-${K8S_VERSION}-linux-amd64.tar.gz" -C /usr/local/bin/
    chmod +x /usr/local/bin/crictl
    log_info "  crictl установлен"
fi

# ============================================
# 3. УСТАНОВКА DOCKER
# ============================================
log_info "3. Установка Docker..."

cd "${SCRIPT_DIR}/packages"
rpm -ivh --force --nodeps containerd.io*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-ce*.rpm docker-ce-cli*.rpm 2>/dev/null || true
rpm -ivh --force --nodeps docker-buildx-plugin*.rpm docker-compose-plugin*.rpm 2>/dev/null || true

systemctl enable --now docker
sleep 5
log_info "Docker: $(docker --version)"

# ============================================
# 4. УСТАНОВКА KUBERNETES
# ============================================
log_info "4. Установка Kubernetes компонентов..."

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

# ============================================
# 5. НАСТРОЙКА CONTAINERD
# ============================================
log_info "5. Настройка containerd..."

systemctl stop containerd 2>/dev/null || true

cat > /etc/containerd/config.toml << 'EOF'
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "localhost:5000/pause:3.10"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
          endpoint = ["http://localhost:5000"]
EOF

systemctl start containerd
sleep 5

if ! systemctl is-active --quiet containerd; then
    log_error "containerd не запустился!"
    journalctl -u containerd -n 20 --no-pager
    exit 1
fi
log_info "containerd настроен и запущен"

# ============================================
# 6. ЗАПУСК KUBELET
# ============================================
log_info "6. Запуск kubelet..."
systemctl enable --now kubelet
sleep 5

# ============================================
# 7. ПРИСОЕДИНЕНИЕ К КЛАСТЕРУ
# ============================================
log_info "7. Присоединение к кластеру..."

eval "$JOIN_COMMAND"

if [[ $? -eq 0 ]]; then
    log_info "Worker успешно присоединён к кластеру!"
else
    log_error "Ошибка присоединения. Проверьте join команду."
    exit 1
fi

log_info "=== УСТАНОВКА WORKER УЗЛА ЗАВЕРШЕНА ==="
echo ""
echo "На master узле выполните: kubectl get nodes"
WORKER_AUTO_SCRIPT

chmod +x "${WORK_DIR}/install-worker-auto.sh"

# Создаем clean-all.sh
cat > "${WORK_DIR}/clean-all.sh" << 'CLEAN_SCRIPT'
#!/bin/bash
# clean-all.sh - Полная очистка перед переустановкой
# Запускать от root

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

log_info "=== ПОЛНАЯ ОЧИСТКА ПЕРЕД ПЕРЕУСТАНОВКОЙ ==="

# 1. Сброс Kubernetes
log_info "1. Сброс Kubernetes..."
kubeadm reset -f 2>/dev/null || true

# 2. Остановка сервисов
log_info "2. Остановка сервисов..."
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
systemctl stop docker 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true
systemctl disable docker 2>/dev/null || true

# 3. Удаление конфигурационных файлов
log_info "3. Удаление конфигурационных файлов..."
rm -rf /etc/kubernetes
rm -rf /var/lib/etcd
rm -rf /var/lib/kubelet
rm -rf /etc/cni
rm -rf /var/lib/cni
rm -rf /opt/cni
rm -rf ~/.kube
rm -rf /root/.kube

# 4. Удаление конфигов containerd
log_info "4. Удаление конфигов containerd..."
rm -rf /etc/containerd
rm -rf /var/lib/containerd
rm -rf /run/containerd

# 5. Удаление Docker registry
log_info "5. Удаление Docker registry..."
docker stop docker-registry 2>/dev/null || true
docker rm docker-registry 2>/dev/null || true
docker system prune -af 2>/dev/null || true
rm -rf /opt/registry

# 6. Очистка iptables
log_info "6. Очистка iptables..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# 7. Очистка сетевых интерфейсов
log_info "7. Очистка сетевых интерфейсов..."
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete docker0 2>/dev/null || true

# 8. Очистка маршрутов
log_info "8. Очистка маршрутов..."
ip route del 10.244.0.0/16 2>/dev/null || true
ip route del 10.96.0.0/12 2>/dev/null || true

# 9. Удаление RPM пакетов
log_info "9. Удаление RPM пакетов..."
rpm -qa | grep -E "kubeadm|kubectl|kubelet" | xargs -r rpm -e --nodeps 2>/dev/null || true
rpm -qa | grep -E "docker-ce|docker-ce-cli|containerd.io" | xargs -r rpm -e --nodeps 2>/dev/null || true

# 10. Очистка логов
log_info "10. Очистка логов..."
rm -rf /var/log/pods
rm -rf /var/log/containers
rm -rf /var/log/kube-*

# 11. Восстановление системных настроек
log_info "11. Восстановление системных настроек..."
swapoff -a
sed -i '/swap/d' /etc/fstab
setenforce 1 2>/dev/null || true
rm -f /etc/sysctl.d/k8s.conf

# 12. Перезагрузка systemd
log_info "12. Перезагрузка systemd..."
systemctl daemon-reload

log_info "=== ОЧИСТКА ЗАВЕРШЕНА ==="
echo ""
log_warn "Для полной переустановки рекомендуется перезагрузить сервер:"
echo "  reboot"
CLEAN_SCRIPT

chmod +x "${WORK_DIR}/clean-all.sh"

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
mv "${WORK_DIR}/install-worker.sh" "${WORK_DIR}/final/"
mv "${WORK_DIR}/install-worker-auto.sh" "${WORK_DIR}/final/"
mv "${WORK_DIR}/clean-all.sh" "${WORK_DIR}/final/"

cd "${WORK_DIR}/final"
tar -czf "/tmp/${OUTPUT_ARCHIVE}" .

log_info "=============================================="
log_info "ГОТОВО!"
log_info "Архив создан: /tmp/${OUTPUT_ARCHIVE}"
log_info "Размер: $(du -h /tmp/${OUTPUT_ARCHIVE} 2>/dev/null | cut -f1)"
log_info ""
log_info "Содержимое архива:"
ls -la
log_info ""
log_info "Перенесите архив на целевую ВМ и выполните:"
log_info "  tar -xzf ${OUTPUT_ARCHIVE}"
log_info "  ./install-all.sh"
log_info "=============================================="