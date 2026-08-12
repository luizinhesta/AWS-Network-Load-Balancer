# AWS Load Balancing ALB/NLB - Luanti

## Descrição do Projeto

Este projeto demonstra uma arquitetura completa na Amazon Web Services (AWS) para fins de estudo, laboratório e portfólio profissional. O objetivo principal é ilustrar as diferenças práticas entre Application Load Balancer (ALB) e Network Load Balancer (NLB), utilizando EC2 Spot Instances, Auto Scaling Groups, Target Groups e os conceitos fundamentais de balanceamento de carga nas camadas Layer 7 (HTTP/HTTPS) e Layer 4 (TCP/UDP).

A arquitetura é composta por dois componentes principais: um portal web informativo acessado via ALB com terminação TLS (HTTPS) e um servidor de jogo Luanti (anteriormente Minetest) acessado via NLB na porta UDP 30000. O portal web exibe informações educacionais sobre os serviços AWS utilizados, enquanto o servidor de jogo permite conexões diretas de jogadores através do protocolo UDP, demonstrando como o NLB opera na Layer 4 sem inspeção de conteúdo.

Toda a infraestrutura é criada manualmente via Console AWS, sem uso de CloudFormation, Terraform, CDK ou qualquer ferramenta de Infrastructure as Code. Esta abordagem didática permite compreender cada recurso individualmente, suas dependências e configurações. O repositório contém o código da aplicação web, configuração Docker do servidor de jogo, scripts de User Data para provisionamento automático, diagramas de arquitetura e guias completos de implantação passo a passo.

---

## Índice de Documentação

| Documento | Descrição |
|-----------|-----------|
| [ARQUITETURA.md](ARQUITETURA.md) | Diagramas detalhados da arquitetura (topologia, tráfego, segurança, Auto Scaling, monitoramento) |
| [IMPLANTACAO-AWS.md](IMPLANTACAO-AWS.md) | Guia passo a passo para criação manual de todos os recursos via Console AWS (13 blocos) |

---

## Estrutura de Diretórios

| Diretório | Descrição |
|-----------|-----------|
| `web/` | Portal web informativo com HTML, CSS, JavaScript e configuração Nginx |
| `game/` | Configuração Docker do servidor Luanti (Dockerfile, docker-compose, configs) |
| `scripts/` | Scripts de User Data para provisionamento EC2 e utilitários de validação AWS CLI |
| `docs/` | Documentação técnica de referência (ALB, NLB, rede, segurança, monitoramento, Spot/Auto Scaling, troubleshooting) |
| `diagrams/` | Diagramas de arquitetura em formato Mermaid e imagens exportadas |

---

## Comparação ALB vs NLB

| Critério | ALB (Application Load Balancer) | NLB (Network Load Balancer) |
|----------|--------------------------------|----------------------------|
| Camada OSI | Layer 7 (Aplicação) | Layer 4 (Transporte) |
| Protocolos | HTTP, HTTPS, gRPC | TCP, UDP, TLS |
| Terminação TLS | Sim, no próprio load balancer | Opcional (TLS passthrough disponível) |
| Preservação de IP do cliente | Não (usa X-Forwarded-For header) | Sim, IP original preservado nativamente |
| Caso de uso neste projeto | Portal web com HTTPS e redirect HTTP→HTTPS | Servidor de jogo Luanti via UDP porta 30000 |
| Roteamento | Baseado em conteúdo (path, host, headers) | Baseado em conexão (IP + porta) |
| Latência | Maior (inspeção de conteúdo HTTP) | Ultra-baixa (passthrough sem inspeção) |
| Health Check | HTTP/HTTPS com path customizado | TCP, HTTP ou HTTPS (porta Override recomendada para UDP) |

---

## Diagrama de Arquitetura

