#!/bin/bash
# =============================================================================
# user-data-web.sh — Script de User Data para instâncias Web (Portal Luanti)
# =============================================================================
# Este script é executado automaticamente na inicialização de instâncias EC2
# do ASG_WEB. Ele provisiona o ambiente completo do Portal Web com Nginx,
# configura o health check endpoint e instala o CloudWatch Agent para coleta
# de logs e métricas.
#
# Uso: Colar o conteúdo deste script no campo "User Data" do Launch Template
#      LaunchTemplate-WEB no Console AWS.
#
# Placeholders a substituir antes de usar:
#   <AWS_REGION>     — Região AWS (ex: us-east-1, sa-east-1)
#   <S3_BUCKET_URL>  — URL do bucket S3 com os arquivos do portal (opcional)
#   <LOG_GROUP_NAME> — Nome do Log Group no CloudWatch (ex: /aws-luanti/web)
#
# Requisitos atendidos: 4.1, 4.6, 9.6, 14.1
# =============================================================================

set -euo pipefail

# --- Variáveis (placeholders descritivos — sem valores hardcoded) ---
AWS_REGION="<AWS_REGION>"
LOG_GROUP_NAME="<LOG_GROUP_NAME>"

# =============================================================================
# 1. Atualização do sistema
# =============================================================================
echo "[INFO] Atualizando pacotes do sistema..."
dnf update -y

# =============================================================================
# 2. Instalação do Nginx
# =============================================================================
echo "[INFO] Instalando Nginx..."
dnf install -y nginx

# =============================================================================
# 3. Configuração dos arquivos do Portal Web
# =============================================================================
# Os arquivos do portal são criados inline via heredoc para eliminar
# dependências externas. Em produção, considere baixar de um bucket S3
# usando: aws s3 cp s3://<S3_BUCKET_URL>/web/ /usr/share/nginx/html/ --recursive
echo "[INFO] Criando arquivos do Portal Web..."

# --- Configuração do Nginx ---
cat > /etc/nginx/nginx.conf << 'NGINX_CONF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request_method $request_uri $server_protocol" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile        on;
    tcp_nopush      on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name _;

        root /usr/share/nginx/html;
        index index.html;

        # Health check endpoint - retorna HTTP 200 com corpo "OK"
        location /health {
            access_log off;
            default_type text/plain;
            try_files /health.html =404;
        }

        # Servir arquivos estáticos
        location / {
            try_files $uri $uri/ =404;
        }
    }
}
NGINX_CONF

# --- Arquivo de health check ---
cat > /usr/share/nginx/html/health.html << 'HEALTH_EOF'
OK
HEALTH_EOF

# --- Página principal do portal ---
cat > /usr/share/nginx/html/index.html << 'INDEX_EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Luanti - Portal Web</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>AWS Luanti — Portal do Projeto</h1>
        <p>Demonstração de arquitetura AWS com ALB, NLB, Spot Instances e Auto Scaling</p>
    </header>

    <main>
        <section id="servidor">
            <h2>Conectar ao Servidor de Jogo</h2>
            <p>Endereço do servidor Luanti:</p>
            <div class="server-address">
                <code id="server-addr">game.DOMAIN:30000</code>
                <button id="copy-btn" onclick="copyAddress()">Copiar</button>
                <span id="copy-feedback" class="feedback hidden">Copiado!</span>
            </div>
            <p>Abra o cliente Luanti, clique em "Multiplayer" e cole o endereço acima.</p>
        </section>

        <section id="alb">
            <h2>Application Load Balancer (ALB)</h2>
            <p>O ALB opera na Layer 7 (HTTP/HTTPS), realizando terminação TLS e roteamento baseado em conteúdo. Neste projeto, o ALB distribui o tráfego HTTPS do portal web entre as instâncias do ASG_WEB.</p>
        </section>

        <section id="nlb">
            <h2>Network Load Balancer (NLB)</h2>
            <p>O NLB opera na Layer 4 (TCP/UDP), oferecendo passthrough de tráfego com ultra-baixa latência. Aqui, o NLB encaminha pacotes UDP na porta 30000 diretamente para o servidor de jogo Luanti.</p>
        </section>

        <section id="spot">
            <h2>Spot Instances</h2>
            <p>Spot Instances oferecem até 70% de desconto em relação a instâncias On-Demand. O projeto utiliza múltiplos tipos de instância (t3.small, t3a.small, t2.small) para diversificação de capacidade e maior disponibilidade.</p>
        </section>

        <section id="autoscaling">
            <h2>Auto Scaling</h2>
            <p>O Auto Scaling Group monitora a utilização de CPU e escala automaticamente as instâncias web. Com Target Tracking a 70% de CPU e self-healing no grupo de jogo, a infraestrutura mantém alta disponibilidade.</p>
        </section>

        <section id="arquitetura">
            <h2>Arquitetura do Projeto</h2>
            <img src="diagrams/arquitetura.png" alt="Diagrama da arquitetura AWS mostrando VPC com subnets públicas, ALB para tráfego web HTTPS, NLB para tráfego UDP do jogo, Auto Scaling Groups e CloudWatch para monitoramento">
        </section>
    </main>

    <script src="script.js"></script>
