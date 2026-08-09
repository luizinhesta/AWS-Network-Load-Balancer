# Guia de Resolução de Problemas

Este documento apresenta os problemas mais comuns encontrados na operação da infraestrutura AWS Luanti ALB/NLB, com passos de diagnóstico e resolução para cada cenário.

---

## 1. Instância Não Passa no Health Check

### Sintomas

- Target Group mostra instância como **unhealthy** no Console AWS.
- ALB ou NLB não encaminha tráfego para a instância.
- ASG substitui a instância repetidamente (loop de substituição).

### Diagnóstico

1. Verifique o estado do target no Console:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
   ```

2. Acesse a instância via SSH e verifique o serviço:
   ```bash
   # Para instâncias web (Nginx)
   sudo systemctl status nginx
   curl -s http://localhost/health

   # Para instâncias game (Docker)
   sudo docker ps
   sudo docker logs <container_id>
   ```

3. Verifique os logs do User Data:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   ```

### Resolução

- **Nginx não iniciou**: Verifique se os arquivos de configuração foram copiados corretamente pelo User Data. Reinicie com `sudo systemctl restart nginx`.
- **Container Docker não está rodando**: Verifique se a imagem foi baixada com `sudo docker images`. Se necessário, puxe novamente com `sudo docker pull`.
- **Porta não acessível**: Confirme que o Security Group permite o tráfego na porta correta (TCP 80 para web, UDP 30000 para game).
- **Grace period**: Lembre-se que o ASG aguarda 300 segundos (grace period) antes de considerar o health check. Se o provisionamento estiver lento, a instância pode ser marcada como unhealthy antes de estar pronta.

---

## 2. Spot Instance Interrompida

### Sintomas

- Instância EC2 desaparece repentinamente.
- Evento de interrupção visível no Console EC2 ou no CloudWatch Events.
- Breve indisponibilidade do serviço (web ou game) durante a reposição.

### Diagnóstico

1. Verifique eventos do ASG:
   ```bash
   aws autoscaling describe-scaling-activities \
     --auto-scaling-group-name <ASG_NAME> \
     --max-items 10
   ```

2. Verifique o histórico de Spot no Console EC2 → Spot Requests → Savings Summary.

3. Consulte os eventos do CloudWatch:
   ```bash
   aws events list-rules --name-prefix "EC2-Spot"
   ```

### Resolução

- **Comportamento esperado**: A interrupção de Spot Instances é normal. O ASG detecta a instância terminada e lança uma nova automaticamente.
- **Reposição demorada**: Se o ASG não lançar uma nova instância, verifique se há capacidade Spot disponível nos tipos configurados (t3.small, t3a.small, t2.small). A diversificação de tipos de instância reduz o risco de indisponibilidade.
- **Tempo de recuperação**: O provisionamento de uma nova instância leva até 300 segundos. Durante esse período, o serviço fica indisponível para o ASG_GAME (max=1). Para o ASG_WEB, se houver outra instância saudável, o tráfego é redirecionado automaticamente.

---

## 3. ALB Retornando Erros 5XX

### Sintomas

- Usuários recebem página de erro 502 (Bad Gateway) ou 503 (Service Unavailable).
- Alarme CloudWatch `HTTPCode_ELB_5XX` é acionado (threshold: >10 em 5 minutos).
- Notificação recebida via SNS.

### Diagnóstico

1. Verifique o estado dos targets:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <TARGET_GROUP_WEB_ARN>
   ```

2. Verifique as métricas do ALB:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/ApplicationELB \
     --metric-name HTTPCode_ELB_5XX_Count \
     --dimensions Name=LoadBalancer,Value=<ALB_FULL_NAME> \
     --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 60 --statistics Sum
   ```

3. Verifique os logs de acesso do ALB (se habilitados) ou os logs da instância EC2.

### Resolução

