# Arquitetura do Projeto AWS Luanti ALB/NLB

Este documento apresenta a arquitetura completa do projeto AWS Luanti ALB/NLB por meio de diagramas detalhados e descrições técnicas. O objetivo é fornecer uma visão clara de como os componentes interagem, desde a topologia de rede até o monitoramento e observabilidade.

## Índice

1. [Topologia de Rede](#1-topologia-de-rede)
2. [Fluxo de Tráfego Web (Layer 7)](#2-fluxo-de-tráfego-web-layer-7)
3. [Fluxo de Tráfego Game (Layer 4)](#3-fluxo-de-tráfego-game-layer-4)
4. [Componentes de Segurança](#4-componentes-de-segurança)
5. [Auto Scaling e Monitoramento](#5-auto-scaling-e-monitoramento)
6. [Visão Geral da Arquitetura](#6-visão-geral-da-arquitetura)

## Documentos Relacionados

- [Guia de Implantação Manual (13 blocos)](./IMPLANTACAO-AWS.md)

---

## 1. Topologia de Rede

A topologia de rede ilustra a estrutura da VPC, incluindo as subnets públicas distribuídas em duas Availability Zones, o Internet Gateway que fornece conectividade com a internet, e as Route Tables que direcionam o tráfego. Todos os recursos são implantados em subnets públicas com atribuição automática de IP público, eliminando a necessidade de NAT Gateways.

```mermaid
graph TB
    subgraph Internet["Internet"]
        USERS["Usuários / Jogadores"]
    end

    subgraph AWS["AWS Cloud"]
        IGW["Internet Gateway<br/>igw-luanti"]

        subgraph VPC["VPC - 10.0.0.0/16<br/>AWS-Luanti-NLB-ALB-Lab-VPC"]
            subgraph RT["Route Table Pública<br/>0.0.0.0/0 → IGW"]
            end

            subgraph AZ1["Availability Zone 1 (ex: us-east-1a)"]
                SUBNET1["Subnet Pública 1<br/>10.0.1.0/24<br/>Auto-assign IPv4: Enabled"]
                EC2_WEB1["EC2 Web (Nginx)<br/>t3.small / Spot"]
                EC2_GAME1["EC2 Game (Docker)<br/>t3.small / Spot"]
            end

            subgraph AZ2["Availability Zone 2 (ex: us-east-1b)"]
                SUBNET2["Subnet Pública 2<br/>10.0.2.0/24<br/>Auto-assign IPv4: Enabled"]
                EC2_WEB2["EC2 Web (Nginx)<br/>t3.small / Spot"]
            end

            ALB["Application Load Balancer<br/>alb-luanti-web<br/>(presente em AZ1 e AZ2)"]
            NLB["Network Load Balancer<br/>nlb-luanti-game<br/>(presente em AZ1 e AZ2)"]
        end
    end

    USERS --> IGW
    IGW --> ALB
    IGW --> NLB
    ALB --> SUBNET1
    ALB --> SUBNET2
    NLB --> SUBNET1
    RT -.->|associada| SUBNET1
    RT -.->|associada| SUBNET2
    SUBNET1 --- EC2_WEB1
    SUBNET1 --- EC2_GAME1
    SUBNET2 --- EC2_WEB2
```

### Detalhes da Topologia

| Componente | Configuração | Descrição |
|------------|-------------|-----------|
| VPC | 10.0.0.0/16 | Rede virtual privada com 65.536 endereços disponíveis |
| Subnet Pública 1 | 10.0.1.0/24 (AZ-1) | 256 endereços na primeira Availability Zone |
| Subnet Pública 2 | 10.0.2.0/24 (AZ-2) | 256 endereços na segunda Availability Zone |
| Internet Gateway | igw-luanti | Conectividade bidirecional com a internet |
| Route Table | 0.0.0.0/0 → IGW | Rota padrão para todo tráfego de saída |

Ambas as subnets possuem atribuição automática de IP público habilitada, permitindo que as instâncias EC2 sejam acessíveis diretamente pela internet através dos Load Balancers.

Para mais detalhes sobre a configuração de rede, consulte a documentação em `docs/REDE.md`.

---

## 2. Fluxo de Tráfego Web (Layer 7)

O fluxo de tráfego web demonstra como as requisições HTTPS dos usuários são processadas pelo Application Load Balancer. O ALB opera na Layer 7 (camada de aplicação), realizando a terminação TLS com certificado ACM e redirecionando requisições HTTP para HTTPS automaticamente. Após a terminação TLS, o tráfego é encaminhado em HTTP para as instâncias EC2 que executam Nginx.

```mermaid
sequenceDiagram
    participant User as Usuário (Browser)
    participant DNS as Route 53<br/>www.DOMAIN
    participant ALB as ALB (Layer 7)<br/>alb-luanti-web
    participant ACM as Certificado ACM<br/>TLS 1.2+
    participant TG as Target Group WEB<br/>HTTP:80
    participant EC2 as EC2 Nginx<br/>(Spot Instance)

    User->>DNS: Resolve www.DOMAIN
    DNS-->>User: Alias → ALB DNS name

    Note over User,ALB: Cenário 1: Requisição HTTPS (porta 443)
    User->>ALB: HTTPS:443 (TLS encrypted)
    ALB->>ACM: Valida certificado TLS
    ACM-->>ALB: Certificado válido
    ALB->>ALB: Terminação TLS (decrypt)
    ALB->>TG: Forward HTTP:80
    TG->>EC2: HTTP:80 (round-robin)
    EC2-->>User: HTML/CSS/JS (200 OK)

    Note over User,ALB: Cenário 2: Requisição HTTP (porta 80)
    User->>ALB: HTTP:80
    ALB-->>User: 301 Redirect → HTTPS:443
```

### Características do Fluxo Web

- **Terminação TLS**: O ALB decifra o tráfego HTTPS usando o certificado ACM, eliminando a necessidade de gerenciar certificados nas instâncias EC2.
- **Redirect HTTP→HTTPS**: Toda requisição na porta 80 recebe resposta 301 (permanent redirect) para a porta 443, garantindo que todo tráfego seja criptografado.
- **Health Check**: O Target Group verifica a saúde das instâncias via `GET /health` (HTTP 200) a cada 30 segundos. Instâncias que falham 3 verificações consecutivas são removidas do pool.
- **Balanceamento**: O ALB distribui o tráfego entre as instâncias registradas no Target Group usando o algoritmo round-robin.

Para mais detalhes sobre o ALB, consulte a documentação em `docs/ALB.md`.

---

## 3. Fluxo de Tráfego Game (Layer 4)

O fluxo de tráfego do jogo demonstra como os pacotes UDP dos jogadores são roteados pelo Network Load Balancer. O NLB opera na Layer 4 (camada de transporte), realizando passthrough do tráfego UDP sem inspeção de conteúdo. Isso garante latência mínima e preservação do IP de origem, essenciais para a experiência de jogo em tempo real.

```mermaid
sequenceDiagram
    participant Player as Jogador<br/>(Cliente Luanti)
    participant DNS as Route 53<br/>game.DOMAIN
    participant NLB as NLB (Layer 4)<br/>nlb-luanti-game
    participant TG as Target Group GAME<br/>UDP:30000
    participant EC2 as EC2 Docker<br/>(Servidor Luanti)
    participant HC as Health Check<br/>TCP:8080

    Player->>DNS: Resolve game.DOMAIN
    DNS-->>Player: Alias → NLB DNS name

    Player->>NLB: UDP:30000 (Luanti Protocol)
    NLB->>TG: UDP:30000 (passthrough)
    Note over NLB,TG: Sem inspeção de conteúdo<br/>IP de origem preservado
    TG->>EC2: UDP:30000
    EC2-->>Player: UDP:30000 (Game Data)

    Note over HC,EC2: Health Check (paralelo)
    HC->>EC2: TCP SYN :8080
    EC2-->>HC: TCP SYN-ACK (socat health check)
    Note over HC: Target healthy ✓
```

### Características do Fluxo Game

- **Passthrough UDP**: O NLB encaminha os pacotes UDP sem modificação, mantendo a baixa latência necessária para jogos.
- **Preservação de IP**: O IP de origem do jogador é preservado, permitindo que o servidor identifique cada cliente.
- **Health Check TCP (porta 8080)**: Como UDP não possui mecanismo nativo de confirmação de conexão, o health check utiliza TCP na porta 8080, onde um serviço `socat` verifica se o container Luanti está rodando e responde OK ao NLB.
- **Single Target**: O ASG-GAME mantém exatamente 1 instância (min=1, max=1), funcionando como self-healing sem escalabilidade horizontal.

Para mais detalhes sobre o NLB, consulte a documentação em `docs/NLB.md`.

---

## 4. Componentes de Segurança

O diagrama de segurança ilustra os Security Groups, IAM Roles e suas relações. A arquitetura segue o princípio de menor privilégio: cada componente recebe apenas as permissões necessárias para sua função, e o tráfego entre camadas é controlado por referência de Security Group ID.

```mermaid
graph TB
    subgraph Internet["Internet (0.0.0.0/0)"]
        USER["Usuários Web"]
        PLAYER["Jogadores UDP"]
        ADMIN["Operador SSH"]
    end

    subgraph SGs["Security Groups"]
        subgraph SG_ALB["SG-ALB"]
            ALB_IN["Inbound:<br/>TCP 80 de 0.0.0.0/0<br/>TCP 443 de 0.0.0.0/0"]
            ALB_OUT["Outbound:<br/>All traffic"]
        end

        subgraph SG_WEB["SG-WEB"]
            WEB_IN["Inbound:<br/>TCP 80 de SG-ALB (por SG ID)<br/>TCP 22 de &lt;MEU_IP&gt;/32"]
            WEB_OUT["Outbound:<br/>All traffic"]
        end

        subgraph SG_GAME["SG-GAME"]
            GAME_IN["Inbound:<br/>UDP 30000 de 0.0.0.0/0<br/>TCP 8080 de 10.0.0.0/16 (NLB HC)<br/>TCP 22 de &lt;MEU_IP&gt;/32"]
            GAME_OUT["Outbound:<br/>All traffic"]
        end
    end

    USER -->|"TCP 80, 443"| SG_ALB
    PLAYER -->|"UDP 30000"| SG_GAME
    ADMIN -->|"TCP 22"| SG_WEB
    ADMIN -->|"TCP 22"| SG_GAME
    SG_ALB -->|"TCP 80 (ref by SG ID)"| SG_WEB
```

### IAM Roles e Permissões

```mermaid
graph LR
    subgraph IAM["IAM - Menor Privilégio"]
        subgraph ROLE_WEB["IAM Role: WebRole"]
            POLICY_WEB["Políticas:<br/>• cloudwatch:PutMetricData<br/>• logs:CreateLogGroup<br/>• logs:CreateLogStream<br/>• logs:PutLogEvents<br/>• logs:DescribeLogStreams"]
            IP_WEB["Instance Profile:<br/>WebInstanceProfile"]
        end

        subgraph ROLE_GAME["IAM Role: GameRole"]
            POLICY_GAME["Políticas:<br/>• cloudwatch:PutMetricData<br/>• logs:CreateLogGroup<br/>• logs:CreateLogStream<br/>• logs:PutLogEvents<br/>• logs:DescribeLogStreams"]
            IP_GAME["Instance Profile:<br/>GameInstanceProfile"]
        end
    end

    subgraph EC2s["Instâncias EC2"]
        WEB_EC2["EC2 Web (Nginx)"]
        GAME_EC2["EC2 Game (Docker)"]
    end

    subgraph CW["CloudWatch"]
        METRICS["Métricas Customizadas"]
        LOGS["Log Groups"]
    end

    IP_WEB -->|"associado"| WEB_EC2
    IP_GAME -->|"associado"| GAME_EC2
    WEB_EC2 -->|"PutMetricData"| METRICS
    WEB_EC2 -->|"PutLogEvents"| LOGS
    GAME_EC2 -->|"PutMetricData"| METRICS
    GAME_EC2 -->|"PutLogEvents"| LOGS
```

### Princípios de Segurança Aplicados

| Princípio | Implementação |
|-----------|--------------|
| Menor privilégio (SGs) | SG-WEB aceita tráfego apenas do SG-ALB, não de 0.0.0.0/0 |
| Referência por SG ID | Regras cross-reference usam Security Group ID em vez de CIDR |
| Menor privilégio (IAM) | Roles sem wildcards em Actions, Resource limitado ao escopo necessário |
| Separação de responsabilidades | Roles distintas para web e game com permissões independentes |
| Acesso SSH restrito | Porta 22 disponível apenas para o IP do operador |
| Sem regras desnecessárias | Nenhuma porta de entrada além das explicitamente definidas |

Para mais detalhes sobre a configuração de segurança, consulte a documentação em `docs/SEGURANCA.md`.

---

## 5. Auto Scaling e Monitoramento

Este diagrama mostra a integração entre os Auto Scaling Groups, CloudWatch (métricas e alarmes), SNS (notificações) e as políticas de escalabilidade. O ASG-WEB escala horizontalmente com base na utilização de CPU, enquanto o ASG-GAME opera em modo self-healing com capacidade fixa.

```mermaid
graph TB
    subgraph ASGs["Auto Scaling Groups"]
        subgraph ASG_WEB["ASG-WEB"]
            ASG_WEB_CFG["Configuração:<br/>Min: 1 | Desejado: 1 | Max: 2<br/>Health Check: ELB (Grace: 300s)<br/>AZs: 2 zonas<br/>Launch Template: LT-WEB"]
            POLICY["Target Tracking Policy:<br/>Métrica: CPUUtilization<br/>Target: 70%<br/>Cooldown: 300s"]
        end

        subgraph ASG_GAME["ASG-GAME"]
            ASG_GAME_CFG["Configuração:<br/>Min: 1 | Desejado: 1 | Max: 1<br/>Health Check: ELB (Grace: 300s)<br/>AZs: 2 zonas<br/>Launch Template: LT-GAME<br/>Modo: Self-Healing"]
        end
    end

    subgraph CloudWatch["CloudWatch"]
        subgraph Metrics["Métricas (período: 60s)"]
            M_ALB["ALB:<br/>RequestCount<br/>TargetResponseTime<br/>HTTPCode_ELB_5XX"]
            M_NLB["NLB:<br/>ProcessedBytes<br/>ActiveFlowCount"]
            M_EC2["EC2:<br/>CPUUtilization<br/>NetworkIn/Out<br/>DiskReadOps/WriteOps"]
        end

        subgraph Alarms["Alarmes"]
            A_CPU["Alarme CPU Alta<br/>CPUUtilization > 80%<br/>3 datapoints @ 60s"]
            A_5XX["Alarme Erros 5XX<br/>HTTPCode_ELB_5XX > 10<br/>1 datapoint @ 300s"]
        end

        subgraph Logs["CloudWatch Logs"]
            LG_SYS["Log Group: /var/log/messages<br/>Retenção: 7 dias"]
            LG_APP["Log Group: Application Logs<br/>Retenção: 7 dias"]
        end
    end

    subgraph Notifications["Notificações"]
        SNS["SNS Topic<br/>luanti-alarms"]
        EMAIL["Email do Operador<br/>&lt;SNS_EMAIL&gt;"]
    end

    M_EC2 -->|"alimenta"| A_CPU
    M_ALB -->|"alimenta"| A_5XX
    A_CPU -->|"publica"| SNS
    A_5XX -->|"publica"| SNS
    SNS -->|"notifica"| EMAIL
    M_EC2 -->|"CPUUtilization"| POLICY
    POLICY -->|"scale-out/in"| ASG_WEB_CFG
```

### Comportamento de Auto Scaling

| Evento | ASG-WEB | ASG-GAME |
|--------|---------|----------|
| CPU > 70% (sustentada) | Scale-out: lança nova instância (até max=2) | Não se aplica (max=1) |
| CPU < 70% (estabilizada) | Scale-in: termina instância extra (até min=1) | Não se aplica |
| Instância unhealthy | Substitui instância após grace period (300s) | Substitui instância após grace period (300s) |
| Spot interrompida | ASG lança nova instância automaticamente | ASG lança nova instância automaticamente |
| Health check ELB falha | Marca instância como unhealthy → substitui | Marca instância como unhealthy → substitui |

### Alarmes e Thresholds

| Alarme | Métrica | Condição | Período | Ação |
|--------|---------|----------|---------|------|
| CPU Alta | CPUUtilization | > 80% por 3 datapoints | 60s cada | Publica em SNS |
| Erros 5XX | HTTPCode_ELB_5XX | > 10 ocorrências | 300s (5 min) | Publica em SNS |

### Fluxo de Self-Healing

1. Instância EC2 falha (crash, Spot interruption, container morto)
2. Health check do Target Group detecta falha (3 verificações consecutivas falharam)
3. ASG marca a instância como unhealthy
4. ASG termina a instância unhealthy
5. ASG lança nova instância usando o Launch Template
6. User Data provisiona a aplicação automaticamente
7. Após grace period (300s), health check confirma a nova instância como healthy

Para mais detalhes sobre Spot Instances e Auto Scaling, consulte a documentação em `docs/SPOT-AUTOSCALING.md`.
Para configuração detalhada de monitoramento, consulte a documentação em `docs/MONITORAMENTO.md`.

---

## 6. Visão Geral da Arquitetura

O diagrama a seguir apresenta uma visão consolidada de todos os componentes e suas interações, desde a entrada do tráfego pela internet até as instâncias EC2, passando por DNS, Load Balancers, Target Groups e Auto Scaling Groups.

```mermaid
graph TB
    subgraph Internet["Internet"]
        U["Usuário Web<br/>(HTTPS)"]
        P["Jogador Luanti<br/>(UDP:30000)"]
    end

    subgraph Route53["Route 53 (DNS)"]
        DNS_WEB["www.DOMAIN<br/>Alias A → ALB"]
        DNS_GAME["game.DOMAIN<br/>Alias A → NLB"]
    end

    subgraph VPC["VPC 10.0.0.0/16"]
        IGW["Internet Gateway"]

        subgraph LoadBalancers["Load Balancers"]
            ALB["ALB - alb-luanti-web<br/>Layer 7 | HTTPS:443<br/>HTTP:80 → 301 HTTPS<br/>SG: SG-ALB"]
            NLB["NLB - nlb-luanti-game<br/>Layer 4 | UDP:30000<br/>Passthrough"]
        end

        subgraph TargetGroups["Target Groups"]
            TG_WEB["TG-WEB<br/>HTTP:80<br/>Health: GET /health<br/>Interval: 30s | 3/3"]
            TG_GAME["TG-GAME<br/>UDP:30000<br/>Health: TCP:8080 (Override)<br/>Interval: 30s | 3/3"]
        end

        subgraph AZ1["AZ-1 (10.0.1.0/24)"]
            WEB1["EC2 Web<br/>Nginx + Portal<br/>SG: SG-WEB<br/>Spot Instance"]
            GAME1["EC2 Game<br/>Docker + Luanti<br/>SG: SG-GAME<br/>Spot Instance"]
        end

        subgraph AZ2["AZ-2 (10.0.2.0/24)"]
            WEB2["EC2 Web<br/>Nginx + Portal<br/>SG: SG-WEB<br/>Spot Instance"]
        end

        ASG_WEB["ASG-WEB<br/>Min:1 Des:1 Max:2<br/>CPU Target: 70%"]
        ASG_GAME["ASG-GAME<br/>Min:1 Des:1 Max:1<br/>Self-Healing"]
    end

    subgraph Monitoring["Observabilidade"]
        CW["CloudWatch<br/>Métricas | Alarmes | Logs"]
        SNS["SNS Topic<br/>Notificações Email"]
    end

    U --> DNS_WEB --> ALB
    P --> DNS_GAME --> NLB
    ALB --> TG_WEB
    NLB --> TG_GAME
    TG_WEB --> ASG_WEB
    TG_GAME --> ASG_GAME
    ASG_WEB --> WEB1 & WEB2
    ASG_GAME --> GAME1
    IGW --- ALB & NLB
    WEB1 & WEB2 & GAME1 -->|"métricas e logs"| CW
    CW -->|"alarmes"| SNS
```

### Resumo dos Componentes

| Camada | Componente | Função |
|--------|-----------|--------|
| DNS | Route 53 | Resolução de nomes com Alias records para ALB e NLB |
| Edge | ALB (Layer 7) | Terminação TLS, redirect HTTP→HTTPS, balanceamento web |
| Edge | NLB (Layer 4) | Passthrough UDP para tráfego de jogo |
| Roteamento | Target Groups | Registro de instâncias e health checks |
| Compute | Auto Scaling Groups | Gerenciamento de capacidade e self-healing |
| Compute | EC2 Spot Instances | Execução das aplicações com otimização de custos |
| Segurança | Security Groups | Controle de tráfego entre camadas |
| Segurança | IAM Roles | Permissões de menor privilégio para instâncias |
| Observabilidade | CloudWatch | Métricas, alarmes e logs centralizados |
| Notificação | SNS | Envio de alertas por email ao operador |

---

## Próximos Passos

Para implantar esta arquitetura, siga o [Guia de Implantação Manual](./IMPLANTACAO-AWS.md) que contém instruções passo a passo para criação de cada recurso via Console AWS, organizadas em 13 blocos sequenciais.
