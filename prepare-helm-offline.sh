#!/bin/bash
# prepare-helm-offline.sh
# Запустить на машине с доступом в интернет
# Создаёт офлайн пакет для установки Helm

set -e

# ============================================
# НАСТРОЙКА ПЕРЕМЕННЫХ
# ============================================
HELM_VERSION="v3.17.2"              # Актуальная версия Helm
ARCH="amd64"                         # Архитектура (amd64, arm64)
WORK_DIR="/tmp/helm-offline-prepare"
OUTPUT_ARCHIVE="helm-offline-${HELM_VERSION}.tar.gz"

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
mkdir -p "${WORK_DIR}"/{rpms,images}
cd "${WORK_DIR}"

log_info "=== НАЧАЛО ПОДГОТОВКИ ОФЛАЙН ПАКЕТА HELM ==="
log_info "Версия Helm: ${HELM_VERSION}"

# ============================================
# 1. СКАЧИВАНИЕ HELM БИНАРНОГО ФАЙЛА
# ============================================
log_info "1. Скачивание Helm бинарного файла..."

# Скачиваем архив с Helm
HELM_TAR="helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
curl -L -o "${WORK_DIR}/${HELM_TAR}" \
    "https://get.helm.sh/${HELM_TAR}" 2>/dev/null

if [[ ! -f "${WORK_DIR}/${HELM_TAR}" ]]; then
    log_error "Не удалось скачать Helm!"
    exit 1
fi

log_info "  Скачан: ${HELM_TAR}"

# Распаковываем для проверки
tar -xzf "${HELM_TAR}" -C "${WORK_DIR}/"
log_info "  Helm версия: $("${WORK_DIR}/linux-${ARCH}/helm" version 2>/dev/null | head -1)"

# ============================================
# 2. СКАЧИВАНИЕ HELM ОБРАЗОВ (Tiller не требуется для v3+)
# ============================================
log_info "2. Скачивание образов Helm (для charts)..."

# Helm 3 не требует Tiller, но могут потребоваться образы для определённых charts
# Скачиваем популярные образы для примера (опционально)
if command -v docker &> /dev/null; then
    log_info "  Скачивание образов (опционально)..."
    
    # Образ для nginx (часто используется в примерах)
    docker pull nginx:latest 2>/dev/null || true
    docker save nginx:latest -o "${WORK_DIR}/images/nginx-latest.tar" 2>/dev/null || true
    
    # Образ для alpine
    docker pull alpine:latest 2>/dev/null || true
    docker save alpine:latest -o "${WORK_DIR}/images/alpine-latest.tar" 2>/dev/null || true
    
    log_info "  Образы сохранены"
else
    log_warn "Docker не установлен, скачивание образов пропущено"
fi

# ============================================
# 3. СОЗДАНИЕ УСТАНОВОЧНОГО СКРИПТА
# ============================================
log_info "3. Создание установочного скрипта..."

cat > "${WORK_DIR}/install-helm.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
# install-helm.sh - офлайн установка Helm
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
HELM_VERSION_PLACEHOLDER

log_info "=== ОФЛАЙН УСТАНОВКА HELM ==="

# ============================================
# 1. УСТАНОВКА HELM
# ============================================
log_info "1. Установка Helm..."

# Распаковка архива
if [[ -f "${SCRIPT_DIR}/helm-${HELM_VERSION_PLACEHOLDER}-linux-amd64.tar.gz" ]]; then
    cd "${SCRIPT_DIR}"
    tar -xzf "helm-${HELM_VERSION_PLACEHOLDER}-linux-amd64.tar.gz"
    
    # Копирование бинарного файла
    cp linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
    
    # Очистка
    rm -rf linux-amd64
    
    log_info "Helm установлен: $(helm version)"
else
    log_error "Архив Helm не найден!"
    exit 1
fi