```mermaid
graph TB
    subgraph Internet
        U[Usuário Web]
        P[Jogador Luanti]
    end

    subgraph Route53[Route 53]
        DNS_WEB[www.DOMAIN → ALB]
        DNS_GAME[game.DOMAIN → NLB]
    end

    subgraph VPC[VPC 10.0.0.0/16]
        subgraph PublicSubnets[Subnets Públicas]
            subgraph AZ1[AZ-1 — 10.0.1.0/24]
                EC2_WEB_1[EC2 Web - Nginx]
                EC2_GAME_1[EC2 Game - Docker]
            end
            subgraph AZ2[AZ-2 — 10.0.2.0/24]
                EC2_WEB_2[EC2 Web - Nginx]
            end
        end

        IGW[Internet Gateway]
        ALB[ALB - Layer 7<br/>HTTPS:443 + HTTP:80→301]
        NLB[NLB - Layer 4<br/>UDP:30000]

        TG_WEB[Target Group WEB<br/>HTTP:80 /health]
        TG_GAME[Target Group GAME<br/>UDP:30000<br/>Health: TCP:8080]

        ASG_WEB[ASG Web<br/>Min:1 Des:1 Max:2<br/>CPU Target 70%]
        ASG_GAME[ASG Game<br/>Min:1 Des:1 Max:1<br/>Self-Healing]
    end

    subgraph Monitoring[CloudWatch]
        CW_METRICS[Métricas ALB/NLB/EC2]
        CW_ALARMS[Alarmes CPU/5XX]
        CW_LOGS[Logs Agent]
        SNS[SNS Topic → Email]
    end

    U -->|HTTPS| DNS_WEB --> ALB
    P -->|UDP:30000| DNS_GAME --> NLB
    ALB --> TG_WEB --> ASG_WEB
    NLB --> TG_GAME --> ASG_GAME
    ASG_WEB --> EC2_WEB_1 & EC2_WEB_2
    ASG_GAME --> EC2_GAME_1
    IGW --- ALB & NLB
    CW_ALARMS --> SNS
```

---

## Instruções de Uso

### Pré-requisitos

- Conta AWS ativa com permissões administrativas
- AWS CLI instalada e configurada localmente (`aws configure`)
- Domínio registrado com Hosted Zone no Route 53
- Certificado ACM validado para o domínio (validação DNS)
- Git instalado para clonar o repositório

