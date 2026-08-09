#!/bin/bash
# =============================================================================
# User Data - Provisionamento da Instância de Jogo (Luanti/Minetest)
# =============================================================================
# Este script é executado automaticamente na inicialização da instância EC2
# pelo Launch Template (LaunchTemplate-GAME).
#
# Função: Instalar Docker, baixar a imagem do servidor Luanti e iniciar o
# container na porta UDP 30000. Também configura o CloudWatch Agent para
# coleta de logs e métricas.
#
# Sistema Operacional: Amazon Linux 2023
# Tempo máximo de provisionamento: 300 segundos
#
# IMPORTANTE: Substituir os placeholders <NOME_DA_VARIÁVEL> pelos valores
# reais antes de colar no campo User Data do Launch Template no Console AWS.
# =============================================================================

set -euo pipefail

# --- Variáveis (placeholders) ------------------------------------------------
AWS_REGION="<AWS_REGION>"
LOG_GROUP_NAME="<LOG_GROUP_NAME>"

# --- Registrar início do provisionamento -------------------------------------
echo "[user-data-game] Início do provisionamento: $(date)"

# =============================================================================
# 1. Atualização do sistema
# =============================================================================
echo "[user-data-game] Atualizando pacotes do sistema..."
dnf update -y

# =============================================================================
# 2. Instalação do Docker
# =============================================================================
echo "[user-data-game] Instalando Docker..."
dnf install -y docker

# Habilitar e iniciar o serviço Docker
echo "[user-data-game] Habilitando e iniciando serviço Docker..."
systemctl enable --now docker

# Adicionar o usuário ec2-user ao grupo docker (permite uso sem sudo)
usermod -aG docker ec2-user

# =============================================================================
# 3. Download da imagem e inicialização do container Luanti
# =============================================================================
echo "[user-data-game] Baixando imagem do servidor Luanti..."
docker pull linuxserver/minetest:latest

echo "[user-data-game] Iniciando container do servidor Luanti na porta UDP 30000..."
docker run -d \
  --name luanti-server \
  --restart unless-stopped \
  -p 30000:30000/udp \
  -e PUID=1000 \
  -e PGID=1000 \
  -e "CLI_ARGS=--gameid minetest" \
  linuxserver/minetest:latest

# Verificar se o container está rodando
echo "[user-data-game] Verificando status do container..."
docker ps --filter "name=luanti-server" --format "{{.Status}}"

# =============================================================================
# 4. Instalação e configuração do CloudWatch Agent
# =============================================================================
echo "[user-data-game] Instalando CloudWatch Agent..."
dnf install -y amazon-cloudwatch-agent

# Criar arquivo de configuração do CloudWatch Agent
echo "[user-data-game] Configurando CloudWatch Agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "region": "${AWS_REGION}",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${LOG_GROUP_NAME}/var/log/messages",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/lib/docker/containers/*/*.log",
            "log_group_name": "${LOG_GROUP_NAME}/docker/luanti-server",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "AWS-Luanti-NLB-ALB/Game",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    }
  }
}
EOF

# Iniciar o CloudWatch Agent com a configuração criada
echo "[user-data-game] Iniciando CloudWatch Agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# =============================================================================
# 5. Finalização
# =============================================================================
echo "[user-data-game] Provisionamento concluído com sucesso: $(date)"
echo "[user-data-game] Container Luanti rodando na porta UDP 30000"