</body>
</html>
INDEX_EOF

# --- Estilos CSS ---
cat > /usr/share/nginx/html/styles.css << 'CSS_EOF'
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    line-height: 1.6;
    color: #333;
    max-width: 1200px;
    margin: 0 auto;
    padding: 1rem;
}

header { text-align: center; padding: 2rem 0; border-bottom: 2px solid #232f3e; margin-bottom: 2rem; }
h1 { color: #232f3e; font-size: clamp(1.5rem, 4vw, 2.5rem); }
h2 { color: #ff9900; margin-bottom: 0.5rem; }
section { margin-bottom: 2rem; padding: 1.5rem; border-radius: 8px; background: #f9f9f9; }

.server-address { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; margin: 1rem 0; }
.server-address code { background: #232f3e; color: #ff9900; padding: 0.5rem 1rem; border-radius: 4px; font-size: 1.1rem; }
.server-address button { background: #ff9900; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; font-weight: bold; }
.server-address button:hover { background: #ec7211; }
.feedback { color: #28a745; font-weight: bold; }
.hidden { display: none; }

img { max-width: 100%; height: auto; border-radius: 8px; margin-top: 1rem; }

@media (max-width: 768px) { body { padding: 0.5rem; } section { padding: 1rem; } }
CSS_EOF

# --- JavaScript ---
cat > /usr/share/nginx/html/script.js << 'JS_EOF'
function copyAddress() {
    var addr = document.getElementById('server-addr').textContent;
    var feedback = document.getElementById('copy-feedback');

    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(addr).then(function() {
            showFeedback(feedback);
        }).catch(function() {
            fallbackCopy(addr, feedback);
        });
    } else {
        fallbackCopy(addr, feedback);
    }
}

function fallbackCopy(text, feedback) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
        document.execCommand('copy');
        showFeedback(feedback);
    } catch (e) {
        feedback.textContent = 'Falha ao copiar';
        feedback.classList.remove('hidden');
    }
    document.body.removeChild(textarea);
}

function showFeedback(el) {
    el.textContent = 'Copiado!';
    el.classList.remove('hidden');
    setTimeout(function() { el.classList.add('hidden'); }, 2500);
}
JS_EOF

# --- Criar diretório para imagem de arquitetura (placeholder) ---
mkdir -p /usr/share/nginx/html/diagrams

# --- Ajustar permissões ---
chown -R nginx:nginx /usr/share/nginx/html/
chmod -R 755 /usr/share/nginx/html/

# =============================================================================
# 4. Configuração do endpoint /health
# =============================================================================
# O endpoint /health já está configurado via nginx.conf e health.html acima.
# Ele retorna HTTP 200 com corpo "OK" para o health check do Target Group.
echo "[INFO] Health check endpoint configurado em /health"

# =============================================================================
# 5. Instalação e configuração do CloudWatch Agent
# =============================================================================
echo "[INFO] Instalando CloudWatch Agent..."
dnf install -y amazon-cloudwatch-agent

# Criar configuração do CloudWatch Agent para coleta de logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << CWAGENT_EOF
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
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "${LOG_GROUP_NAME}/nginx-access",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "${LOG_GROUP_NAME}/nginx-error",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "${LOG_GROUP_NAME}/system",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "AWS-Luanti-NLB-ALB/Web",
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
CWAGENT_EOF

# =============================================================================
# 6. Inicialização dos serviços
# =============================================================================
echo "[INFO] Iniciando Nginx..."
systemctl enable --now nginx

echo "[INFO] Iniciando CloudWatch Agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# =============================================================================
# 7. Verificação final
# =============================================================================
echo "[INFO] Verificando serviços..."

# Verificar se Nginx está rodando
if systemctl is-active --quiet nginx; then
    echo "[OK] Nginx está ativo e rodando"
else
    echo "[ERRO] Nginx não iniciou corretamente"
    exit 1
fi

# Verificar health check local
if curl -sf http://localhost/health > /dev/null 2>&1; then
    echo "[OK] Health check endpoint respondendo corretamente"
else
    echo "[AVISO] Health check pode demorar alguns segundos para responder"
fi

echo "[INFO] Provisionamento da instância web concluído com sucesso!"