### Implantação

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/seu-usuario/AWS-Luanti-NLB-ALB.git
   cd AWS-Luanti-NLB-ALB
   ```

2. **Configure as variáveis de ambiente:**
   ```bash
   cp .env.example .env
   # Edite .env com seus valores reais (região, domínio, conta AWS, etc.)
   ```

3. **Siga o guia de implantação:**
   - Abra [IMPLANTACAO-AWS.md](IMPLANTACAO-AWS.md) e execute os 13 blocos sequencialmente no Console AWS
   - Cada bloco contém instruções detalhadas, valores a preencher e checkpoints de validação

4. **Execute os scripts de User Data:**
   - Os scripts em `scripts/user-data-web.sh` e `scripts/user-data-game.sh` são colados no campo User Data dos Launch Templates durante a criação no Console

### Atualização do Portal Web (Deploy de Novas Versões)

O portal web é provisionado via User Data no Launch Template. Para publicar uma nova versão:

1. **Atualize o User Data no Launch Template:**
   - Acesse **EC2 → Launch Templates → AWS-Luanti-NLB-ALB-Lab-LT-WEB**
   - Clique em **Actions → Modify template (Create new version)**
   - Atualize o conteúdo do campo **User Data** com o novo `scripts/user-data-web.sh`
   - Clique em **Create template version**
   - Marque a nova versão como **Default version**

2. **Execute um Instance Refresh no Auto Scaling Group:**
   - Acesse **EC2 → Auto Scaling Groups → ASG-WEB**
   - Clique na aba **Instance refresh** → **Start instance refresh**
   - Em **Minimum healthy percentage**, defina `0%` (para lab) ou `50%` (para produção)
   - Clique em **Start instance refresh**

3. **Aguarde a substituição:**
   - O ASG terminará as instâncias antigas e lançará novas com o User Data atualizado
   - As novas instâncias serão registradas automaticamente no Target Group
   - O ALB começará a rotear tráfego para elas assim que o health check passar

> **Alternativa rápida para testes**: Termine a instância manualmente (EC2 → Instâncias → Terminate). O ASG automaticamente lançará uma nova instância com o Launch Template mais recente.

---

### Validação

1. **Execute o script de validação:**
   ```bash
   chmod +x scripts/validate-resources.sh
   ./scripts/validate-resources.sh
   ```

2. **Teste o portal web:**
   ```bash
   curl -I https://www.SEU-DOMINIO
   # Esperado: HTTP/2 200
   ```

3. **Teste o redirect HTTP→HTTPS:**
   ```bash
   curl -I http://www.SEU-DOMINIO
   # Esperado: HTTP/1.1 301 Moved Permanently
   ```

4. **Teste a resolução DNS:**
   ```bash
   nslookup www.SEU-DOMINIO
   nslookup game.SEU-DOMINIO
   ```

5. **Teste o servidor de jogo:**
   - Abra o cliente Luanti e conecte em `game.SEU-DOMINIO:30000`

---

## Custos Estimados

| Recurso | Tipo | Custo On-Demand (mensal) | Custo Spot (mensal) | Economia |
|---------|------|--------------------------|---------------------|----------|
| EC2 Web (t3.small) | Instância | ~$15.18 | ~$4.55 | ~70% |
| EC2 Game (t3.small) | Instância | ~$15.18 | ~$4.55 | ~70% |
| ALB | Load Balancer | ~$16.43 | — | — |
| NLB | Load Balancer | ~$16.43 | — | — |
| Route 53 | DNS | ~$0.50 | — | — |
| ACM | Certificado | Gratuito | — | — |
| CloudWatch | Monitoramento | ~$3.00 | — | — |
| SNS | Notificações | ~$0.00 | — | — |
| **Total Estimado** | | **~$66.72** | **~$45.46** | **~32%** |

> **Nota:** Os valores são estimativas baseadas na região us-east-1 com uso moderado. O custo real pode variar conforme a região, volume de tráfego e disponibilidade de capacidade Spot. A economia com Spot Instances pode chegar a 70-90% em instâncias individuais, mas o total do projeto inclui recursos com preço fixo (ALB, NLB, Route 53).

---

## Serviços e Tecnologias Utilizadas

### Serviços AWS

| Serviço | Função no Projeto |
|---------|-------------------|
| **VPC** | Rede virtual isolada (10.0.0.0/16) com 2 subnets públicas em AZs distintas, Internet Gateway e Route Table |
| **EC2** | Instâncias de computação que hospedam o portal web (Nginx) e o servidor de jogo (Docker + Luanti) |
| **EC2 Spot Instances** | Instâncias com até 70% de desconto, usando pool diversificado (t3.small, t3a.small, t2.small) para reduzir interrupções |
| **Application Load Balancer (ALB)** | Balanceador Layer 7 que recebe tráfego HTTPS na porta 443, realiza terminação TLS com certificado ACM e distribui para instâncias web |
| **Network Load Balancer (NLB)** | Balanceador Layer 4 que encaminha tráfego UDP na porta 30000 diretamente para o servidor de jogo, sem inspeção de conteúdo |
| **Auto Scaling Groups** | Gerenciam capacidade: ASG-WEB escala de 1 a 2 instâncias com base em CPU (target 70%); ASG-GAME mantém exatamente 1 instância (self-healing) |
| **Target Groups** | Registram instâncias e executam health checks: TG-WEB (HTTP /health) e TG-GAME (TCP porta 8080 via socat) |
| **Route 53** | DNS gerenciado com Alias records apontando `www.dominio` para o ALB e `game.dominio` para o NLB |
| **ACM (Certificate Manager)** | Certificado TLS gratuito com validação DNS, usado pelo ALB para terminação HTTPS |
| **CloudWatch** | Coleta de métricas (CPU, memória, disco), logs de aplicação (Nginx, Docker) e alarmes com thresholds configuráveis |
| **SNS (Simple Notification Service)** | Tópico que recebe alarmes do CloudWatch e envia notificações por email ao operador |
| **IAM** | Roles e políticas de menor privilégio para instâncias EC2 (apenas PutMetricData e PutLogEvents no CloudWatch) |

### Stack da Aplicação

| Tecnologia | Função |
|------------|--------|
| **Nginx** | Servidor web nas instâncias do portal, servindo HTML/CSS/JS com endpoint `/health` para health checks |
| **Docker** | Runtime do container Luanti nas instâncias de jogo (imagem `linuxserver/luanti:latest`) |
| **Luanti (Minetest)** | Servidor de jogo open-source voxel, acessível via UDP na porta 30000 |
| **HTML5 / CSS3 / JavaScript** | Portal web responsivo com informações do projeto e instruções de conexão ao servidor |
| **Bash (User Data)** | Scripts de provisionamento automático executados no boot das instâncias EC2 (instalação de pacotes, deploy, health check) |
| **socat** | Utilitário usado para criar um health check TCP dedicado na porta 8080 que valida se o container Luanti está rodando |

### Conceitos Demonstrados

- Diferença prática entre balanceamento Layer 4 (NLB/UDP) e Layer 7 (ALB/HTTPS)
- Terminação TLS no load balancer com certificado ACM gratuito
- Health checks customizados (HTTP path vs TCP port override para UDP)
- Spot Instances com diversificação de pool e self-healing via Auto Scaling
- Segurança com Security Groups referenciados por ID (sem abrir portas desnecessárias)
- IAM com menor privilégio (roles específicas por função)
- Observabilidade com CloudWatch Agent (métricas custom + logs centralizados)
- Provisionamento imutável via User Data (instâncias descartáveis e reproduzíveis)

---

## Licença

Este projeto é de uso educacional e para fins de portfólio.