# ============================================
# 2. НАСТРОЙКА HELM (ДОБАВЛЕНИЕ РЕПОЗИТОРИЕВ - ОПЦИОНАЛЬНО)
# ============================================
log_info "2. Настройка Helm..."

# Создание директории для конфигурации
mkdir -p /root/.config/helm

# Добавление официального репозитория (требуется интернет, пропускаем при офлайн установке)
log_warn "Добавление репозиториев требует интернета"
log_warn "Выполните позже: helm repo add stable https://charts.helm.sh/stable"
log_warn "               helm repo add bitnami https://charts.bitnami.com/bitnami"

# ============================================
# 3. ЗАГРУЗКА ОБРАЗОВ (ЕСЛИ ЕСТЬ)
# ============================================
if [[ -d "${SCRIPT_DIR}/images" ]]; then
    log_info "3. Загрузка Docker образов..."
    
    for tarfile in "${SCRIPT_DIR}/images"/*.tar; do
        if [[ -f "$tarfile" ]]; then
            docker load -i "$tarfile" 2>/dev/null && \
            log_info "  Загружен: $(basename "$tarfile")"
        fi
    done
fi

# ============================================
# 4. ПРОВЕРКА
# ============================================
log_info "4. Проверка установки..."
echo ""
helm version
echo ""
helm help | head -10

log_info "=== УСТАНОВКА HELM ЗАВЕРШЕНА ==="
echo ""
echo "Для проверки:"
echo "  helm version"
echo "  helm list"
echo "  helm repo list"
echo ""
echo "Добавление репозиториев (требуется интернет):"
echo "  helm repo add stable https://charts.helm.sh/stable"
echo "  helm repo add bitnami https://charts.bitnami.com/bitnami"
echo "  helm repo update"
INSTALL_SCRIPT

# Заменяем плейсхолдер на реальную версию
sed -i "s|HELM_VERSION_PLACEHOLDER|${HELM_VERSION}|g" "${WORK_DIR}/install-helm.sh"
chmod +x "${WORK_DIR}/install-helm.sh"

# ============================================
# 4. СОЗДАНИЕ ФИНАЛЬНОГО АРХИВА
# ============================================
log_info "4. Создание финального архива..."

# Организация структуры
mkdir -p "${WORK_DIR}/final"
mv "${WORK_DIR}/"*.tar.gz "${WORK_DIR}/final/" 2>/dev/null || true
mv "${WORK_DIR}/install-helm.sh" "${WORK_DIR}/final/"
if [[ -d "${WORK_DIR}/images" ]]; then
    mv "${WORK_DIR}/images" "${WORK_DIR}/final/" 2>/dev/null || true
fi

# Создание README
cat > "${WORK_DIR}/final/README.txt" << EOF
===========================================
ОФЛАЙН УСТАНОВКА HELM
===========================================

Версия: ${HELM_VERSION}

Структура:
  helm-${HELM_VERSION}-linux-amd64.tar.gz - Бинарный архив Helm
  images/                                 - Дополнительные Docker образы
  install-helm.sh                         - Установочный скрипт

Установка на целевой ВМ:
  1. Распаковать архив
  2. Запустить: ./install-helm.sh
  3. Дождаться завершения

После установки:
  helm version
  helm list

Для добавления репозиториев (требуется интернет):
  helm repo add stable https://charts.helm.sh/stable
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
===========================================
EOF

cd "${WORK_DIR}/final"
tar -czf "/tmp/${OUTPUT_ARCHIVE}" .

log_info "=============================================="
log_info "ГОТОВО!"
log_info "Архив создан: /tmp/${OUTPUT_ARCHIVE}"
log_info "Размер: $(du -h /tmp/${OUTPUT_ARCHIVE} 2>/dev/null | cut -f1)"
log_info ""
log_info "Перенесите архив на целевую ВМ и выполните:"
log_info "  tar -xzf ${OUTPUT_ARCHIVE}"
log_info "  ./install-helm.sh"
log_info "=============================================="