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
REGISTRY="localhost:5000"  # Registry на master узле
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
# 2. НАСТРОЙКА HOSTS (ДОБАВИТЬ MASTER IP)
# ============================================
log_info "2. Настройка /etc/hosts..."
read -p "Введите IP адрес MASTER узла: " MASTER_IP

if [[ -n "$MASTER_IP" ]]; then
    if ! grep -q "$MASTER_IP" /etc/hosts; then
        echo "$MASTER_IP master" >> /etc/hosts
        log_info "Добавлена запись: $MASTER_IP master"
    fi
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

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml 2>/dev/null || true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i "s|sandbox_image = .*|sandbox_image = \"${REGISTRY}/pause:3.10\"|" /etc/containerd/config.toml

systemctl restart containerd
systemctl enable --now kubelet

# ============================================
# 6. ОЖИДАНИЕ JOIN КОМАНДЫ
# ============================================
log_info "6. Ожидание join команды..."

echo ""
echo "=============================================="
echo "УСТАНОВКА WORKER УЗЛА ЗАВЕРШЕНА!"
echo "=============================================="
echo ""
echo "Теперь выполните на MASTER узле:"
echo "  kubeadm token create --print-join-command"
echo ""
echo "Затем скопируйте полученную команду и выполните её здесь"
echo "Пример команды:"
echo "  kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo "После присоединения проверьте на master: kubectl get nodes"
echo "=============================================="