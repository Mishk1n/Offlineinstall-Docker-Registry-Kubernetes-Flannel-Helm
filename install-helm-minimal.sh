#!/bin/bash
# install-helm-minimal.sh
# Минимальная офлайн установка Helm

set -e

GREEN='\033[0;32m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Проверка наличия архива
if [[ ! -f "helm-v3.17.2-linux-amd64.tar.gz" ]]; then
    log_info "Скачивание Helm..."
    curl -L -o helm-v3.17.2-linux-amd64.tar.gz \
        "https://get.helm.sh/helm-v3.17.2-linux-amd64.tar.gz"
fi

# Установка
log_info "Установка Helm..."
tar -xzf helm-v3.17.2-linux-amd64.tar.gz
cp linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
rm -rf linux-amd64

log_info "Готово! Версия: $(helm version)"