- **Todos os targets unhealthy (503)**: Todas as instâncias web estão com problemas. Verifique o Nginx em cada instância e os logs do User Data.
- **Backend timeout (502)**: O Nginx está respondendo lentamente ou a instância está sobrecarregada. Verifique a utilização de CPU e memória.
- **Certificado expirado**: Verifique o estado do certificado ACM no Console. O ACM renova automaticamente certificados validados por DNS, mas problemas no registro CNAME podem impedir a renovação.
- **Listener HTTPS mal configurado**: Confirme que o listener na porta 443 está associado ao certificado ACM correto e encaminhando para o Target Group WEB.

---

## 4. NLB Sem Conectividade (UDP 30000)

### Sintomas

- Jogadores não conseguem conectar ao servidor Luanti via `game.DOMAIN:30000`.
- Timeout de conexão no cliente Luanti.
- Target Group GAME mostra instância como unhealthy.

### Diagnóstico

1. Verifique a resolução DNS:
   ```bash
   nslookup game.DOMAIN
   # ou
   dig game.DOMAIN
   ```

2. Verifique o estado do target:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <TARGET_GROUP_GAME_ARN>
   ```

3. Acesse a instância e verifique o container:
   ```bash
   sudo docker ps
   sudo netstat -ulnp | grep 30000
   ```

4. Verifique o Security Group SG-GAME:
   ```bash
   aws ec2 describe-security-groups --group-ids <SG_GAME_ID>
   ```

### Resolução

- **DNS não resolve**: Verifique se o registro Alias A para `game.DOMAIN` aponta para o NLB no Route 53. Confirme que o Hosted Zone está correto.
- **Container não rodando**: O Docker ou o container Luanti pode ter falhado. Reinicie com `sudo docker restart <container_id>` ou verifique os logs para identificar a causa.
- **Porta UDP bloqueada**: Confirme que o SG-GAME permite UDP na porta 30000 de 0.0.0.0/0. Verifique também que não há Network ACLs bloqueando o tráfego.
- **Health check TCP falhando**: O Target Group GAME utiliza health check TCP na porta 30000. Se o container estiver rodando mas o health check falhar, verifique se o processo está escutando na porta correta com `sudo ss -ulnp | grep 30000`.
- **NLB cross-zone desabilitado**: Se a instância do jogo estiver em uma AZ diferente do NLB node que recebe o tráfego, habilite cross-zone load balancing nas configurações do NLB.

---

## 5. Script de User Data Falha

### Sintomas

- Instância EC2 inicia mas os serviços não estão configurados.
- Health check falha, ASG substitui a instância em loop.
- CloudWatch Agent não envia métricas ou logs.

### Diagnóstico

1. Acesse a instância (se ainda disponível) e verifique o log:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   sudo cat /var/log/cloud-init.log
   ```

2. Verifique se os pacotes foram instalados:
   ```bash
   rpm -qa | grep nginx
   docker --version
   ```

### Resolução

- **Falha no yum install**: Verifique conectividade com a internet (IGW associado, rota padrão na Route Table, IP público atribuído).
- **Docker image não encontrada**: Confirme o nome da imagem no script e a conectividade com o Docker Hub ou registry.
- **Permissão negada**: Verifique se o script está sendo executado como root (User Data executa como root por padrão no Amazon Linux 2023).
- **Timeout no provisionamento**: Se o script excede 300 segundos, simplifique ou otimize os passos. Considere usar uma AMI personalizada com pacotes pré-instalados.

---

## 6. CloudWatch Agent Não Envia Logs/Métricas

### Sintomas

- Log Groups esperados não aparecem no Console CloudWatch.
- Métricas customizadas ausentes.
- Alarmes em estado INSUFFICIENT_DATA.

### Diagnóstico

