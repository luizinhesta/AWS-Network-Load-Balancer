# Guia de Implantação Manual — AWS Load Balancing ALB/NLB - Luanti

> **Documento**: Instruções passo a passo para criação manual de todos os recursos AWS via Console.
> **Método**: Console AWS (sem Infrastructure as Code).
> **Ordem**: 13 blocos sequenciais com dependências respeitadas.

---

## Índice

- [Pré-requisitos](#pré-requisitos)
- [Bloco 1 — VPC e Rede](#bloco-1--vpc-e-rede)
- [Bloco 2 — Security Groups](#bloco-2--security-groups)
- [Bloco 3 — IAM Roles e Instance Profiles](#bloco-3--iam-roles-e-instance-profiles)
- [Bloco 4 — Launch Templates](#bloco-4--launch-templates)
- [Bloco 5 — Target Groups](#bloco-5--target-groups)
- [Bloco 6 — Application Load Balancer (ALB)](#bloco-6--application-load-balancer-alb)
- [Bloco 7 — Network Load Balancer (NLB)](#bloco-7--network-load-balancer-nlb)
- [Bloco 8 — Auto Scaling Groups](#bloco-8--auto-scaling-groups)
- [Bloco 9 — DNS Route 53](#bloco-9--dns-route-53)
- [Bloco 10 — Certificado ACM](#bloco-10--certificado-acm)
- [Bloco 11 — CloudWatch Alarmes](#bloco-11--cloudwatch-alarmes)
- [Bloco 12 — CloudWatch Logs](#bloco-12--cloudwatch-logs)
- [Bloco 13 — SNS Topics](#bloco-13--sns-topics)
- [Remoção dos Recursos (Ordem Reversa)](#remoção-dos-recursos-ordem-reversa)

---

## Pré-requisitos

Antes de iniciar a criação dos recursos, verifique que você possui todos os itens abaixo:

### 1. Conta AWS Ativa

- Conta AWS ativa com acesso ao Console de Gerenciamento.
- Faturamento habilitado (alguns recursos podem gerar custos, mesmo que mínimos).
- Verifique que a conta não está em período de suspensão ou com restrições ativas.

### 2. AWS CLI Configurada

- AWS CLI v2 instalada localmente para comandos de validação.
- Perfil configurado com `aws configure` (Access Key ID, Secret Access Key, região padrão).
- Teste de conectividade: execute `aws sts get-caller-identity` e confirme que retorna o Account ID correto.

### 3. Domínio Registrado

- Domínio registrado e com Hosted Zone criada no Route 53.
- Anote o **Hosted Zone ID** (será necessário nos blocos de DNS e certificado).
- O domínio deve estar resolvendo (NS records propagados).

### 4. Permissões IAM do Operador

O usuário ou role IAM utilizado para criar os recursos deve possuir, no mínimo, as seguintes permissões:

- `ec2:*` — Criação de VPC, Subnets, Security Groups, Launch Templates, instâncias.
- `elasticloadbalancing:*` — Criação e configuração de ALB, NLB, Target Groups, Listeners.
- `autoscaling:*` — Criação e configuração de Auto Scaling Groups.
- `iam:*` — Criação de Roles, Policies, Instance Profiles.
- `route53:*` — Criação de records DNS.
- `acm:*` — Solicitação e validação de certificados.
- `cloudwatch:*` — Criação de alarmes e dashboards.
- `logs:*` — Criação de Log Groups.
- `sns:*` — Criação de tópicos e subscriptions.

> **Recomendação**: Para um ambiente de laboratório, utilize um usuário com a policy `AdministratorAccess`. Em produção, refine para o menor privilégio.

### 5. Informações a Coletar Previamente

Preencha os valores no arquivo `.env.example` antes de iniciar:

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `AWS_REGION` | Região AWS de implantação | `us-east-1` |
| `DOMAIN_NAME` | Domínio registrado | `meudominio.com` |
| `HOSTED_ZONE_ID` | ID da Hosted Zone no Route 53 | `Z0123456789ABCDEF` |
| `AWS_ACCOUNT_ID` | ID numérico da conta AWS (12 dígitos) | `123456789012` |
| `SSH_MY_IP` | IP público do operador (formato CIDR /32) | `203.0.113.50/32` |
| `SNS_EMAIL` | Email para notificações CloudWatch | `admin@empresa.com` |

### 6. Região AWS

- Defina a região **antes** de começar e mantenha-a consistente durante toda a implantação.
- Verifique no canto superior direito do Console que a região ativa é a desejada.
- Todas as instruções deste guia assumem que você está operando na mesma região.

### 7. Tags Padrão (Opcional)

Para facilitar a identificação e organização dos recursos, considere adicionar a tag `Project=AWS-Luanti-NLB-ALB` nos recursos principais (VPC, Security Groups). Tags não são obrigatórias para o funcionamento da infraestrutura.

---

## Bloco 1 — VPC e Rede

> **Objetivo**: Criar a base de rede com VPC, subnets públicas em duas AZs, Internet Gateway e Route Table.
> **Tempo estimado**: 15–20 minutos.

---

### 1.1 Criar a VPC

1. Acesse **VPC** → **Your VPCs** → **Create VPC**.
2. Selecione **VPC only** (não utilizar o assistente "VPC and more").
3. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Name tag** | `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **IPv4 CIDR block** | `10.0.0.0/16` |
| **IPv6 CIDR block** | No IPv6 CIDR block |
| **Tenancy** | Default |

4. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

5. Clique em **Create VPC**.
6. Anote o **VPC ID** gerado (formato: `vpc-xxxxxxxxxxxxxxxxx`).

> 📸 **Screenshot placeholder**: _Captura da tela de confirmação da VPC criada com sucesso._

---

### 1.2 Criar Subnet Pública — AZ-1

1. Acesse **VPC** → **Subnets** → **Create subnet**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **VPC ID** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Subnet name** | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1` |
| **Availability Zone** | Selecione a **primeira AZ** disponível (ex: `us-east-1a`) |
| **IPv4 subnet CIDR block** | `10.0.1.0/24` |

3. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

4. Clique em **Create subnet**.
5. Anote o **Subnet ID** gerado.

> 📸 **Screenshot placeholder**: _Captura da subnet AZ-1 criada com sucesso._

---

### 1.3 Criar Subnet Pública — AZ-2

1. Acesse **VPC** → **Subnets** → **Create subnet**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **VPC ID** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Subnet name** | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2` |
| **Availability Zone** | Selecione a **segunda AZ** disponível (ex: `us-east-1b`) |
| **IPv4 subnet CIDR block** | `10.0.2.0/24` |

3. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

4. Clique em **Create subnet**.
5. Anote o **Subnet ID** gerado.

> 📸 **Screenshot placeholder**: _Captura da subnet AZ-2 criada com sucesso._

---

### 1.4 Habilitar Auto-assign IP Público nas Subnets

Para **cada uma** das duas subnets criadas:

1. Acesse **VPC** → **Subnets**.
2. Selecione a subnet (ex: `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1`).
3. Clique em **Actions** → **Edit subnet settings**.
4. Marque a opção **Enable auto-assign public IPv4 address**.
5. Clique em **Save**.
6. Repita para a segunda subnet (`AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2`).

> 📸 **Screenshot placeholder**: _Captura mostrando a opção "Auto-assign public IPv4 address" habilitada._

---

### 1.5 Criar Internet Gateway

1. Acesse **VPC** → **Internet gateways** → **Create internet gateway**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Name tag** | `AWS-Luanti-NLB-ALB-Lab-IGW` |

3. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

4. Clique em **Create internet gateway**.
5. Na tela de confirmação, clique em **Attach to VPC**.
6. Selecione `AWS-Luanti-NLB-ALB-Lab-VPC`.
7. Clique em **Attach internet gateway**.

> 📸 **Screenshot placeholder**: _Captura do Internet Gateway com estado "Attached"._

---

### 1.6 Criar Route Table Pública

1. Acesse **VPC** → **Route tables** → **Create route table**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Name tag** | `AWS-Luanti-NLB-ALB-Lab-PublicRT` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |

3. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

4. Clique em **Create route table**.

---

### 1.7 Adicionar Rota Padrão ao Internet Gateway

1. Selecione a Route Table `AWS-Luanti-NLB-ALB-Lab-PublicRT`.
2. Clique na aba **Routes** → **Edit routes** → **Add route**.
3. Preencha:

| Campo | Valor |
|-------|-------|
| **Destination** | `0.0.0.0/0` |
| **Target** | Selecione **Internet Gateway** → `AWS-Luanti-NLB-ALB-Lab-IGW` |

4. Clique em **Save changes**.

> 📸 **Screenshot placeholder**: _Captura da Route Table com rota 0.0.0.0/0 → IGW._

---

### 1.8 Associar Route Table às Subnets Públicas

1. Selecione a Route Table `AWS-Luanti-NLB-ALB-Lab-PublicRT`.
2. Clique na aba **Subnet associations** → **Edit subnet associations**.
3. Marque as duas subnets:
   - `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1`
   - `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2`
4. Clique em **Save associations**.

> 📸 **Screenshot placeholder**: _Captura da associação das subnets à Route Table pública._

---

---


## Bloco 2 — Security Groups

> **Objetivo**: Criar os Security Groups com regras de menor privilégio para ALB, instâncias web e instâncias de jogo.
> **Tempo estimado**: 10–15 minutos.
> **Dependência**: Bloco 1 (VPC deve existir).

---

### 2.1 Criar Security Group — SG-ALB

1. Acesse **VPC** → **Security groups** → **Create security group**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Security group name** | `SG-ALB` |
| **Description** | `Security Group para o Application Load Balancer - permite HTTP e HTTPS de qualquer origem` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |

3. Em **Inbound rules**, clique em **Add rule** e adicione:

| Type | Protocol | Port range | Source | Description |
|------|----------|------------|--------|-------------|
| HTTP | TCP | 80 | `0.0.0.0/0` | Tráfego HTTP público |
| HTTPS | TCP | 443 | `0.0.0.0/0` | Tráfego HTTPS público |

4. Em **Outbound rules**, mantenha a regra padrão:

| Type | Protocol | Port range | Destination |
|------|----------|------------|-------------|
| All traffic | All | All | `0.0.0.0/0` |

5. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `SG-ALB` |

6. Clique em **Create security group**.
7. Anote o **Security Group ID** (formato: `sg-xxxxxxxxxxxxxxxxx`).

> 📸 **Screenshot placeholder**: _Captura do SG-ALB criado com regras de entrada HTTP e HTTPS._

---

### 2.2 Criar Security Group — SG-WEB

1. Acesse **VPC** → **Security groups** → **Create security group**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Security group name** | `SG-WEB` |
| **Description** | `Security Group para instâncias web - permite HTTP apenas do ALB` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |

3. Em **Inbound rules**, clique em **Add rule** e adicione:

| Type | Protocol | Port range | Source | Description |
|------|----------|------------|--------|-------------|
| HTTP | TCP | 80 | **Custom**: digite o **Security Group ID** do `SG-ALB` (ex: `sg-xxxxxxxxxxxxxxxxx`) | Tráfego HTTP do ALB |

> ⚠️ **Importante**: Utilize a referência por **Security Group ID**, não por CIDR. Ao digitar `sg-` no campo Source, o Console exibirá o SG-ALB para seleção.

4. Em **Outbound rules**, mantenha a regra padrão (All traffic → 0.0.0.0/0).

5. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `SG-WEB` |

6. Clique em **Create security group**.
7. Anote o **Security Group ID**.

> 📸 **Screenshot placeholder**: _Captura do SG-WEB com regra de entrada referenciando o SG-ALB por ID._

---

### 2.3 Criar Security Group — SG-GAME

1. Acesse **VPC** → **Security groups** → **Create security group**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Security group name** | `SG-GAME` |
| **Description** | `Security Group para instâncias de jogo - permite UDP 30000 de qualquer origem` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |

3. Em **Inbound rules**, clique em **Add rule** e adicione:

| Type | Protocol | Port range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 30000 | `0.0.0.0/0` | Tráfego UDP Luanti de qualquer origem |
| Custom TCP | TCP | 8080 | `10.0.0.0/16` | Health check do NLB (socat) |

4. Em **Outbound rules**, mantenha a regra padrão (All traffic → 0.0.0.0/0).

5. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `SG-GAME` |

6. Clique em **Create security group**.
7. Anote o **Security Group ID**.

> 📸 **Screenshot placeholder**: _Captura do SG-GAME com regra UDP 30000._

---

### 2.4 (Opcional) Adicionar Regra SSH para Acesso Administrativo

Se você necessita de acesso SSH para debugging, adicione esta regra aos Security Groups **SG-WEB** e **SG-GAME**:

1. Selecione o Security Group (SG-WEB ou SG-GAME).
2. Clique na aba **Inbound rules** → **Edit inbound rules** → **Add rule**.
3. Preencha:

| Type | Protocol | Port range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | `<YOUR_IP>/32` (ex: `203.0.113.50/32`) | SSH restrito ao operador |

> ⚠️ **Importante**: **Nunca** utilize `0.0.0.0/0` como source para SSH. Restrinja ao seu IP público atual. Utilize o valor definido na variável `SSH_MY_IP` do `.env.example`.

4. Clique em **Save rules**.
5. Repita para o outro Security Group, se necessário.

> 📸 **Screenshot placeholder**: _Captura da regra SSH restrita ao IP do operador._

---

---


## Bloco 3 — IAM Roles e Instance Profiles

> **Objetivo**: Criar IAM Roles com menor privilégio para instâncias web e de jogo, permitindo publicação de métricas e logs no CloudWatch.
> **Tempo estimado**: 15–20 minutos.
> **Dependência**: Nenhuma (pode ser feito em paralelo ao Bloco 1).

---

### 3.1 Criar IAM Role — WebRole

1. Acesse **IAM** → **Roles** → **Create role**.
2. Em **Trusted entity type**, selecione **AWS service**.
3. Em **Use case**, selecione **EC2**.
4. Clique em **Next**.
5. Na tela de permissões, **não selecione nenhuma policy gerenciada** (criaremos uma custom policy depois).
6. Clique em **Next**.
7. Preencha:

| Campo | Valor |
|-------|-------|
| **Role name** | `AWS-Luanti-NLB-ALB-Lab-WebRole` |
| **Description** | `IAM Role para instâncias web do projeto AWS Luanti - CloudWatch Logs e Metrics` |

8. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

9. Clique em **Create role**.

> 📸 **Screenshot placeholder**: _Captura da WebRole criada com sucesso._

---

### 3.2 Criar Política IAM — WebPolicy

1. Acesse **IAM** → **Policies** → **Create policy**.
2. Selecione a aba **JSON**.
3. Cole o seguinte JSON (substitua `<AWS_REGION>` e `<AWS_ACCOUNT_ID>` pelos valores reais):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchMetrics",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "cloudwatch:namespace": "AWS-Luanti/Web"
                }
            }
        },
        {
            "Sid": "CloudWatchLogsCreateGroup",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup"
            ],
            "Resource": "arn:aws:logs:<AWS_REGION>:<AWS_ACCOUNT_ID>:log-group:*"
        },
        {
            "Sid": "CloudWatchLogsWrite",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:<AWS_REGION>:<AWS_ACCOUNT_ID>:log-group:/aws-luanti/web/*:*"
        }
    ]
}
```

4. Clique em **Next**.
5. Preencha:

| Campo | Valor |
|-------|-------|
| **Policy name** | `AWS-Luanti-NLB-ALB-Lab-WebPolicy` |
| **Description** | `Política de menor privilégio para instâncias web - CloudWatch Logs e Metrics` |

6. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |

7. Clique em **Create policy**.

> 📸 **Screenshot placeholder**: _Captura da WebPolicy criada com JSON de menor privilégio._

---

### 3.3 Associar WebPolicy à WebRole

1. Acesse **IAM** → **Roles** → selecione `AWS-Luanti-NLB-ALB-Lab-WebRole`.
2. Na aba **Permissions**, clique em **Add permissions** → **Attach policies**.
3. Pesquise por `AWS-Luanti-NLB-ALB-Lab-WebPolicy`.
4. Marque a policy e clique em **Add permissions**.

> 📸 **Screenshot placeholder**: _Captura da policy anexada à WebRole._

---

### 3.4 Criar IAM Role — GameRole

1. Acesse **IAM** → **Roles** → **Create role**.
2. Em **Trusted entity type**, selecione **AWS service**.
3. Em **Use case**, selecione **EC2**.
4. Clique em **Next**.
5. Na tela de permissões, **não selecione nenhuma policy gerenciada**.
6. Clique em **Next**.
7. Preencha:

| Campo | Valor |
|-------|-------|
| **Role name** | `AWS-Luanti-NLB-ALB-Lab-GameRole` |
| **Description** | `IAM Role para instâncias de jogo do projeto AWS Luanti - CloudWatch Logs e Metrics` |

8. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

9. Clique em **Create role**.

> 📸 **Screenshot placeholder**: _Captura da GameRole criada com sucesso._

---

### 3.5 Criar Política IAM — GamePolicy

1. Acesse **IAM** → **Policies** → **Create policy**.
2. Selecione a aba **JSON**.
3. Cole o seguinte JSON (substitua `<AWS_REGION>` e `<AWS_ACCOUNT_ID>` pelos valores reais):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchMetrics",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "cloudwatch:namespace": "AWS-Luanti/Game"
                }
            }
        },
        {
            "Sid": "CloudWatchLogsCreateGroup",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup"
            ],
            "Resource": "arn:aws:logs:<AWS_REGION>:<AWS_ACCOUNT_ID>:log-group:*"
        },
        {
            "Sid": "CloudWatchLogsWrite",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:<AWS_REGION>:<AWS_ACCOUNT_ID>:log-group:/aws-luanti/game/*:*"
        }
    ]
}
```

4. Clique em **Next**.
5. Preencha:

| Campo | Valor |
|-------|-------|
| **Policy name** | `AWS-Luanti-NLB-ALB-Lab-GamePolicy` |
| **Description** | `Política de menor privilégio para instâncias de jogo - CloudWatch Logs e Metrics` |

6. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |

7. Clique em **Create policy**.

> 📸 **Screenshot placeholder**: _Captura da GamePolicy criada com JSON de menor privilégio._

---

### 3.6 Associar GamePolicy à GameRole

1. Acesse **IAM** → **Roles** → selecione `AWS-Luanti-NLB-ALB-Lab-GameRole`.
2. Na aba **Permissions**, clique em **Add permissions** → **Attach policies**.
3. Pesquise por `AWS-Luanti-NLB-ALB-Lab-GamePolicy`.
4. Marque a policy e clique em **Add permissions**.

> 📸 **Screenshot placeholder**: _Captura da policy anexada à GameRole._

---

### 3.7 Verificar Instance Profiles (Criados Automaticamente)

> **Nota**: Quando uma IAM Role é criada via Console com EC2 como trusted entity, o AWS cria automaticamente um Instance Profile com o mesmo nome da Role. Verifique se ambos existem:

```bash
# Verificar Instance Profile da WebRole
aws iam get-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-WebRole

# Verificar Instance Profile da GameRole
aws iam get-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-GameRole
```

Se por algum motivo os Instance Profiles não foram criados automaticamente, crie-os manualmente:

```bash
# Criar Instance Profile para WebRole (se necessário)
aws iam create-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-WebRole

aws iam add-role-to-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-WebRole \
  --role-name AWS-Luanti-NLB-ALB-Lab-WebRole

# Criar Instance Profile para GameRole (se necessário)
aws iam create-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-GameRole

aws iam add-role-to-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-GameRole \
  --role-name AWS-Luanti-NLB-ALB-Lab-GameRole
```

---

---


## Bloco 4 — Launch Templates

> **Objetivo**: Criar Launch Templates para instâncias web e de jogo com Amazon Linux 2023, Spot Instances, múltiplos tipos de instância e User Data para provisionamento automático.
> **Tempo estimado**: 15–20 minutos.
> **Dependências**: Bloco 2 (Security Groups) e Bloco 3 (IAM Roles/Instance Profiles).

---

### 4.1 Criar Launch Template — LT-WEB

1. Acesse **EC2** → **Launch Templates** → **Create launch template**.
2. Preencha os campos:

#### Informações do Launch Template

| Campo | Valor |
|-------|-------|
| **Launch template name** | `AWS-Luanti-NLB-ALB-Lab-LT-WEB` |
| **Template version description** | `v1 - Nginx web server com portal Luanti` |

#### Application and OS Images (AMI)

| Campo | Valor |
|-------|-------|
| **AMI** | Amazon Linux 2023 AMI (selecione a mais recente via "Browse more AMIs" → filtrar por "Amazon Linux 2023") |

#### Instance type

| Campo | Valor |
|-------|-------|
| **Instance type** | `t3.small` (tipo primário — tipos adicionais serão configurados no ASG) |

#### Key pair (login)

| Campo | Valor |
|-------|-------|
| **Key pair name** | Selecione um key pair existente ou crie um novo (necessário para SSH) |

#### Network settings

| Campo | Valor |
|-------|-------|
| **Security groups** | Selecione `SG-WEB` |

#### Advanced details — IAM Instance Profile

| Campo | Valor |
|-------|-------|
| **IAM instance profile** | Selecione `AWS-Luanti-NLB-ALB-Lab-WebRole` |

#### Advanced details — Purchasing option

| Campo | Valor |
|-------|-------|
| **Request Spot Instances** | ✅ Habilitado |
| **Spot request type** | One-time |
| **Interruption behavior** | Terminate |

#### Advanced details — User Data

No campo **User Data**, cole o conteúdo completo do script `scripts/user-data-web.sh` do repositório.

> **Referência**: O script completo está disponível em [`scripts/user-data-web.sh`](scripts/user-data-web.sh). Copie e cole o conteúdo inteiro no campo User Data.

O script realiza as seguintes operações:
- Atualiza pacotes do sistema
- Instala Nginx
- Baixa/copia os arquivos do portal web
- Configura o endpoint `/health`
- Instala e configura o CloudWatch Agent
- Inicia o serviço Nginx

3. Na seção **Tags** (em "Resource tags"), adicione as tags que serão aplicadas às instâncias criadas:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `AWS-Luanti-NLB-ALB-Lab-Web` |
| `Role` | `Web` |

4. Clique em **Create launch template**.

> 📸 **Screenshot placeholder**: _Captura do LT-WEB criado com configuração Spot e User Data._

---

### 4.2 Configuração de Múltiplos Tipos de Instância (LT-WEB)

> **Nota**: A configuração de múltiplos tipos de instância (t3.small, t3a.small, t2.small) será definida no **Auto Scaling Group** (Bloco 8), utilizando **Mixed Instances Policy**. O Launch Template define o tipo primário (t3.small), e o ASG adiciona as alternativas para diversificação de capacidade Spot.

Tipos de instância configurados para o pool web:

| Tipo | vCPU | Memória | Família |
|------|------|---------|---------|
| `t3.small` | 2 | 2 GB | Nitro (primário) |
| `t3a.small` | 2 | 2 GB | Nitro AMD |
| `t2.small` | 1 | 2 GB | Legado |

---

### 4.3 Criar Launch Template — LT-GAME

1. Acesse **EC2** → **Launch Templates** → **Create launch template**.
2. Preencha os campos:

#### Informações do Launch Template

| Campo | Valor |
|-------|-------|
| **Launch template name** | `AWS-Luanti-NLB-ALB-Lab-LT-GAME` |
| **Template version description** | `v1 - Servidor Luanti em Docker` |

#### Application and OS Images (AMI)

| Campo | Valor |
|-------|-------|
| **AMI** | Amazon Linux 2023 AMI (mesma AMI utilizada no LT-WEB) |

#### Instance type

| Campo | Valor |
|-------|-------|
| **Instance type** | `t3.small` (tipo primário — tipos adicionais serão configurados no ASG) |

#### Key pair (login)

| Campo | Valor |
|-------|-------|
| **Key pair name** | Selecione o mesmo key pair utilizado no LT-WEB |

#### Network settings

| Campo | Valor |
|-------|-------|
| **Security groups** | Selecione `SG-GAME` |

#### Advanced details — IAM Instance Profile

| Campo | Valor |
|-------|-------|
| **IAM instance profile** | Selecione `AWS-Luanti-NLB-ALB-Lab-GameRole` |

#### Advanced details — Purchasing option

| Campo | Valor |
|-------|-------|
| **Request Spot Instances** | ✅ Habilitado |
| **Spot request type** | One-time |
| **Interruption behavior** | Terminate |

#### Advanced details — User Data

No campo **User Data**, cole o conteúdo completo do script `scripts/user-data-game.sh` do repositório.

> **Referência**: O script completo está disponível em [`scripts/user-data-game.sh`](scripts/user-data-game.sh). Copie e cole o conteúdo inteiro no campo User Data.

O script realiza as seguintes operações:
- Atualiza pacotes do sistema
- Instala Docker
- Inicia o serviço Docker
- Baixa a imagem `lscr.io/linuxserver/luanti:latest`
- Inicia o container na porta UDP/TCP 30000
- Configura serviço de health check TCP na porta 8080 (socat)
- Instala e configura o CloudWatch Agent
- Provisionamento completo em até 300 segundos

3. Na seção **Tags** (em "Resource tags"), adicione as tags que serão aplicadas às instâncias criadas:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `AWS-Luanti-NLB-ALB-Lab-Game` |
| `Role` | `Game` |

4. Clique em **Create launch template**.

> 📸 **Screenshot placeholder**: _Captura do LT-GAME criado com configuração Spot e User Data._

---

### 4.4 Configuração de Múltiplos Tipos de Instância (LT-GAME)

> **Nota**: Assim como no LT-WEB, a diversificação de tipos será configurada no **Auto Scaling Group** (Bloco 8).

Tipos de instância configurados para o pool de jogo:

| Tipo | vCPU | Memória | Família |
|------|------|---------|---------|
| `t3.small` | 2 | 2 GB | Nitro (primário) |
| `t3a.small` | 2 | 2 GB | Nitro AMD |
| `t2.small` | 1 | 2 GB | Legado |

---

### 4.5 Resumo dos Launch Templates

| Launch Template | Nome | AMI | Spot | Instance Profile | Security Group | User Data |
|----------------|------|-----|------|-----------------|----------------|-----------|
| LT-WEB | `AWS-Luanti-NLB-ALB-Lab-LT-WEB` | Amazon Linux 2023 | ✅ Terminate | `AWS-Luanti-NLB-ALB-Lab-WebRole` | `SG-WEB` | `user-data-web.sh` |
| LT-GAME | `AWS-Luanti-NLB-ALB-Lab-LT-GAME` | Amazon Linux 2023 | ✅ Terminate | `AWS-Luanti-NLB-ALB-Lab-GameRole` | `SG-GAME` | `user-data-game.sh` |

---

---


## Bloco 5 — Target Groups

> **Objetivo**: Criar os Target Groups para roteamento de tráfego do ALB (web) e do NLB (jogo), com health checks configurados.
> **Tempo estimado**: 10–15 minutos.
> **Dependência**: Bloco 1 (VPC deve existir).

---

### 5.1 Criar Target Group — TG-WEB (HTTP)

1. Acesse **EC2** → **Target Groups** → **Create target group**.
2. Em **Choose a target type**, selecione **Instances**.
3. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Target group name** | `TG-WEB` |
| **Protocol** | `HTTP` |
| **Port** | `80` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Protocol version** | `HTTP1` |

4. Na seção **Health checks**, configure:

| Campo | Valor |
|-------|-------|
| **Health check protocol** | `HTTP` |
| **Health check path** | `/health` |

5. Expanda **Advanced health check settings**:

| Campo | Valor |
|-------|-------|
| **Port** | `Traffic port` |
| **Healthy threshold** | `3` |
| **Unhealthy threshold** | `3` |
| **Timeout** | `5` segundos |
| **Interval** | `30` segundos |
| **Success codes** | `200` |

6. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

7. Clique em **Next**.
8. Na tela **Register targets**, **não registre targets agora** (o ASG fará isso automaticamente no Bloco 8).
9. Clique em **Create target group**.

> 📸 **Screenshot placeholder**: _Captura do TG-WEB criado com health check em /health._

---

### 5.2 Criar Target Group — TG-GAME (UDP)

1. Acesse **EC2** → **Target Groups** → **Create target group**.
2. Em **Choose a target type**, selecione **Instances**.
3. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Target group name** | `TG-GAME` |
| **Protocol** | `UDP` |
| **Port** | `30000` |
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |

4. Na seção **Health checks**, configure:

| Campo | Valor |
|-------|-------|
| **Health check protocol** | `TCP` |
| **Health check port** | Selecione **Override** e digite `8080` |

> ⚠️ **Nota**: Target Groups UDP não suportam health check via UDP. Utilizamos TCP na porta 8080 (Override), onde o script `user-data-game.sh` configura um serviço `socat` que responde OK quando o container Luanti está rodando. Esta abordagem é mais confiável que verificar TCP na porta do jogo.

5. Expanda **Advanced health check settings**:

| Campo | Valor |
|-------|-------|
| **Healthy threshold** | `3` |
| **Unhealthy threshold** | `3` |
| **Timeout** | `10` segundos |
| **Interval** | `30` segundos |

6. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

7. Clique em **Next**.
8. Na tela **Register targets**, **não registre targets agora** (o ASG fará isso automaticamente no Bloco 8).
9. Clique em **Create target group**.

> 📸 **Screenshot placeholder**: _Captura do TG-GAME criado com health check TCP na porta 8080 (Override)._

---

### 5.3 Resumo dos Target Groups

| Target Group | Protocolo | Porta | Health Check | Porta HC | Path | Intervalo | Threshold |
|--------------|-----------|-------|--------------|----------|------|-----------|-----------|
| `TG-WEB` | HTTP | 80 | HTTP | Traffic port | `/health` | 30s | 3/3 |
| `TG-GAME` | UDP | 30000 | TCP | 8080 (Override) | — | 30s | 3/3 |

---

### 5.4 Checkpoint de Validação — Bloco 5

```bash
# Listar Target Groups do projeto
aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'TG-')].{Name:TargetGroupName,Protocol:Protocol,Port:Port,VPC:VpcId,HealthCheck:HealthCheckProtocol}" \
  --output table

# Verificar health check do TG-WEB
aws elbv2 describe-target-groups \
  --names TG-WEB \
  --query "TargetGroups[0].{Protocol:Protocol,Port:Port,HCProtocol:HealthCheckProtocol,HCPath:HealthCheckPath,HCInterval:HealthCheckIntervalSeconds,HealthyThreshold:HealthyThresholdCount,UnhealthyThreshold:UnhealthyThresholdCount}" \
  --output table

# Verificar health check do TG-GAME
aws elbv2 describe-target-groups \
  --names TG-GAME \
  --query "TargetGroups[0].{Protocol:Protocol,Port:Port,HCProtocol:HealthCheckProtocol,HCPort:HealthCheckPort,HCInterval:HealthCheckIntervalSeconds,HealthyThreshold:HealthyThresholdCount,UnhealthyThreshold:UnhealthyThresholdCount}" \
  --output table
```

**Critérios de sucesso:**

- ✅ `TG-WEB` com protocolo HTTP, porta 80, health check HTTP em `/health`
- ✅ `TG-GAME` com protocolo UDP, porta 30000, health check TCP na porta 30000
- ✅ Ambos com intervalo de 30s e threshold 3/3
- ✅ Ambos associados à VPC `AWS-Luanti-NLB-ALB-Lab-VPC`
- ✅ Nenhum target registrado ainda (será feito pelo ASG)

---


## Bloco 6 — Application Load Balancer (ALB)

> **Objetivo**: Criar o ALB com listeners HTTP (redirect para HTTPS) e HTTPS (forward para TG-WEB), utilizando certificado ACM.
> **Tempo estimado**: 15–20 minutos.
> **Dependências**: Bloco 2 (SG-ALB), Bloco 5 (TG-WEB), Bloco 10 (Certificado ACM validado).

> ⚠️ **Pré-requisito obrigatório**: O certificado ACM deve estar no estado **"Issued"** antes de configurar o listener HTTPS. Se o certificado ainda não foi criado/validado, execute primeiro o [Bloco 10 — Certificado ACM](#bloco-10--certificado-acm) e retorne a este bloco após a validação.

---

### 6.1 Criar o Application Load Balancer

1. Acesse **EC2** → **Load Balancers** → **Create Load Balancer**.
2. Em **Load balancer types**, selecione **Application Load Balancer** → **Create**.
3. Preencha os campos:

#### Basic configuration

| Campo | Valor |
|-------|-------|
| **Load balancer name** | `alb-luanti-web` |
| **Scheme** | `Internet-facing` |
| **IP address type** | `IPv4` |

#### Network mapping

| Campo | Valor |
|-------|-------|
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Availability Zones** | Marque **ambas** as AZs e selecione as subnets públicas correspondentes: |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1` |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2` |

#### Security groups

| Campo | Valor |
|-------|-------|
| **Security groups** | Selecione `SG-ALB` (remova o security group default se estiver selecionado) |

#### Listeners and routing

Configure o primeiro listener (HTTP):

| Campo | Valor |
|-------|-------|
| **Protocol** | `HTTP` |
| **Port** | `80` |
| **Default action** | `Redirect to` |
| **Protocol** | `HTTPS` |
| **Port** | `443` |
| **Status code** | `301 - Permanently moved` |

4. Clique em **Add listener** para adicionar o segundo listener (HTTPS):

| Campo | Valor |
|-------|-------|
| **Protocol** | `HTTPS` |
| **Port** | `443` |
| **Default action** | `Forward to` → Selecione `TG-WEB` |

#### Secure listener settings (HTTPS)

| Campo | Valor |
|-------|-------|
| **Security policy** | `ELBSecurityPolicy-TLS13-1-2-2021-06` (ou a mais recente disponível) |
| **Default SSL/TLS certificate** | `From ACM` → Selecione o certificado para seu domínio |

> ⚠️ **Importante**: Se o certificado ACM não aparecer na lista, verifique:
> - O certificado está na **mesma região** do ALB.
> - O certificado está no estado **"Issued"** (validação DNS concluída).
> - Consulte o [Bloco 10](#bloco-10--certificado-acm) para instruções de criação e validação.

5. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

6. Revise o **Summary** e clique em **Create load balancer**.
7. Aguarde o estado mudar para **Active** (pode levar 2–3 minutos).
8. Anote o **DNS name** do ALB (formato: `alb-luanti-web-XXXXXXXXX.<region>.elb.amazonaws.com`).

> 📸 **Screenshot placeholder**: _Captura do ALB criado com estado Active e ambos os listeners configurados._

---

### 6.2 Verificar Listeners do ALB

Após a criação, confirme os listeners:

1. Acesse **EC2** → **Load Balancers** → selecione `alb-luanti-web`.
2. Clique na aba **Listeners and rules**.
3. Verifique:

| Listener | Porta | Ação |
|----------|-------|------|
| HTTP | 80 | Redirect para `HTTPS:443` (301) |
| HTTPS | 443 | Forward para `TG-WEB` |

> 📸 **Screenshot placeholder**: _Captura da aba Listeners mostrando HTTP:80 redirect e HTTPS:443 forward._

---

### 6.3 Checkpoint de Validação — Bloco 6

```bash
# Verificar ALB criado
aws elbv2 describe-load-balancers \
  --names alb-luanti-web \
  --query "LoadBalancers[0].{Name:LoadBalancerName,DNS:DNSName,State:State.Code,Type:Type,Scheme:Scheme,AZs:AvailabilityZones[*].ZoneName}" \
  --output table

# Verificar listeners do ALB
aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names alb-luanti-web --query "LoadBalancers[0].LoadBalancerArn" --output text) \
  --query "Listeners[*].{Port:Port,Protocol:Protocol,DefaultAction:DefaultActions[0].Type}" \
  --output table

# Verificar Security Groups associados ao ALB
aws elbv2 describe-load-balancers \
  --names alb-luanti-web \
  --query "LoadBalancers[0].SecurityGroups" \
  --output table

# Verificar certificado no listener HTTPS
aws elbv2 describe-listener-certificates \
  --listener-arn $(aws elbv2 describe-listeners --load-balancer-arn $(aws elbv2 describe-load-balancers --names alb-luanti-web --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Listeners[?Port==\`443\`].ListenerArn" --output text) \
  --query "Certificates[*].CertificateArn" \
  --output text
```

**Critérios de sucesso:**

- ✅ ALB `alb-luanti-web` com estado `active` e scheme `internet-facing`
- ✅ ALB distribuído em 2 Availability Zones
- ✅ Listener HTTP:80 com ação `redirect` (301 para HTTPS:443)
- ✅ Listener HTTPS:443 com ação `forward` para `TG-WEB`
- ✅ Certificado ACM associado ao listener HTTPS
- ✅ Security Group `SG-ALB` associado ao ALB
- ✅ Tags `Project` e `Environment` aplicadas

---


## Bloco 7 — Network Load Balancer (NLB)

> **Objetivo**: Criar o NLB para tráfego UDP do servidor de jogo Luanti, com listener na porta 30000.
> **Tempo estimado**: 10–15 minutos.
> **Dependências**: Bloco 1 (VPC e Subnets), Bloco 5 (TG-GAME).

---

### 7.1 Criar o Network Load Balancer

1. Acesse **EC2** → **Load Balancers** → **Create Load Balancer**.
2. Em **Load balancer types**, selecione **Network Load Balancer** → **Create**.
3. Preencha os campos:

#### Basic configuration

| Campo | Valor |
|-------|-------|
| **Load balancer name** | `nlb-luanti-game` |
| **Scheme** | `Internet-facing` |
| **IP address type** | `IPv4` |

#### Network mapping

| Campo | Valor |
|-------|-------|
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Availability Zones** | Marque **ambas** as AZs e selecione as subnets públicas correspondentes: |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1` |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2` |

> **Nota**: O NLB não utiliza Security Groups. O controle de acesso é feito no Security Group das instâncias de destino (`SG-GAME`).

#### Listeners and routing

| Campo | Valor |
|-------|-------|
| **Protocol** | `UDP` |
| **Port** | `30000` |
| **Default action** | `Forward to` → Selecione `TG-GAME` |

4. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |

5. Revise o **Summary** e clique em **Create load balancer**.
6. Aguarde o estado mudar para **Active** (pode levar 2–3 minutos).
7. Anote o **DNS name** do NLB (formato: `nlb-luanti-game-XXXXXXXXX.<region>.elb.amazonaws.com`).

> 📸 **Screenshot placeholder**: _Captura do NLB criado com listener UDP:30000 e estado Active._

---

### 7.2 Verificar Listener do NLB

1. Acesse **EC2** → **Load Balancers** → selecione `nlb-luanti-game`.
2. Clique na aba **Listeners and rules**.
3. Verifique:

| Listener | Protocolo | Porta | Ação |
|----------|-----------|-------|------|
| UDP | UDP | 30000 | Forward para `TG-GAME` |

> 📸 **Screenshot placeholder**: _Captura do listener UDP:30000 no NLB._

---

### 7.3 Checkpoint de Validação — Bloco 7

```bash
# Verificar NLB criado
aws elbv2 describe-load-balancers \
  --names nlb-luanti-game \
  --query "LoadBalancers[0].{Name:LoadBalancerName,DNS:DNSName,State:State.Code,Type:Type,Scheme:Scheme,AZs:AvailabilityZones[*].ZoneName}" \
  --output table

# Verificar listener do NLB
aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names nlb-luanti-game --query "LoadBalancers[0].LoadBalancerArn" --output text) \
  --query "Listeners[*].{Port:Port,Protocol:Protocol,DefaultAction:DefaultActions[0].Type,TargetGroup:DefaultActions[0].TargetGroupArn}" \
  --output table

# Verificar que o NLB está nas 2 AZs
aws elbv2 describe-load-balancers \
  --names nlb-luanti-game \
  --query "LoadBalancers[0].AvailabilityZones[*].{Zone:ZoneName,Subnet:SubnetId}" \
  --output table
```

**Critérios de sucesso:**

- ✅ NLB `nlb-luanti-game` com estado `active` e scheme `internet-facing`
- ✅ NLB do tipo `network`
- ✅ NLB distribuído em 2 Availability Zones
- ✅ Listener UDP:30000 com ação `forward` para `TG-GAME`
- ✅ Tags `Project` e `Environment` aplicadas

---


## Bloco 8 — Auto Scaling Groups

> **Objetivo**: Criar os Auto Scaling Groups para instâncias web (com scaling por CPU) e de jogo (self-healing), registrando-os nos respectivos Target Groups.
> **Tempo estimado**: 20–25 minutos.
> **Dependências**: Bloco 4 (Launch Templates), Bloco 5 (Target Groups), Bloco 6 (ALB), Bloco 7 (NLB).

---

### 8.1 Criar Auto Scaling Group — ASG-WEB

1. Acesse **EC2** → **Auto Scaling Groups** → **Create Auto Scaling group**.
2. Preencha os campos:

#### Step 1 — Choose launch template

| Campo | Valor |
|-------|-------|
| **Auto Scaling group name** | `ASG-WEB` |
| **Launch template** | Selecione `AWS-Luanti-NLB-ALB-Lab-LT-WEB` |
| **Version** | `Latest` |

3. Clique em **Next**.

#### Step 2 — Choose instance launch options

Em **Instance type requirements**, selecione **Override launch template**:

| Campo | Valor |
|-------|-------|
| **Instance types** | `t3.small`, `t3a.small`, `t2.small` |
| **Instance purchase options** | `Combine purchase options and instance types` |
| **Spot allocation strategy** | `Price capacity optimized` |

Em **Network**, configure:

| Campo | Valor |
|-------|-------|
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Availability Zones and subnets** | Selecione **ambas** as subnets: |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1` |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2` |

4. Clique em **Next**.

#### Step 3 — Configure advanced options

| Campo | Valor |
|-------|-------|
| **Load balancing** | `Attach to an existing load balancer` |
| **Existing load balancer target groups** | Selecione `TG-WEB` |
| **Health checks** | |
| **Health check type** | Marque `ELB` (além do EC2 padrão) |
| **Health check grace period** | `300` segundos |

> ⚠️ **Importante**: O grace period de 300 segundos permite que a instância complete o provisionamento (User Data) antes de ser avaliada pelo health check.

5. Clique em **Next**.

#### Step 4 — Configure group size and scaling

| Campo | Valor |
|-------|-------|
| **Desired capacity** | `1` |
| **Minimum capacity** | `1` |
| **Maximum capacity** | `2` |

Em **Scaling policies**, selecione **Target tracking scaling policy**:

| Campo | Valor |
|-------|-------|
| **Scaling policy name** | `CPU-Target-70` |
| **Metric type** | `Average CPU utilization` |
| **Target value** | `70` (%) |
| **Instances need** | `300` seconds warmup before including in metric |

> **Nota sobre cooldown**: O campo "Instances need X seconds warmup" funciona como cooldown efetivo, impedindo ações de escala enquanto novas instâncias estão sendo provisionadas.

6. Clique em **Next**.

#### Step 5 — Add notifications (opcional)

- Pode ser configurado posteriormente no Bloco 13 (SNS). Clique em **Next**.

#### Step 6 — Add tags

Adicione as tags que serão aplicadas às instâncias criadas pelo ASG:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `AWS-Luanti-NLB-ALB-Lab-Web` |
| `Role` | `Web` |

7. Clique em **Next**, revise o resumo e clique em **Create Auto Scaling group**.

> 📸 **Screenshot placeholder**: _Captura do ASG-WEB criado com capacidade 1/1/2 e Target Tracking policy._

---

### 8.2 Criar Auto Scaling Group — ASG-GAME

1. Acesse **EC2** → **Auto Scaling Groups** → **Create Auto Scaling group**.
2. Preencha os campos:

#### Step 1 — Choose launch template

| Campo | Valor |
|-------|-------|
| **Auto Scaling group name** | `ASG-GAME` |
| **Launch template** | Selecione `AWS-Luanti-NLB-ALB-Lab-LT-GAME` |
| **Version** | `Latest` |

3. Clique em **Next**.

#### Step 2 — Choose instance launch options

Em **Instance type requirements**, selecione **Override launch template**:

| Campo | Valor |
|-------|-------|
| **Instance types** | `t3.small`, `t3a.small`, `t2.small` |
| **Instance purchase options** | `Combine purchase options and instance types` |
| **Spot allocation strategy** | `Price capacity optimized` |

Em **Network**, configure:

| Campo | Valor |
|-------|-------|
| **VPC** | Selecione `AWS-Luanti-NLB-ALB-Lab-VPC` |
| **Availability Zones and subnets** | Selecione **ambas** as subnets: |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ1` |
| | `AWS-Luanti-NLB-ALB-Lab-PublicSubnet-AZ2` |

4. Clique em **Next**.

#### Step 3 — Configure advanced options

| Campo | Valor |
|-------|-------|
| **Load balancing** | `Attach to an existing load balancer` |
| **Existing load balancer target groups** | Selecione `TG-GAME` |
| **Health checks** | |
| **Health check type** | Marque `ELB` (além do EC2 padrão) |
| **Health check grace period** | `300` segundos |

5. Clique em **Next**.

#### Step 4 — Configure group size and scaling

| Campo | Valor |
|-------|-------|
| **Desired capacity** | `1` |
| **Minimum capacity** | `1` |
| **Maximum capacity** | `1` |

Em **Scaling policies**, selecione **None** (não é necessária política de escalabilidade para self-healing).

> **Nota sobre Self-Healing**: Com min=1, desired=1 e max=1, o ASG garante que sempre haverá exatamente 1 instância de jogo ativa. Se a instância falhar (health check) ou for terminada (Spot interruption), o ASG automaticamente lançará uma nova instância de substituição.

6. Clique em **Next**.

#### Step 5 — Add notifications (opcional)

- Pode ser configurado posteriormente no Bloco 13 (SNS). Clique em **Next**.

#### Step 6 — Add tags

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |
| `ManagedBy` | `Console` |
| `Name` | `AWS-Luanti-NLB-ALB-Lab-Game` |
| `Role` | `Game` |

7. Clique em **Next**, revise o resumo e clique em **Create Auto Scaling group**.

> 📸 **Screenshot placeholder**: _Captura do ASG-GAME criado com capacidade 1/1/1 (self-healing)._

---

### 8.3 Resumo dos Auto Scaling Groups

| ASG | Launch Template | Min | Desired | Max | Scaling Policy | Target Group | Health Check |
|-----|----------------|-----|---------|-----|----------------|--------------|--------------|
| `ASG-WEB` | `AWS-Luanti-NLB-ALB-Lab-LT-WEB` | 1 | 1 | 2 | Target Tracking CPU 70% | `TG-WEB` | ELB (grace 300s) |
| `ASG-GAME` | `AWS-Luanti-NLB-ALB-Lab-LT-GAME` | 1 | 1 | 1 | Nenhuma (self-healing) | `TG-GAME` | ELB (grace 300s) |

**Características:**
- Ambos os ASGs distribuídos em **2 Availability Zones** para alta disponibilidade.
- Ambos utilizam **Spot Instances** com diversificação de tipos (t3.small, t3a.small, t2.small).
- Health check tipo **ELB** com grace period de **300 segundos** para permitir provisionamento completo.
- `ASG-WEB` escala horizontalmente com base na CPU (70% target).
- `ASG-GAME` opera em modo self-healing (substitui instâncias falhas automaticamente).

---

### 8.4 Checkpoint de Validação — Bloco 8

```bash
# Listar Auto Scaling Groups do projeto
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'ASG-')].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,AZs:AvailabilityZones,TG:TargetGroupARNs[0],HealthCheck:HealthCheckType,Grace:HealthCheckGracePeriod}" \
  --output table

# Verificar política de scaling do ASG-WEB
aws autoscaling describe-policies \
  --auto-scaling-group-name ASG-WEB \
  --query "ScalingPolicies[*].{Name:PolicyName,Type:PolicyType,Metric:TargetTrackingConfiguration.PredefinedMetricSpecification.PredefinedMetricType,Target:TargetTrackingConfiguration.TargetValue}" \
  --output table

# Verificar instâncias ativas nos ASGs
aws autoscaling describe-auto-scaling-instances \
  --query "AutoScalingInstances[?contains(AutoScalingGroupName, 'ASG-')].{ID:InstanceId,ASG:AutoScalingGroupName,AZ:AvailabilityZone,State:LifecycleState,Health:HealthStatus}" \
  --output table

# Verificar registro nos Target Groups
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names TG-WEB --query "TargetGroups[0].TargetGroupArn" --output text) \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}" \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names TG-GAME --query "TargetGroups[0].TargetGroupArn" --output text) \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}" \
  --output table
```

**Critérios de sucesso:**

- ✅ `ASG-WEB` com min=1, desired=1, max=2 em 2 AZs
- ✅ `ASG-GAME` com min=1, desired=1, max=1 em 2 AZs
- ✅ Ambos com health check tipo `ELB` e grace period `300`
- ✅ `ASG-WEB` com Target Tracking policy (CPU 70%)
- ✅ `ASG-WEB` registrado no `TG-WEB`, `ASG-GAME` registrado no `TG-GAME`
- ✅ Instâncias em estado `InService` após provisionamento
- ✅ Targets com estado `healthy` nos Target Groups (após grace period)

---


## Bloco 9 — DNS Route 53

> **Objetivo**: Criar registros DNS Alias A para direcionar tráfego web (www.DOMAIN) ao ALB e tráfego de jogo (game.DOMAIN) ao NLB.
> **Tempo estimado**: 10–15 minutos.
> **Dependências**: Bloco 6 (ALB ativo), Bloco 7 (NLB ativo), Hosted Zone existente no Route 53.

> ⚠️ **Pré-requisitos**:
> - Domínio registrado com Hosted Zone criada no Route 53.
> - ALB `alb-luanti-web` no estado **Active**.
> - NLB `nlb-luanti-game` no estado **Active**.
> - Tenha em mãos o **Hosted Zone ID** (anotado nos pré-requisitos).

---

### 9.1 Criar Registro DNS — www.DOMAIN → ALB

1. Acesse **Route 53** → **Hosted zones** → selecione a Hosted Zone do seu domínio.
2. Clique em **Create record**.
3. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Record name** | `www` |
| **Record type** | `A - Routes traffic to an IPv4 address and some AWS resources` |
| **Alias** | ✅ Habilitado (toggle ativado) |

4. Com o Alias habilitado, configure o endpoint:

| Campo | Valor |
|-------|-------|
| **Route traffic to** | `Alias to Application and Classic Load Balancer` |
| **Region** | Selecione a região onde o ALB foi criado (ex: `us-east-1`) |
| **Load balancer** | Selecione `alb-luanti-web` (o DNS name será exibido) |

5. Configure as opções de roteamento:

| Campo | Valor |
|-------|-------|
| **Routing policy** | `Simple routing` |
| **Evaluate target health** | ✅ `Yes` |

> **Nota**: A opção **Evaluate target health** permite que o Route 53 verifique a saúde do ALB antes de direcionar tráfego. Se o ALB estiver unhealthy, o Route 53 não retornará o registro.

6. Clique em **Create records**.

> 📸 **Screenshot placeholder**: _Captura do registro A Alias www.DOMAIN apontando para o ALB._

---

### 9.2 Criar Registro DNS — game.DOMAIN → NLB

1. Na mesma Hosted Zone, clique em **Create record**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Record name** | `game` |
| **Record type** | `A - Routes traffic to an IPv4 address and some AWS resources` |
| **Alias** | ✅ Habilitado (toggle ativado) |

3. Com o Alias habilitado, configure o endpoint:

| Campo | Valor |
|-------|-------|
| **Route traffic to** | `Alias to Network Load Balancer` |
| **Region** | Selecione a região onde o NLB foi criado (ex: `us-east-1`) |
| **Load balancer** | Selecione `nlb-luanti-game` (o DNS name será exibido) |

4. Configure as opções de roteamento:

| Campo | Valor |
|-------|-------|
| **Routing policy** | `Simple routing` |
| **Evaluate target health** | ✅ `Yes` |

5. Clique em **Create records**.

> 📸 **Screenshot placeholder**: _Captura do registro A Alias game.DOMAIN apontando para o NLB._

---

### 9.3 Resumo dos Registros DNS

| Registro | Tipo | Nome | Destino | Evaluate Target Health |
|----------|------|------|---------|------------------------|
| Web | A (Alias) | `www.<DOMAIN_NAME>` | ALB `alb-luanti-web` | ✅ Yes |
| Game | A (Alias) | `game.<DOMAIN_NAME>` | NLB `nlb-luanti-game` | ✅ Yes |

**Fluxo de resolução:**
- `www.DOMAIN` → Route 53 → ALB → TG-WEB → Instâncias Web (HTTP/HTTPS)
- `game.DOMAIN` → Route 53 → NLB → TG-GAME → Instância Game (UDP:30000)

---

### 9.4 Checkpoint de Validação — Bloco 9

```bash
# Listar records da Hosted Zone (substitua <HOSTED_ZONE_ID> pelo valor real)
aws route53 list-resource-record-sets \
  --hosted-zone-id <HOSTED_ZONE_ID> \
  --query "ResourceRecordSets[?Type=='A'].{Name:Name,Type:Type,AliasTarget:AliasTarget.DNSName,EvaluateHealth:AliasTarget.EvaluateTargetHealth}" \
  --output table

# Testar resolução DNS do portal web
nslookup www.<DOMAIN_NAME>

# Testar resolução DNS do servidor de jogo
nslookup game.<DOMAIN_NAME>

# Verificar que o ALB responde via DNS (após instâncias estarem healthy)
curl -I https://www.<DOMAIN_NAME>

# Verificar redirect HTTP → HTTPS
curl -I http://www.<DOMAIN_NAME>
```

**Critérios de sucesso:**

- ✅ Registro A Alias `www.<DOMAIN_NAME>` apontando para DNS do ALB
- ✅ Registro A Alias `game.<DOMAIN_NAME>` apontando para DNS do NLB
- ✅ Ambos com `Evaluate target health: true`
- ✅ `nslookup www.<DOMAIN_NAME>` resolve para IPs do ALB
- ✅ `nslookup game.<DOMAIN_NAME>` resolve para IPs do NLB
- ✅ `curl -I https://www.<DOMAIN_NAME>` retorna HTTP 200 (após instâncias healthy)
- ✅ `curl -I http://www.<DOMAIN_NAME>` retorna HTTP 301 redirect para HTTPS

---


## Bloco 10 — Certificado ACM

> **Objetivo**: Solicitar e validar um certificado TLS público via AWS Certificate Manager (ACM) utilizando validação DNS, necessário para o listener HTTPS do ALB.
> **Tempo estimado**: 5–10 minutos (criação) + até 30 minutos (propagação DNS e validação).
> **Dependências**: Hosted Zone existente no Route 53, domínio registrado.

> ⚠️ **Importante**: Este bloco deve ser executado **antes** de configurar o listener HTTPS no Bloco 6. O certificado precisa estar no estado "Issued" para ser selecionado no ALB.

---

### 10.1 Solicitar Certificado Público

1. Acesse **AWS Certificate Manager (ACM)** → **Request a certificate**.
2. Selecione **Request a public certificate** → **Next**.
3. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Fully qualified domain name** | `<DOMAIN_NAME>` (ex: `meudominio.com`) |

4. Clique em **Add another name to this certificate** para adicionar domínios adicionais:

| Nome adicional |
|----------------|
| `*.<DOMAIN_NAME>` (wildcard — cobre www, game e qualquer subdomínio) |


> **Nota**: O wildcard (`*.DOMAIN`) permite usar o mesmo certificado para `www.DOMAIN`, `game.DOMAIN` e quaisquer outros subdomínios futuros.

5. Em **Validation method**, selecione:

| Campo | Valor |
|-------|-------|
| **Validation method** | `DNS validation - recommended` |

6. Em **Key algorithm**, selecione:

| Campo | Valor |
|-------|-------|
| **Key algorithm** | `RSA 2048` |

7. Na seção **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |

8. Clique em **Request**.

> 📸 **Screenshot placeholder**: _Captura do certificado solicitado com estado "Pending validation"._

---

### 10.2 Validação DNS — Criar Registro CNAME

Após solicitar o certificado, o ACM exibe os registros CNAME necessários para validação:

1. Na página do certificado (estado **"Pending validation"**), localize a seção **Domains**.
2. Para cada domínio listado, anote os valores:

| Campo | Descrição |
|-------|-----------|
| **CNAME name** | Nome do registro DNS de validação (ex: `_abc123.meudominio.com`) |
| **CNAME value** | Valor do registro DNS de validação (ex: `_def456.acm-validations.aws`) |

3. **Opção A — Criação automática via Console ACM** (recomendado se a Hosted Zone está no Route 53):
   - Clique em **Create records in Route 53**.
   - O ACM criará automaticamente os registros CNAME na Hosted Zone correta.
   - Confirme clicando em **Create records**.

4. **Opção B — Criação manual no Route 53** (se a opção automática não estiver disponível):
   - Acesse **Route 53** → **Hosted zones** → selecione sua zona.
   - Clique em **Create record**.
   - Preencha:

| Campo | Valor |
|-------|-------|
| **Record name** | Cole o **CNAME name** (sem o domínio base) |
| **Record type** | `CNAME` |
| **Value** | Cole o **CNAME value** fornecido pelo ACM |
| **TTL** | `300` |

   - Clique em **Create records**.
   - Repita para cada domínio listado no certificado (domínio base + wildcard).


> 📸 **Screenshot placeholder**: _Captura dos registros CNAME de validação criados no Route 53._

---

### 10.3 Aguardar Validação — Estado "Issued"

1. Retorne ao **ACM** → selecione o certificado solicitado.
2. Aguarde o estado mudar de **"Pending validation"** para **"Issued"**.

| Estado | Significado | Ação |
|--------|-------------|------|
| `Pending validation` | Registros CNAME criados, aguardando propagação DNS | Aguardar (pode levar de 5 a 30 minutos) |
| `Issued` | ✅ Certificado validado e pronto para uso | Pode prosseguir para o Bloco 6 (ALB) |
| `Failed` | ❌ Validação falhou | Verificar se os registros CNAME estão corretos e acessíveis |

> **Dica**: A validação pode levar de 5 a 30 minutos. Enquanto aguarda, você pode avançar para outros blocos que não dependem do certificado (Blocos 11, 12, 13).

> ⚠️ **Não prossiga para o listener HTTPS do Bloco 6** até que o estado seja "Issued".

3. Anote o **ARN do certificado** (formato: `arn:aws:acm:<REGION>:<ACCOUNT_ID>:certificate/<UUID>`).

> 📸 **Screenshot placeholder**: _Captura do certificado no estado "Issued" com ARN visível._

---

### 10.4 Checkpoint de Validação — Bloco 10

```bash
# Listar certificados ACM na região atual
aws acm list-certificates \
  --query "CertificateSummaryList[?contains(DomainName, '<DOMAIN_NAME>')].{Domain:DomainName,ARN:CertificateArn,Status:Status}" \
  --output table

# Verificar detalhes do certificado (substitua <CERTIFICATE_ARN>)
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --query "Certificate.{Domain:DomainName,Status:Status,Type:Type,SANs:SubjectAlternativeNames,ValidationMethod:DomainValidationOptions[0].ValidationMethod}" \
  --output table

# Verificar estado de validação de cada domínio
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --query "Certificate.DomainValidationOptions[*].{Domain:DomainName,Status:ValidationStatus,Method:ValidationMethod}" \
  --output table
```

**Critérios de sucesso:**

- ✅ Certificado com estado `Issued`
- ✅ Domínio principal (`<DOMAIN_NAME>`) e wildcard (`*.<DOMAIN_NAME>`) cobertos
- ✅ Método de validação: `DNS`
- ✅ Registros CNAME de validação presentes na Hosted Zone do Route 53
- ✅ ARN do certificado anotado para uso no Bloco 6 (listener HTTPS do ALB)
- ✅ Tags `Project` e `Environment` aplicadas

---



## Bloco 11 — CloudWatch Alarmes

> **Objetivo**: Criar alarmes no CloudWatch para monitorar CPU das instâncias EC2 e erros 5XX do ALB, com notificações via SNS.
> **Tempo estimado**: 15–20 minutos.
> **Dependências**: Bloco 8 (ASGs com instâncias ativas), Bloco 13 (SNS Topic — pode ser criado primeiro).

> ⚠️ **Nota**: Crie o tópico SNS (Bloco 13) antes dos alarmes para poder associar a ação de notificação. Se preferir, crie o tópico rapidamente antes de voltar a este bloco.

---

### 11.1 Criar Alarme — CPU Alta (Instâncias EC2)

1. Acesse **CloudWatch** → **Alarms** → **All alarms** → **Create alarm**.
2. Clique em **Select metric**.
3. Navegue: **EC2** → **By Auto Scaling Group** → selecione a métrica:

| Campo | Valor |
|-------|-------|
| **AutoScalingGroupName** | `ASG-WEB` |
| **Metric name** | `CPUUtilization` |

4. Clique em **Select metric**.
5. Configure as condições do alarme:

#### Specify metric and conditions

| Campo | Valor |
|-------|-------|
| **Statistic** | `Average` |
| **Period** | `60` segundos (1 minuto) |

#### Conditions

| Campo | Valor |
|-------|-------|
| **Threshold type** | `Static` |
| **Whenever CPUUtilization is...** | `Greater than` |
| **than...** | `80` (%) |

#### Additional configuration

| Campo | Valor |
|-------|-------|
| **Datapoints to alarm** | `3 out of 3` |
| **Missing data treatment** | `Treat missing data as missing` |

> **Explicação**: O alarme será acionado quando a CPU média ultrapassar 80% por 3 períodos consecutivos de 60 segundos (3 minutos contínuos acima do threshold).

6. Clique em **Next**.

#### Configure actions

| Campo | Valor |
|-------|-------|
| **Alarm state trigger** | `In alarm` |
| **Select an SNS topic** | `Select an existing SNS topic` |
| **Send a notification to...** | Selecione `AWS-Luanti-NLB-ALB-Lab-Notifications` |

> Se o tópico SNS ainda não existe, selecione **Create new topic** e nomeie como `AWS-Luanti-NLB-ALB-Lab-Notifications`.

7. Clique em **Next**.

#### Add name and description

| Campo | Valor |
|-------|-------|
| **Alarm name** | `AWS-Luanti-NLB-ALB-Lab-CPU-High` |
| **Alarm description** | `Alarme quando CPU média do ASG-WEB ultrapassa 80% por 3 minutos consecutivos` |

8. Clique em **Next**, revise e clique em **Create alarm**.

> 📸 **Screenshot placeholder**: _Captura do alarme CPU-High criado com threshold 80% e 3 datapoints._

---

### 11.2 Criar Alarme — Erros 5XX do ALB

1. Acesse **CloudWatch** → **Alarms** → **Create alarm**.
2. Clique em **Select metric**.
3. Navegue: **ApplicationELB** → **Per AppELB Metrics** → selecione a métrica:

| Campo | Valor |
|-------|-------|
| **LoadBalancer** | `app/alb-luanti-web/xxxxxxxxx` (selecione o ALB) |
| **Metric name** | `HTTPCode_ELB_5XX_Count` |

4. Clique em **Select metric**.
5. Configure as condições:

#### Specify metric and conditions

| Campo | Valor |
|-------|-------|
| **Statistic** | `Sum` |
| **Period** | `300` segundos (5 minutos) |

#### Conditions

| Campo | Valor |
|-------|-------|
| **Threshold type** | `Static` |
| **Whenever HTTPCode_ELB_5XX_Count is...** | `Greater than` |
| **than...** | `10` |

#### Additional configuration

| Campo | Valor |
|-------|-------|
| **Datapoints to alarm** | `1 out of 1` |
| **Missing data treatment** | `Treat missing data as not breaching` |

> **Explicação**: O alarme será acionado quando a soma de erros 5XX ultrapassar 10 em um único período de 5 minutos. "Treat missing data as not breaching" evita alarmes falsos quando não há tráfego.

6. Clique em **Next**.

#### Configure actions

| Campo | Valor |
|-------|-------|
| **Alarm state trigger** | `In alarm` |
| **Select an SNS topic** | `Select an existing SNS topic` |
| **Send a notification to...** | Selecione `AWS-Luanti-NLB-ALB-Lab-Notifications` |

7. Clique em **Next**.

#### Add name and description

| Campo | Valor |
|-------|-------|
| **Alarm name** | `AWS-Luanti-NLB-ALB-Lab-5XX-High` |
| **Alarm description** | `Alarme quando erros 5XX do ALB ultrapassam 10 ocorrências em 5 minutos` |

8. Clique em **Next**, revise e clique em **Create alarm**.

> 📸 **Screenshot placeholder**: _Captura do alarme 5XX-High criado com threshold >10 em 5 minutos._

---

### 11.3 Resumo dos Alarmes CloudWatch

| Alarme | Métrica | Statistic | Threshold | Período | Datapoints | Ação |
|--------|---------|-----------|-----------|---------|------------|------|
| `AWS-Luanti-NLB-ALB-Lab-CPU-High` | CPUUtilization (ASG-WEB) | Average | >80% | 60s | 3/3 | SNS Publish |
| `AWS-Luanti-NLB-ALB-Lab-5XX-High` | HTTPCode_ELB_5XX_Count (ALB) | Sum | >10 | 300s | 1/1 | SNS Publish |

**Comportamento esperado:**
- **CPU-High**: Dispara quando a média de CPU do ASG-WEB fica acima de 80% por 3 minutos consecutivos. Complementa a política de scaling (70%) como alerta de capacidade.
- **5XX-High**: Dispara quando o ALB retorna mais de 10 erros 5XX em 5 minutos, indicando problemas no backend.

---

### 11.4 Checkpoint de Validação — Bloco 11

```bash
# Listar alarmes do projeto
aws cloudwatch describe-alarms \
  --alarm-name-prefix "AWS-Luanti-NLB-ALB-Lab" \
  --query "MetricAlarms[*].{Name:AlarmName,Metric:MetricName,Threshold:Threshold,Period:Period,Datapoints:EvaluationPeriods,State:StateValue,Action:AlarmActions[0]}" \
  --output table

# Verificar detalhes do alarme CPU
aws cloudwatch describe-alarms \
  --alarm-names "AWS-Luanti-NLB-ALB-Lab-CPU-High" \
  --query "MetricAlarms[0].{Name:AlarmName,Namespace:Namespace,Metric:MetricName,Statistic:Statistic,Threshold:Threshold,ComparisonOperator:ComparisonOperator,Period:Period,EvalPeriods:EvaluationPeriods,State:StateValue}" \
  --output table

# Verificar detalhes do alarme 5XX
aws cloudwatch describe-alarms \
  --alarm-names "AWS-Luanti-NLB-ALB-Lab-5XX-High" \
  --query "MetricAlarms[0].{Name:AlarmName,Namespace:Namespace,Metric:MetricName,Statistic:Statistic,Threshold:Threshold,ComparisonOperator:ComparisonOperator,Period:Period,EvalPeriods:EvaluationPeriods,State:StateValue}" \
  --output table
```

**Critérios de sucesso:**

- ✅ Alarme `AWS-Luanti-NLB-ALB-Lab-CPU-High` criado com threshold >80%, período 60s, 3/3 datapoints
- ✅ Alarme `AWS-Luanti-NLB-ALB-Lab-5XX-High` criado com threshold >10, período 300s, 1/1 datapoints
- ✅ Ambos com ação de publicação no tópico SNS `AWS-Luanti-NLB-ALB-Lab-Notifications`
- ✅ Ambos no estado `OK` (sem alarme ativo) após criação
- ✅ Statistic correta: Average para CPU, Sum para 5XX

---


## Bloco 12 — CloudWatch Logs

> **Objetivo**: Configurar o CloudWatch Logs Agent nas instâncias EC2 para coletar logs do sistema operacional e aplicação, enviando-os para Log Groups dedicados com retenção de 7 dias.
> **Tempo estimado**: 15–20 minutos.
> **Dependências**: Bloco 3 (IAM Roles com permissões de Logs), Bloco 8 (ASGs com instâncias ativas).

> **Nota**: A instalação do CloudWatch Agent é feita automaticamente pelo User Data (scripts/user-data-web.sh e scripts/user-data-game.sh). Este bloco documenta a criação dos Log Groups e verificação da configuração.

---

### 12.1 Criar Log Groups

1. Acesse **CloudWatch** → **Logs** → **Log groups** → **Create log group**.
2. Crie os seguintes Log Groups:

#### Log Group 1 — Sistema Web

| Campo | Valor |
|-------|-------|
| **Log group name** | `/aws-luanti/web/system` |
| **Retention setting** | `7 days` |

Clique em **Create**.

#### Log Group 2 — Aplicação Web (Nginx)

| Campo | Valor |
|-------|-------|
| **Log group name** | `/aws-luanti/web/nginx` |
| **Retention setting** | `7 days` |

Clique em **Create**.

#### Log Group 3 — Sistema Game

| Campo | Valor |
|-------|-------|
| **Log group name** | `/aws-luanti/game/system` |
| **Retention setting** | `7 days` |

Clique em **Create**.

#### Log Group 4 — Aplicação Game (Docker/Luanti)

| Campo | Valor |
|-------|-------|
| **Log group name** | `/aws-luanti/game/application` |
| **Retention setting** | `7 days` |

Clique em **Create**.

3. Para cada Log Group, adicione tags:
   - Acesse o Log Group → **Tags** → **Manage tags**.

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |

> 📸 **Screenshot placeholder**: _Captura dos 4 Log Groups criados com retenção de 7 dias._

---

### 12.2 Configuração do CloudWatch Agent nas Instâncias

O CloudWatch Agent é instalado e configurado automaticamente pelo User Data. Abaixo está a configuração utilizada:

#### Logs coletados — Instâncias Web

| Arquivo de Log | Log Group | Log Stream |
|---------------|-----------|------------|
| `/var/log/messages` | `/aws-luanti/web/system` | `{instance_id}` |
| `/var/log/nginx/access.log` | `/aws-luanti/web/nginx` | `{instance_id}-access` |
| `/var/log/nginx/error.log` | `/aws-luanti/web/nginx` | `{instance_id}-error` |

#### Logs coletados — Instâncias Game

| Arquivo de Log | Log Group | Log Stream |
|---------------|-----------|------------|
| `/var/log/messages` | `/aws-luanti/game/system` | `{instance_id}` |
| Stdout do container Docker | `/aws-luanti/game/application` | `{instance_id}-luanti` |

#### Configuração do Agent (amazon-cloudwatch-agent.json)

A configuração é embutida nos scripts de User Data. Os pontos-chave são:

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws-luanti/web/system",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  }
}
```

> **Referência completa**: Consulte os scripts [`scripts/user-data-web.sh`](scripts/user-data-web.sh) e [`scripts/user-data-game.sh`](scripts/user-data-game.sh) para a configuração completa do CloudWatch Agent.

> 📸 **Screenshot placeholder**: _Captura do CloudWatch Agent configurado e publicando logs._

---

### 12.3 Verificar Recebimento de Logs

Após as instâncias serem provisionadas pelo ASG (aguardar ~5 minutos após lançamento):

1. Acesse **CloudWatch** → **Logs** → **Log groups**.
2. Verifique que os Log Groups possuem **Log streams** ativos.
3. Clique em cada Log Group e confirme que há eventos recentes.

> **Dica**: Se não houver logs após 5 minutos, verifique:
> - A IAM Role da instância tem permissões de CloudWatch Logs (Bloco 3).
> - O CloudWatch Agent está rodando: conecte via SSH e execute `systemctl status amazon-cloudwatch-agent`.
> - A configuração do agent está correta: verifique `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`.

---

### 12.4 Resumo dos Log Groups

| Log Group | Fonte | Retenção | Instâncias |
|-----------|-------|----------|------------|
| `/aws-luanti/web/system` | `/var/log/messages` | 7 dias | Web (ASG-WEB) |
| `/aws-luanti/web/nginx` | Nginx access/error logs | 7 dias | Web (ASG-WEB) |
| `/aws-luanti/game/system` | `/var/log/messages` | 7 dias | Game (ASG-GAME) |
| `/aws-luanti/game/application` | Docker stdout (Luanti) | 7 dias | Game (ASG-GAME) |

---

### 12.5 Checkpoint de Validação — Bloco 12

```bash
# Listar Log Groups do projeto
aws logs describe-log-groups \
  --log-group-name-prefix "/aws-luanti" \
  --query "logGroups[*].{Name:logGroupName,Retention:retentionInDays,StoredBytes:storedBytes}" \
  --output table

# Verificar Log Streams ativos (substitua o nome do Log Group)
aws logs describe-log-streams \
  --log-group-name "/aws-luanti/web/system" \
  --order-by LastEventTime \
  --descending \
  --limit 5 \
  --query "logStreams[*].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table

# Verificar últimos eventos de log do sistema web
aws logs get-log-events \
  --log-group-name "/aws-luanti/web/system" \
  --log-stream-name $(aws logs describe-log-streams --log-group-name "/aws-luanti/web/system" --order-by LastEventTime --descending --limit 1 --query "logStreams[0].logStreamName" --output text) \
  --limit 5 \
  --query "events[*].{Time:timestamp,Message:message}" \
  --output table

# Verificar status do CloudWatch Agent (via SSH na instância)
# ssh -i <key.pem> ec2-user@<IP_INSTANCIA>
# systemctl status amazon-cloudwatch-agent
```

**Critérios de sucesso:**

- ✅ 4 Log Groups criados com prefixo `/aws-luanti/`
- ✅ Todos com retenção configurada para 7 dias
- ✅ Log Streams ativos em cada Log Group (após instâncias serem provisionadas)
- ✅ Eventos de log recentes visíveis nos streams
- ✅ `/var/log/messages` sendo coletado de todas as instâncias
- ✅ Logs de aplicação (Nginx e Docker) sendo coletados
- ✅ Tags `Project` e `Environment` aplicadas aos Log Groups

---



## Bloco 13 — SNS Topics

> **Objetivo**: Criar um tópico SNS para centralizar as notificações dos alarmes CloudWatch e configurar subscriptions por email.
> **Tempo estimado**: 5–10 minutos.
> **Dependências**: Nenhuma (pode ser criado a qualquer momento, mas é referenciado pelo Bloco 11).

---

### 13.1 Criar Tópico SNS

1. Acesse **Amazon SNS** → **Topics** → **Create topic**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Type** | `Standard` |
| **Name** | `AWS-Luanti-NLB-ALB-Lab-Notifications` |
| **Display name** | `Luanti Lab Alerts` |

3. Expanda **Access policy** e mantenha o padrão (Basic):

| Campo | Valor |
|-------|-------|
| **Define who can publish messages to the topic** | `Only the topic owner` |
| **Define who can subscribe to this topic** | `Only the topic owner` |

4. Em **Tags**, adicione:

| Key | Value |
|-----|-------|
| `Project` | `AWS-Luanti-NLB-ALB` |
| `Environment` | `Lab` |

5. Clique em **Create topic**.
6. Anote o **ARN do tópico** (formato: `arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications`).

> 📸 **Screenshot placeholder**: _Captura do tópico SNS criado com nome e ARN visíveis._

---

### 13.2 Criar Subscription por Email

1. Na página do tópico criado, clique em **Create subscription**.
2. Preencha os campos:

| Campo | Valor |
|-------|-------|
| **Topic ARN** | `arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications` (pré-selecionado) |
| **Protocol** | `Email` |
| **Endpoint** | `<EMAIL_ADDRESS>` (seu email para receber notificações) |

3. Clique em **Create subscription**.

4. **Confirmar a subscription:**
   - Acesse a caixa de entrada do email informado.
   - Localize o email de confirmação da AWS (remetente: `no-reply@sns.amazonaws.com`).
   - Clique no link **Confirm subscription** no corpo do email.
   - A subscription mudará de estado `Pending confirmation` para `Confirmed`.

> ⚠️ **Importante**: Até que a subscription seja confirmada via email, nenhuma notificação será entregue. Confirme o mais rápido possível.

> 📸 **Screenshot placeholder**: _Captura da subscription confirmada com estado "Confirmed"._

---

### 13.3 Testar Notificação (Opcional)

Para validar que as notificações funcionam:

1. Na página do tópico, clique em **Publish message**.
2. Preencha:

| Campo | Valor |
|-------|-------|
| **Subject** | `[TESTE] Notificação CloudWatch - Lab Luanti` |
| **Message body** | `Esta é uma mensagem de teste para validar o pipeline de notificações.` |

3. Clique em **Publish message**.
4. Verifique se o email chegou na caixa de entrada.

---

### 13.4 Checkpoint de Validação — Bloco 13

```bash
# Listar tópicos SNS
aws sns list-topics \
  --query "Topics[?contains(TopicArn, 'AWS-Luanti-NLB-ALB-Lab')].TopicArn" \
  --output table

# Verificar atributos do tópico
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications \
  --query "Attributes.{Name:DisplayName,SubscriptionsConfirmed:SubscriptionsConfirmed,SubscriptionsPending:SubscriptionsPending}" \
  --output table

# Listar subscriptions do tópico
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications \
  --query "Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}" \
  --output table

# Verificar que os alarmes CloudWatch apontam para este tópico
aws cloudwatch describe-alarms \
  --alarm-name-prefix "AWS-Luanti-NLB-ALB-Lab" \
  --query "MetricAlarms[*].{Alarm:AlarmName,SNSAction:AlarmActions[0]}" \
  --output table
```

**Critérios de sucesso:**

- ✅ Tópico `AWS-Luanti-NLB-ALB-Lab-Notifications` criado com tipo Standard
- ✅ Pelo menos 1 subscription por email com estado `Confirmed`
- ✅ Alarmes do Bloco 11 referenciando o ARN deste tópico como ação
- ✅ Display name configurado como `Luanti Lab Alerts`
- ✅ Tags `Project` e `Environment` aplicadas

---



---

# Remoção dos Recursos (Ordem Reversa)

> **Objetivo**: Remover todos os recursos AWS criados neste laboratório na ordem correta (reversa à criação), evitando erros de dependência.
> **Tempo estimado total**: 30–45 minutos.

> ⚠️ **ATENÇÃO**: A remoção deve seguir **rigorosamente a ordem reversa** (Bloco 13 → Bloco 1). Tentar deletar recursos fora de ordem resultará em erros de dependência (o Console AWS impedirá a exclusão).

---

## Ordem de Remoção

A tabela abaixo lista todos os recursos na ordem correta de exclusão:

| Ordem | Bloco Original | Recurso a Deletar | Dependência que impede exclusão |
|-------|---------------|--------------------|---------------------------------|
| 1 | 13 - SNS | Subscriptions do tópico | — |
| 2 | 13 - SNS | Tópico `AWS-Luanti-NLB-ALB-Lab-Notifications` | Remover referências nos alarmes primeiro |
| 3 | 12 - Logs | Log Streams (em cada Log Group) | — |
| 4 | 12 - Logs | Log Groups (`/aws-luanti/*`) | — |
| 5 | 11 - Alarmes | Alarme `AWS-Luanti-NLB-ALB-Lab-CPU-High` | — |
| 6 | 11 - Alarmes | Alarme `AWS-Luanti-NLB-ALB-Lab-5XX-High` | — |
| 7 | 10 - ACM | Registros CNAME de validação (Route 53) | Desassociar certificado do ALB primeiro |
| 8 | 10 - ACM | Certificado ACM | Não pode ser deletado se associado a um listener |
| 9 | 9 - DNS | Record `www.<DOMAIN_NAME>` (Route 53) | — |
| 10 | 9 - DNS | Record `game.<DOMAIN_NAME>` (Route 53) | — |
| 11 | 8 - ASGs | `ASG-WEB` (terminará instâncias automaticamente) | Desassociar do TG antes ou junto |
| 12 | 8 - ASGs | `ASG-GAME` (terminará instâncias automaticamente) | Desassociar do TG antes ou junto |

| 13 | 7 - NLB | Listener UDP:30000 do NLB | — |
| 14 | 7 - NLB | Load Balancer `nlb-luanti-game` | Remover listeners primeiro |
| 15 | 6 - ALB | Listener HTTPS:443 do ALB | — |
| 16 | 6 - ALB | Listener HTTP:80 do ALB | — |
| 17 | 6 - ALB | Load Balancer `alb-luanti-web` | Remover listeners primeiro |
| 18 | 5 - TGs | Target Group `TG-WEB` | Não pode ser deletado se associado a um ASG ou listener ativo |
| 19 | 5 - TGs | Target Group `TG-GAME` | Não pode ser deletado se associado a um ASG ou listener ativo |
| 20 | 4 - LTs | Launch Template `AWS-Luanti-NLB-ALB-Lab-LT-WEB` | Não pode ser deletado se referenciado por ASG ativo |
| 21 | 4 - LTs | Launch Template `AWS-Luanti-NLB-ALB-Lab-LT-GAME` | Não pode ser deletado se referenciado por ASG ativo |
| 22 | 3 - IAM | Policy `AWS-Luanti-NLB-ALB-Lab-WebPolicy` | Desanexar da Role primeiro |
| 23 | 3 - IAM | Policy `AWS-Luanti-NLB-ALB-Lab-GamePolicy` | Desanexar da Role primeiro |
| 24 | 3 - IAM | Role `AWS-Luanti-NLB-ALB-Lab-WebRole` (com Instance Profile) | Remover Instance Profile primeiro |
| 25 | 3 - IAM | Role `AWS-Luanti-NLB-ALB-Lab-GameRole` (com Instance Profile) | Remover Instance Profile primeiro |
| 26 | 2 - SGs | Security Group `SG-WEB` | Remover regras que o referenciam primeiro |
| 27 | 2 - SGs | Security Group `SG-GAME` | Verificar que nenhum recurso o utiliza |
| 28 | 2 - SGs | Security Group `SG-ALB` | Remover regras do SG-WEB que o referenciam primeiro |
| 29 | 1 - Rede | Route Table e associações | — |
| 30 | 1 - Rede | Internet Gateway (detach + delete) | Detach da VPC antes de deletar |
| 31 | 1 - Rede | Subnets públicas | Verificar que não há ENIs ativas |
| 32 | 1 - Rede | VPC `AWS-Luanti-NLB-ALB-Lab-VPC` | Todos os recursos internos devem estar removidos |

---

## Instruções Detalhadas de Remoção

### Passo 1 — Remover SNS (Bloco 13)

```bash
# Deletar subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications \
  --query "Subscriptions[*].SubscriptionArn" --output text | \
  xargs -n1 aws sns unsubscribe --subscription-arn

# Deletar tópico
aws sns delete-topic \
  --topic-arn arn:aws:sns:<REGION>:<ACCOUNT_ID>:AWS-Luanti-NLB-ALB-Lab-Notifications
```

**Via Console**: SNS → Topics → selecione o tópico → **Delete**.

---

### Passo 2 — Remover CloudWatch Logs (Bloco 12)

```bash
# Deletar Log Groups
aws logs delete-log-group --log-group-name "/aws-luanti/web/system"
aws logs delete-log-group --log-group-name "/aws-luanti/web/nginx"
aws logs delete-log-group --log-group-name "/aws-luanti/game/system"
aws logs delete-log-group --log-group-name "/aws-luanti/game/application"
```

**Via Console**: CloudWatch → Logs → Log groups → selecione os 4 groups → **Actions** → **Delete**.

---

### Passo 3 — Remover CloudWatch Alarmes (Bloco 11)

```bash
# Deletar alarmes
aws cloudwatch delete-alarms \
  --alarm-names "AWS-Luanti-NLB-ALB-Lab-CPU-High" "AWS-Luanti-NLB-ALB-Lab-5XX-High"
```

**Via Console**: CloudWatch → Alarms → selecione os alarmes → **Actions** → **Delete**.

---

### Passo 4 — Remover Certificado ACM (Bloco 10)

> ⚠️ **Antes de deletar**: Certifique-se de que o certificado **não está associado** ao listener HTTPS do ALB. O ALB deve ser removido primeiro (Passo 7).

```bash
# Verificar que o certificado não está em uso
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --query "Certificate.InUseBy" --output text

# Se "InUseBy" estiver vazio, deletar o certificado
aws acm delete-certificate --certificate-arn <CERTIFICATE_ARN>
```

**Via Console**: ACM → selecione o certificado → **Delete**. Também remova os registros CNAME de validação no Route 53.

---

### Passo 5 — Remover DNS Route 53 (Bloco 9)

1. Acesse **Route 53** → **Hosted zones** → selecione a zona.
2. Selecione os registros `www.<DOMAIN_NAME>` e `game.<DOMAIN_NAME>`.
3. Clique em **Delete records**.

```bash
# Via CLI (requer JSON change batch)
aws route53 change-resource-record-sets \
  --hosted-zone-id <HOSTED_ZONE_ID> \
  --change-batch '{
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "www.<DOMAIN_NAME>",
          "Type": "A",
          "AliasTarget": {
            "HostedZoneId": "<ALB_HOSTED_ZONE_ID>",
            "DNSName": "<ALB_DNS_NAME>",
            "EvaluateTargetHealth": true
          }
        }
      }
    ]
  }'
```

> Repita para o registro `game.<DOMAIN_NAME>` apontando para o NLB.

---

### Passo 6 — Remover Auto Scaling Groups (Bloco 8)

> ⚠️ **Atenção**: Ao deletar um ASG, todas as instâncias EC2 gerenciadas por ele serão **automaticamente terminadas**.

```bash
# Deletar ASG-WEB (força deleção mesmo com instâncias ativas)
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name ASG-WEB \
  --force-delete

# Deletar ASG-GAME
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name ASG-GAME \
  --force-delete
```

**Via Console**: EC2 → Auto Scaling Groups → selecione o ASG → **Delete** → confirme.

> Aguarde a terminação das instâncias antes de prosseguir (1–2 minutos).

---

### Passo 7 — Remover Load Balancers (Blocos 6 e 7)

```bash
# Deletar ALB
aws elbv2 delete-load-balancer \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names alb-luanti-web --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Deletar NLB
aws elbv2 delete-load-balancer \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names nlb-luanti-game --query "LoadBalancers[0].LoadBalancerArn" --output text)
```

**Via Console**: EC2 → Load Balancers → selecione → **Actions** → **Delete**.

> Aguarde que o estado mude para **"deleted"** antes de remover Target Groups (pode levar 1–2 minutos).

---

### Passo 8 — Remover Target Groups (Bloco 5)

> ⚠️ Os Target Groups só podem ser removidos depois que os Load Balancers e ASGs que os referenciam forem deletados.

```bash
# Deletar TG-WEB
aws elbv2 delete-target-group \
  --target-group-arn $(aws elbv2 describe-target-groups --names TG-WEB --query "TargetGroups[0].TargetGroupArn" --output text)

# Deletar TG-GAME
aws elbv2 delete-target-group \
  --target-group-arn $(aws elbv2 describe-target-groups --names TG-GAME --query "TargetGroups[0].TargetGroupArn" --output text)
```

**Via Console**: EC2 → Target Groups → selecione → **Actions** → **Delete**.

---

### Passo 9 — Remover Launch Templates (Bloco 4)

```bash
# Deletar LT-WEB
aws ec2 delete-launch-template \
  --launch-template-name AWS-Luanti-NLB-ALB-Lab-LT-WEB

# Deletar LT-GAME
aws ec2 delete-launch-template \
  --launch-template-name AWS-Luanti-NLB-ALB-Lab-LT-GAME
```

**Via Console**: EC2 → Launch Templates → selecione → **Actions** → **Delete template**.

---

### Passo 10 — Remover IAM Roles e Policies (Bloco 3)

> ⚠️ **Ordem obrigatória**: Desanexar policies → Remover Role do Instance Profile → Deletar Instance Profile → Deletar Role → Deletar Policy.

```bash
# === WebRole ===
# Desanexar policy
aws iam detach-role-policy \
  --role-name AWS-Luanti-NLB-ALB-Lab-WebRole \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWS-Luanti-NLB-ALB-Lab-WebPolicy

# Remover role do instance profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-WebRole \
  --role-name AWS-Luanti-NLB-ALB-Lab-WebRole

# Deletar instance profile
aws iam delete-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-WebRole

# Deletar role
aws iam delete-role --role-name AWS-Luanti-NLB-ALB-Lab-WebRole

# Deletar policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWS-Luanti-NLB-ALB-Lab-WebPolicy

# === GameRole ===
# Desanexar policy
aws iam detach-role-policy \
  --role-name AWS-Luanti-NLB-ALB-Lab-GameRole \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWS-Luanti-NLB-ALB-Lab-GamePolicy

# Remover role do instance profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-GameRole \
  --role-name AWS-Luanti-NLB-ALB-Lab-GameRole

# Deletar instance profile
aws iam delete-instance-profile \
  --instance-profile-name AWS-Luanti-NLB-ALB-Lab-GameRole

# Deletar role
aws iam delete-role --role-name AWS-Luanti-NLB-ALB-Lab-GameRole

# Deletar policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWS-Luanti-NLB-ALB-Lab-GamePolicy
```


**Via Console**: IAM → Roles → selecione a Role → Detach policies → Delete role. Depois IAM → Policies → selecione → **Delete**.

---

### Passo 11 — Remover Security Groups (Bloco 2)

> ⚠️ **Ordem importante**: Remova primeiro os SGs que **não são referenciados** por outros (SG-GAME), depois o SG que é referenciado (SG-ALB dentro do SG-WEB). Antes de deletar SG-ALB, remova a regra no SG-WEB que o referencia.

```bash
# Primeiro: remover a regra do SG-WEB que referencia SG-ALB
aws ec2 revoke-security-group-ingress \
  --group-id <SG_WEB_ID> \
  --protocol tcp --port 80 \
  --source-group <SG_ALB_ID>

# Agora deletar os Security Groups (em qualquer ordem)
aws ec2 delete-security-group --group-id <SG_GAME_ID>
aws ec2 delete-security-group --group-id <SG_WEB_ID>
aws ec2 delete-security-group --group-id <SG_ALB_ID>
```

**Via Console**: EC2 → Security Groups → selecione → **Actions** → **Delete security groups**.

> Se receber erro "has a dependent object", verifique se há ENIs (Elastic Network Interfaces) ativas usando o SG. Aguarde que os Load Balancers e instâncias sejam completamente removidos.

---

### Passo 12 — Remover VPC e Rede (Bloco 1)

> ⚠️ **Dependências da VPC**: A VPC só pode ser deletada quando TODOS os recursos internos forem removidos (subnets, IGW, route tables, security groups, ENIs).

```bash
# Deletar associações da Route Table com subnets
aws ec2 disassociate-route-table \
  --association-id <ROUTE_TABLE_ASSOCIATION_ID_1>
aws ec2 disassociate-route-table \
  --association-id <ROUTE_TABLE_ASSOCIATION_ID_2>

# Deletar Route Table (apenas as criadas manualmente, não a "main")
aws ec2 delete-route-table --route-table-id <ROUTE_TABLE_ID>

# Detach Internet Gateway da VPC
aws ec2 detach-internet-gateway \
  --internet-gateway-id <IGW_ID> \
  --vpc-id <VPC_ID>

# Deletar Internet Gateway
aws ec2 delete-internet-gateway --internet-gateway-id <IGW_ID>

# Deletar Subnets
aws ec2 delete-subnet --subnet-id <SUBNET_AZ1_ID>
aws ec2 delete-subnet --subnet-id <SUBNET_AZ2_ID>

# Deletar VPC
aws ec2 delete-vpc --vpc-id <VPC_ID>
```


**Via Console**: VPC → Your VPCs → selecione `AWS-Luanti-NLB-ALB-Lab-VPC` → **Actions** → **Delete VPC**. O Console oferece a opção de deletar recursos dependentes automaticamente.

> **Dica**: A opção "Delete VPC" do Console pode lidar com a remoção de subnets, route tables e IGW automaticamente, mas é recomendado fazer manualmente para entender as dependências.

---

## Alertas de Dependência

| Se tentar deletar... | Erro provável | Solução |
|---------------------|---------------|---------|
| VPC com recursos ativos | `DependencyViolation: The vpc has dependencies` | Remover todos os recursos internos primeiro |
| Security Group em uso | `DependencyViolation: resource has a dependent object` | Remover regras que referenciam o SG, aguardar deleção de ENIs |
| Target Group com listener associado | `ResourceInUse` | Deletar o Load Balancer ou listener primeiro |
| Certificado ACM em uso pelo ALB | `ResourceInUseException` | Remover o listener HTTPS ou o ALB primeiro |
| Launch Template referenciado por ASG | `ResourceInUse` | Deletar o ASG primeiro |
| IAM Role com policy anexada | `DeleteConflict: Cannot delete a role with policies attached` | Desanexar todas as policies primeiro |
| Internet Gateway attached à VPC | `DependencyViolation` | Executar `detach-internet-gateway` antes do delete |
| Route Table com associações | `DependencyViolation` | Desassociar das subnets antes de deletar |

---

## Checklist Final de Remoção

Use este checklist para confirmar que todos os recursos foram removidos:

- [ ] SNS: Tópico `AWS-Luanti-NLB-ALB-Lab-Notifications` deletado
- [ ] CloudWatch Logs: 4 Log Groups `/aws-luanti/*` deletados
- [ ] CloudWatch Alarmes: `CPU-High` e `5XX-High` deletados
- [ ] ACM: Certificado deletado + CNAMEs de validação removidos
- [ ] Route 53: Records `www` e `game` deletados
- [ ] ASGs: `ASG-WEB` e `ASG-GAME` deletados (instâncias terminadas)
- [ ] ALB: `alb-luanti-web` deletado
- [ ] NLB: `nlb-luanti-game` deletado
- [ ] Target Groups: `TG-WEB` e `TG-GAME` deletados
- [ ] Launch Templates: `LT-WEB` e `LT-GAME` deletados
- [ ] IAM: Roles, Policies e Instance Profiles deletados
- [ ] Security Groups: `SG-ALB`, `SG-WEB`, `SG-GAME` deletados
- [ ] VPC: Route Table, IGW, Subnets e VPC deletados


### Verificação Final — Confirmar Remoção Completa

```bash
# Verificar que não há recursos com a tag do projeto
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=AWS-Luanti-NLB-ALB \
  --query "ResourceTagMappingList[*].{ARN:ResourceARN}" \
  --output table

# Verificar que a VPC foi removida
aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=AWS-Luanti-NLB-ALB" \
  --query "Vpcs[*].VpcId" --output text

# Verificar que não há instâncias remanescentes
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=AWS-Luanti-NLB-ALB" "Name=instance-state-name,Values=running,pending,stopping" \
  --query "Reservations[*].Instances[*].InstanceId" --output text
```

**Se todos os comandos retornarem vazio, a remoção foi concluída com sucesso.** ✅

> **Nota sobre custos**: Após a remoção completa, não haverá mais cobranças associadas a este laboratório. Verifique o **AWS Cost Explorer** nos dias seguintes para confirmar que não há cobranças residuais.
