## Офлайн установки Helm - менеджера пакетов для Kubernetes.
### Инструкция по использованию

Этап 1: Подготовка на машине с интернетом
```bash 
# 1. Скачать скрипт prepare-helm-offline.sh
# 2. Дать права на выполнение
chmod +x prepare-helm-offline.sh

# 3. Запустить подготовку
./prepare-helm-offline.sh

# Результат: /tmp/helm-offline-v3.17.2.tar.gz
```
Этап 2: Перенос на целевую ВМ
```bash
# Скопировать архив на целевую машину
scp /tmp/helm-offline-v3.17.2.tar.gz root@target-vm:/opt/
```
Этап 3: Установка на целевой ВМ
```bash
# 1. Распаковать архив
cd /opt
tar -xzf helm-offline-v3.17.2.tar.gz
cd helm-offline-*

# 2. Запустить установку
chmod +x install-helm.sh
./install-helm.sh
```
### Проверка установки
```bash
# Проверка версии
helm version

# Ожидаемый вывод:
# version.BuildInfo{Version:"v3.17.2", GitCommit:"...", GitTreeState:"clean", GoVersion:"..."}

# Проверка списка репозиториев
helm repo list

# Проверка помощи
helm --help
```
### 📦 Версии Helm

| Версия | Дата выпуска | Поддержка Kubernetes |
|:-------|:-------------|:---------------------|
| v3.17.2 | 2025-01 | 1.29 - 1.32 |
| v3.16.0 | 2024-09 | 1.28 - 1.31 |
| v3.15.0 | 2024-06 | 1.27 - 1.30 |

> **✅ Рекомендуемая версия:** `v3.17.2` (совместима с Kubernetes 1.33.10)

### Удаление Helm
```bash
# Удаление бинарного файла
rm -f /usr/local/bin/helm

### Удаление конфигурации
rm -rf /root/.config/helm
rm -rf /root/.cache/helm
```
