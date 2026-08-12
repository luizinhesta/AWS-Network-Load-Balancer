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
    <title>AWS Luanti ALB/NLB — Portal do Projeto</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>AWS Luanti ALB/NLB</h1>
        <p>Arquitetura AWS com Application Load Balancer e Network Load Balancer para estudo e portfólio</p>
    </header>

    <main>
        <section id="sobre">
            <h2>Sobre o Projeto</h2>
            <p>
                Este projeto demonstra uma arquitetura completa na AWS utilizando Application Load Balancer (ALB)
                e Network Load Balancer (NLB) para balanceamento de carga em diferentes camadas de rede.
                O objetivo é ilustrar as diferenças entre Layer 7 (HTTP/HTTPS) e Layer 4 (TCP/UDP),
                utilizando EC2 Spot Instances, Auto Scaling Groups, Target Groups e boas práticas de segurança e monitoramento.
            </p>
        </section>

        <section id="servidor">
            <h2>Conectar ao Servidor de Jogo</h2>
            <p>Para jogar no servidor Luanti hospedado nesta infraestrutura, utilize o endereço abaixo:</p>
            <div class="server-address">
                <code id="server-addr">game.dev.inhesta.net:30000</code>
                <button id="copy-btn" onclick="copyAddress()">Copiar</button>
                <span id="copy-feedback" class="feedback hidden">Copiado!</span>
            </div>

            <h3>1. Baixar o Luanti</h3>
            <p>O Luanti (antigo Minetest) é um jogo de mundo aberto gratuito e open-source, similar ao Minecraft.</p>
            <ol>
                <li>Acesse o site oficial: <a href="https://www.luanti.org/en/downloads/" target="_blank" rel="noopener noreferrer">luanti.org/downloads</a></li>
                <li>Clique em <strong>"Luanti 5.16.1 - installer, 64-bit (recommended)"</strong> para baixar o instalador Windows.</li>
                <li>Se preferir a versão portátil (sem instalação), baixe o arquivo <code>.zip</code> e extraia em uma pasta.</li>
            </ol>

            <h3>2. Instalar</h3>
            <ol>
                <li>Execute o arquivo <code>luanti-5.16.1.exe</code> baixado.</li>
                <li>Clique em <strong>"Sim"</strong> na permissão de administrador.</li>
                <li>Siga o assistente: aceite os termos, escolha a pasta e clique em <strong>"Instalar"</strong>.</li>
                <li>Após concluir, clique em <strong>"Finalizar"</strong>.</li>
            </ol>

            <h3>3. Configurar e Conectar ao Servidor</h3>
            <ol>
                <li>Abra o <strong>Luanti</strong> pelo Menu Iniciar ou Área de Trabalho.</li>
                <li>Clique na aba <strong>"Jogar Online"</strong>.</li>
                <li>No campo <strong>Endereço</strong> (canto superior direito), digite: <code>game.dev.inhesta.net</code></li>
                <li>No campo <strong>Porta</strong>, mantenha: <code>30000</code></li>
                <li>No campo <strong>Nome</strong>, escolha um nome de usuário (ex: seu nome).</li>
                <li>O campo <strong>Senha</strong> pode ficar vazio.</li>
                <li>Clique em <strong>"Registrar"</strong> (primeira vez) ou <strong>"Entrar"</strong> (se já tiver conta).</li>
            </ol>

            <div class="info-box">
                <strong>Dica:</strong> Após conectar pela primeira vez, o servidor aparecerá na seção "Favoritos" para acesso rápido nas próximas vezes.
            </div>
        </section>

        <section id="educacional">
            <h2>Conceitos da Arquitetura</h2>

            <div class="card">
                <h3>Application Load Balancer (ALB)</h3>
                <p>Opera na Layer 7 (HTTP/HTTPS), realizando terminação TLS e roteamento baseado em conteúdo. Neste projeto, o ALB distribui o tráfego HTTPS do portal web entre as instâncias do ASG.</p>
            </div>

            <div class="card">
                <h3>Network Load Balancer (NLB)</h3>
                <p>Opera na Layer 4 (TCP/UDP), oferecendo passthrough de tráfego com ultra-baixa latência. Aqui, o NLB encaminha pacotes UDP na porta 30000 diretamente para o servidor de jogo Luanti.</p>
            </div>

            <div class="card">
                <h3>Spot Instances</h3>
                <p>Oferecem até 70% de desconto em relação a instâncias On-Demand. O projeto utiliza múltiplos tipos de instância para diversificação de capacidade e maior disponibilidade.</p>
            </div>

            <div class="card">
                <h3>Auto Scaling</h3>
                <p>Monitora a utilização de CPU e escala automaticamente as instâncias web. Com Target Tracking a 70% e self-healing no grupo de jogo, a infraestrutura mantém alta disponibilidade.</p>
            </div>
        </section>
    </main>

    <footer>
        <p>Projeto AWS Luanti ALB/NLB — Laboratório de Estudo e Portfólio</p>
    </footer>

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
    background: #f9fafb;
    max-width: 900px;
    margin: 0 auto;
    padding: 1rem;
}

header { text-align: center; padding: 2rem 1rem; background: #232f3e; color: #fff; border-radius: 8px; margin-bottom: 2rem; }
header h1 { color: #fff; font-size: clamp(1.5rem, 4vw, 2.5rem); margin-bottom: 0.5rem; }
header p { color: rgba(255,255,255,0.85); }

main { padding: 0; }

h2 { color: #232f3e; margin-bottom: 0.5rem; margin-top: 1.5rem; }
h3 { color: #232f3e; margin-top: 1.5rem; margin-bottom: 0.5rem; }
p { margin-bottom: 1rem; color: #4a5568; }
a { color: #146eb4; }
a:hover { color: #ff9900; }

section { margin-bottom: 2rem; }

ol { padding-left: 1.5rem; color: #4a5568; margin-bottom: 1rem; }
ol li { margin-bottom: 0.5rem; }

code { background: #edf2f7; padding: 0.15em 0.4em; border-radius: 4px; font-size: 0.9em; font-family: 'SF Mono', 'Fira Code', monospace; }

.server-address { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; margin: 1rem 0 1.5rem; padding: 1.5rem; background: #fff; border: 2px solid #ff9900; border-radius: 12px; }
.server-address code { font-size: 1.1rem; font-weight: 600; color: #232f3e; padding: 0.5rem 1rem; }
.server-address button { background: #146eb4; color: #fff; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; font-weight: 500; }
.server-address button:hover { background: #0f5a9e; }
.feedback { color: #38a169; font-weight: bold; }
.hidden { display: none; }

.info-box { background: #ebf8ff; border: 1px solid #bee3f8; border-left: 4px solid #146eb4; border-radius: 8px; padding: 1rem 1.5rem; margin-top: 1rem; color: #4a5568; }
.info-box strong { color: #146eb4; }

.card { background: #fff; border: 1px solid #e2e8f0; border-left: 4px solid #146eb4; border-radius: 8px; padding: 1.5rem; margin-bottom: 1rem; }
.card:hover { box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
.card h3 { margin-top: 0; color: #146eb4; }
.card p { margin-bottom: 0; }

footer { background: #232f3e; color: rgba(255,255,255,0.8); text-align: center; padding: 1.5rem; border-radius: 8px; margin-top: 2rem; }
footer p { color: rgba(255,255,255,0.8); margin-bottom: 0; }

@media (max-width: 768px) { body { padding: 0.5rem; } }
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