1. Verifique o status do agente:
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
   ```

2. Verifique os logs do agente:
   ```bash
   sudo cat /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
   ```

3. Verifique permissões da IAM Role:
   ```bash
   aws iam get-instance-profile --instance-profile-name <INSTANCE_PROFILE_NAME>
   ```

### Resolução

- **Agente não instalado**: Verifique o script de User Data. O agente pode não ter sido baixado ou instalado corretamente.
- **Permissões IAM insuficientes**: A IAM Role da instância precisa das permissões `cloudwatch:PutMetricData`, `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` e `logs:DescribeLogStreams`.
- **Configuração inválida**: Verifique o arquivo de configuração do agente em `/opt/aws/amazon-cloudwatch-agent/etc/`. Garanta que os Log Groups e namespaces de métricas estão corretos.

---

## 7. DNS Não Resolve (Route 53)

### Sintomas

- `nslookup www.DOMAIN` ou `nslookup game.DOMAIN` não retorna resultado.
- Navegador exibe erro "DNS_PROBE_FINISHED_NXDOMAIN".

### Diagnóstico

1. Verifique os registros no Route 53:
   ```bash
   aws route53 list-resource-record-sets \
     --hosted-zone-id <HOSTED_ZONE_ID> \
     --query "ResourceRecordSets[?Name=='www.DOMAIN.' || Name=='game.DOMAIN.']"
   ```

2. Verifique se o domínio está usando os Name Servers corretos:
   ```bash
   dig NS DOMAIN
   ```

### Resolução

- **Registro ausente**: Crie o registro Alias A no Route 53 apontando para o ALB (www) ou NLB (game).
- **Name Servers incorretos**: Se o domínio foi registrado em outro provedor, atualize os NS records para apontar para os Name Servers da Hosted Zone do Route 53.
- **Propagação DNS**: Alterações no DNS podem levar até 48 horas para propagar globalmente, embora tipicamente leve poucos minutos com TTL baixo.
- **Evaluate Target Health**: Se o target estiver unhealthy e `evaluate target health` estiver habilitado, o Route 53 pode não retornar o registro. Verifique a saúde dos targets no load balancer correspondente.

---

## 8. Certificado ACM Não Valida

### Sintomas

- Certificado permanece no estado "Pending validation" indefinidamente.
- Listener HTTPS (porta 443) não pode ser configurado no ALB.

### Diagnóstico

1. Verifique o estado do certificado:
   ```bash
   aws acm describe-certificate --certificate-arn <CERTIFICATE_ARN>
   ```

2. Verifique se o registro CNAME de validação existe:
   ```bash
   aws route53 list-resource-record-sets \
     --hosted-zone-id <HOSTED_ZONE_ID> \
     --query "ResourceRecordSets[?Type=='CNAME']"
   ```

### Resolução

- **CNAME não criado**: Acesse o Console ACM, copie os valores do CNAME de validação e crie o registro no Route 53.
- **CNAME incorreto**: Compare o Name e Value fornecidos pelo ACM com o registro criado no Route 53. Devem ser idênticos.
- **Domínio em outro provedor DNS**: Se o DNS não está no Route 53, crie o CNAME no provedor onde o domínio está hospedado.
- **TTL elevado**: Se alterou o CNAME recentemente, aguarde o TTL anterior expirar para que a validação seja concluída.

---

## Dicas Gerais

- **Verifique a região**: Sempre confirme que está operando na região AWS correta antes de investigar.
- **Tags facilitam busca**: Use o filtro por tag `Project=AWS-Luanti-NLB-ALB` para localizar rapidamente seus recursos.
- **Ordem importa**: Problemas em cascata geralmente originam-se de um recurso base mal configurado (VPC, Security Groups, IAM).
- **Grace period do ASG**: Aguarde os 300 segundos de grace period antes de considerar que o health check falhou definitivamente.
- **Logs primeiro**: Sempre consulte `/var/log/cloud-init-output.log` como primeiro passo ao investigar problemas em instâncias recém-lançadas.

---

## Documentos Relacionados

- [Guia de Implantação](../IMPLANTACAO-AWS.md) — Instruções passo a passo para criação dos recursos
- [Monitoramento](./MONITORAMENTO.md) — Configuração de métricas, alarmes e logs
- [Segurança](./SEGURANCA.md) — Security Groups e IAM Roles
- [Rede](./REDE.md) — VPC, Subnets e conectividade
- [ALB](./ALB.md) — Application Load Balancer
- [NLB](./NLB.md) — Network Load Balancer
