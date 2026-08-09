# Segurança — Security Groups e IAM

Este documento descreve a estratégia de segurança adotada no projeto AWS Luanti ALB/NLB, cobrindo Security Groups, IAM Roles, Instance Profiles e o princípio de menor privilégio aplicado a cada camada da arquitetura.

## Security Groups vs Network ACLs

Security Groups operam no nível da instância (stateful), enquanto Network ACLs operam no nível da subnet (stateless). Neste projeto utilizamos exclusivamente Security Groups por oferecerem controle granular por recurso e rastreamento automático de estado — uma resposta permitida por uma regra de entrada não precisa de regra de saída explícita. Network ACLs permanecem com a configuração padrão (permitir tudo), uma vez que o controle de acesso é delegado integralmente aos Security Groups.

## Princípio de Menor Privilégio

Cada Security Group permite exclusivamente o tráfego necessário para a operação do respectivo componente. Nenhuma regra adicional além das documentadas é configurada. Isso reduz a superfície de ataque e limita o impacto de uma eventual comprometimento de qualquer camada.

## Security Groups do Projeto

### SG-ALB — Security Group do Application Load Balancer

| Direção | Protocolo | Porta | Origem/Destino | Justificativa |
|---------|-----------|-------|----------------|---------------|
| Inbound | TCP | 80 | 0.0.0.0/0 | Receber requisições HTTP (redirect para HTTPS) |
| Inbound | TCP | 443 | 0.0.0.0/0 | Receber requisições HTTPS dos usuários |
| Outbound | Todos | Todos | 0.0.0.0/0 | Padrão AWS (tráfego de saída irrestrito) |

O ALB é o ponto de entrada público para o portal web. Aceitar tráfego de qualquer origem nas portas 80 e 443 é necessário pois os usuários acessam de IPs variados na internet.

### SG-WEB — Security Group das Instâncias Web

| Direção | Protocolo | Porta | Origem/Destino | Justificativa |
|---------|-----------|-------|----------------|---------------|
| Inbound | TCP | 80 | **SG-ALB** (por SG ID) | Aceitar tráfego apenas do ALB |
| Inbound | TCP | 22 | IP do operador (/32) | Acesso SSH para manutenção |
| Outbound | Todos | Todos | 0.0.0.0/0 | Padrão AWS |

A regra de entrada na porta 80 referencia o **Security Group ID** do SG-ALB em vez de um bloco CIDR. Essa técnica, conhecida como **SG chaining** (encadeamento de Security Groups), oferece vantagens significativas:

- **Dinâmico**: se o ALB muda de IP (por exemplo, durante scaling), a regra continua válida automaticamente.
- **Explícito**: documenta a relação de dependência entre componentes — apenas tráfego originado pelo ALB é aceito.
- **Seguro**: impede acesso direto às instâncias web pela internet, mesmo que elas possuam IP público.

O acesso SSH é restrito ao IP do operador (`SSH_MY_IP` no `.env.example`), evitando exposição da porta 22 para toda a internet.

### SG-GAME — Security Group das Instâncias de Jogo

| Direção | Protocolo | Porta | Origem/Destino | Justificativa |
|---------|-----------|-------|----------------|---------------|
| Inbound | UDP | 30000 | 0.0.0.0/0 | Conexões dos jogadores Luanti |
| Inbound | TCP | 22 | IP do operador (/32) | Acesso SSH para manutenção |
| Outbound | Todos | Todos | 0.0.0.0/0 | Padrão AWS |

O NLB opera na Layer 4 e preserva o IP de origem do cliente, portanto a regra de entrada aceita UDP de qualquer origem para permitir conexões de jogadores. Diferente do cenário web, não há intermediário que possa ser referenciado por SG ID — o tráfego chega diretamente do IP do jogador.

## IAM Roles e Instance Profiles

As instâncias EC2 não utilizam credenciais estáticas (access keys). Em vez disso, cada grupo de instâncias assume uma IAM Role com permissões mínimas através de um Instance Profile.

### WebRole

Política com permissões restritas para as instâncias do portal web:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

### GameRole

Política com as mesmas permissões mínimas para as instâncias de jogo:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

Ambas as roles possuem uma **trust policy** que permite apenas o serviço `ec2.amazonaws.com` assumi-las:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Instance Profiles

Cada role está vinculada a um Instance Profile correspondente:

| Instance Profile | IAM Role | Associado a |
|-----------------|----------|-------------|
| WebInstanceProfile | WebRole | Launch Template LT-WEB |
| GameInstanceProfile | GameRole | Launch Template LT-GAME |

O Instance Profile é o mecanismo que permite a uma instância EC2 assumir a role. No Console AWS, ao criar o Launch Template, seleciona-se o Instance Profile desejado no campo "IAM instance profile".

## Por que Referência por Security Group ID?

Usar o ID do Security Group como origem em vez de um bloco CIDR é uma prática recomendada pela AWS por três razões:

1. **Resiliência a mudanças de IP** — Load Balancers e instâncias podem trocar de IP sem invalidar regras.
2. **Documentação implícita** — A regra expressa a relação arquitetural entre componentes.
3. **Proteção contra bypass** — Um atacante que conheça o IP da instância não consegue acessá-la diretamente, pois a regra valida a origem pelo Security Group associado ao recurso.

## Boas Práticas Aplicadas

- Separação de Security Groups por função (ALB, Web, Game) para isolamento de responsabilidades.
- IAM Roles em vez de access keys estáticas nas instâncias.
- Permissões IAM limitadas a `cloudwatch:PutMetricData` e `logs:*` — sem acesso a S3, EC2, ou outros serviços.
- SSH restrito a um único IP (/32) do operador.
- Nenhum segredo ou credencial hardcoded nos scripts ou configurações do repositório.
- Arquivo `.env.example` com placeholders e `.gitignore` protegendo o `.env` real.

## Referências

- [docs/REDE.md](REDE.md) — Configuração de VPC e rede
- [ARQUITETURA.md](../ARQUITETURA.md) — Diagramas de arquitetura incluindo componentes de segurança
- [IMPLANTACAO-AWS.md](../IMPLANTACAO-AWS.md) — Bloco 2 (Security Groups) e Bloco 3 (IAM Roles)
