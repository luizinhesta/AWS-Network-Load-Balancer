# Application Load Balancer (ALB)

## Conceitos Fundamentais — Layer 7

O Application Load Balancer (ALB) opera na **Layer 7 do modelo OSI**, ou seja, na camada de aplicação. Diferente de balanceadores que atuam na Layer 4 (transporte), o ALB é capaz de inspecionar o conteúdo das requisições HTTP/HTTPS, incluindo headers, métodos, paths e query strings. Isso possibilita decisões de roteamento inteligentes baseadas no conteúdo da requisição, não apenas no endereço IP e porta de destino.

Por atuar na camada de aplicação, o ALB entende o protocolo HTTP nativamente. Ele pode realizar ações como redirecionamentos (301/302), respostas fixas, autenticação integrada com OIDC/Cognito e roteamento baseado em regras complexas. Cada listener pode conter múltiplas regras com condições de path (`/api/*`, `/static/*`) ou host (`api.dominio.com`, `www.dominio.com`), direcionando o tráfego para Target Groups distintos.

O ALB também suporta WebSockets, HTTP/2 e gRPC, mantendo conexões persistentes com os targets enquanto gerencia múltiplas conexões dos clientes de forma eficiente através de multiplexação.

## Terminação TLS

A **terminação TLS** (TLS termination) é o processo em que o ALB decifra o tráfego HTTPS recebido do cliente, encerrandoa conexão criptografada no próprio load balancer. A partir desse ponto, a comunicação entre o ALB e as instâncias EC2 no Target Group ocorre via HTTP simples (porta 80), eliminando a necessidade de gerenciar certificados em cada instância individualmente.

Neste projeto, a terminação TLS é realizada utilizando um certificado gerenciado pelo **AWS Certificate Manager (ACM)**. O ACM provisiona, renova e gerencia o ciclo de vida do certificado automaticamente, sem custo adicional quando associado ao ALB. O certificado é validado via DNS (registro CNAME na Hosted Zone do Route 53) e deve estar no estado "Issued" antes de ser associado ao listener HTTPS.

**Benefícios da terminação TLS no ALB:**

- Centralização do gerenciamento de certificados em um único ponto
- Redução da carga computacional nas instâncias EC2 (offload de criptografia)
- Renovação automática via ACM sem intervenção manual
- Simplificação da configuração do Nginx nos targets (apenas HTTP:80)

## Roteamento Baseado em Conteúdo

O ALB suporta roteamento avançado baseado em conteúdo (content-based routing) através de regras nos listeners. Cada regra pode avaliar condições como:

- **Path pattern**: Rotear `/api/*` para um Target Group de backend e `/` para o Target Group de frontend
- **Host header**: Rotear `api.dominio.com` para um grupo e `www.dominio.com` para outro
- **HTTP method**: Diferenciar entre GET, POST, PUT, DELETE
- **Query string**: Rotear com base em parâmetros da URL
- **Source IP**: Restringir ou direcionar tráfego baseado na origem

Neste projeto, a configuração utiliza roteamento simples com uma única regra de encaminhamento no listener HTTPS, direcionando todo o tráfego para o Target_Group_WEB. O listener HTTP:80 possui apenas uma ação de redirect 301 para HTTPS:443.

## Configuração no Projeto

### ALB — `alb-luanti-web`

| Parâmetro | Valor |
|-----------|-------|
| Nome | alb-luanti-web |
| Scheme | Internet-facing |
| Tipo | Application |
| Availability Zones | 2 AZs (subnets públicas) |
| Security Group | SG-ALB |
| IP Address Type | IPv4 |

### Listeners

| Listener | Porta | Protocolo | Ação |
|----------|-------|-----------|------|
| HTTP | 80 | HTTP | Redirect 301 → HTTPS:443 |
| HTTPS | 443 | HTTPS | Forward → Target_Group_WEB |

O listener HTTPS utiliza o certificado ACM associado ao domínio do projeto. A política de segurança TLS recomendada é `ELBSecurityPolicy-TLS13-1-2-2021-06` ou superior.

### Target Group — `Target_Group_WEB`

| Parâmetro | Valor |
|-----------|-------|
| Nome | tg-luanti-web |
| Protocolo | HTTP |
| Porta | 80 |
| Tipo de Target | Instance |
| VPC | VPC do projeto |

### Health Check

| Parâmetro | Valor |
|-----------|-------|
| Protocolo | HTTP |
| Path | /health |
| Porta | traffic-port (80) |
| Resposta esperada | HTTP 200 |
| Intervalo | 30 segundos |
| Timeout | 5 segundos |
| Threshold Healthy | 3 verificações consecutivas |
| Threshold Unhealthy | 3 verificações consecutivas |

O endpoint `/health` é servido pelo Nginx nas instâncias EC2 e retorna uma resposta simples "OK" com status 200, confirmando que a instância está operacional e pronta para receber tráfego.

### Security Group — `SG-ALB`

| Tipo | Protocolo | Porta | Origem | Descrição |
|------|-----------|-------|--------|-----------|
| Inbound | TCP | 80 | 0.0.0.0/0 | Tráfego HTTP (redirect para HTTPS) |
| Inbound | TCP | 443 | 0.0.0.0/0 | Tráfego HTTPS |
| Outbound | All | All | 0.0.0.0/0 | Permite toda saída |

## ALB vs Classic Load Balancer

O ALB substituiu o Classic Load Balancer (CLB) como a opção recomendada para tráfego HTTP/HTTPS na AWS. As principais vantagens do ALB incluem:

- **Roteamento baseado em conteúdo**: CLB só suporta roteamento por porta; ALB suporta regras por path, host, headers
- **Target Groups múltiplos**: Um ALB pode rotear para diferentes Target Groups com base em regras
- **Suporte a containers**: Integração nativa com ECS para mapeamento dinâmico de portas
- **WebSocket e HTTP/2**: Suporte nativo, não disponível no CLB
- **Métricas granulares**: Métricas por Target Group e por regra no CloudWatch
- **Custo-benefício**: Um ALB com múltiplas regras substitui vários CLBs

## Referências Internas

- [Documentação NLB](./NLB.md) — Comparação com Network Load Balancer (Layer 4)
- [Documentação de Rede](./REDE.md) — VPC, subnets e conectividade
- [Documentação de Segurança](./SEGURANCA.md) — Security Groups e IAM
- [Guia de Implantação](../IMPLANTACAO-AWS.md) — Passo a passo para criação do ALB via Console
