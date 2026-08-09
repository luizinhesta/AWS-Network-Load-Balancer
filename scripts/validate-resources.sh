#!/bin/bash
# ============================================================================
# validate-resources.sh
# Script de validação de recursos AWS para o projeto AWS Luanti ALB/NLB
#
# Descrição:
#   Verifica a criação e configuração correta de todos os recursos AWS
#   utilizados no projeto, agrupados por bloco de implantação.
#
# Uso:
#   Antes de executar, substitua os placeholders pelos valores reais:
#   - <VPC_ID>         : ID da VPC criada (ex: vpc-0abc123def456)
#   - <HOSTED_ZONE_ID> : ID da Hosted Zone no Route 53 (ex: Z0123456789ABCDEF)
#
#   chmod +x scripts/validate-resources.sh
#   ./scripts/validate-resources.sh
#
# Requisitos:
#   - AWS CLI configurada com credenciais válidas
#   - Permissões de leitura nos serviços: EC2, ELBv2, AutoScaling, Route53, CloudWatch
# ============================================================================

# --- Configuração de Placeholders ---
# Substitua pelos valores reais do seu ambiente antes de executar
VPC_ID="<VPC_ID>"
HOSTED_ZONE_ID="<HOSTED_ZONE_ID>"

# --- Nomes dos Recursos ---
ALB_NAME="alb-luanti-web"
NLB_NAME="nlb-luanti-game"
PROJECT_TAG="AWS-Luanti-NLB-ALB"

# --- Cores para output (se o terminal suportar) ---
if [ -t 1 ] && command -v tput &> /dev/null && [ "$(tput colors 2>/dev/null)" -ge 8 ]; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN=""
    RED=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# --- Contadores ---
TOTAL=0
PASSED=0
FAILED=0

# --- Funções Auxiliares ---

# Imprime cabeçalho de seção
print_section() {
    echo ""
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${BLUE}  $1${RESET}"
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
}

# Verifica resultado de um comando e imprime status
check_result() {
    local description="$1"
    local result="$2"
    local expected="$3"

    TOTAL=$((TOTAL + 1))

    if [ -n "$result" ] && [ "$result" != "0" ] && [ "$result" != "null" ] && [ "$result" != "None" ]; then
        echo "  ${GREEN}[OK]${RESET}    $description"
        PASSED=$((PASSED + 1))
    else
        echo "  ${RED}[FALHA]${RESET} $description"
        if [ -n "$expected" ]; then
            echo "          ${YELLOW}Esperado: $expected${RESET}"
        fi
        FAILED=$((FAILED + 1))
    fi
}

# Executa comando AWS CLI e retorna resultado
run_check() {
    local cmd="$1"
    local result
    result=$(eval "$cmd" 2>/dev/null)
    echo "$result"
}

# ============================================================================
# INÍCIO DAS VALIDAÇÕES
# ============================================================================

echo ""
echo "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo "${BOLD}║   Validação de Recursos AWS - Projeto Luanti ALB/NLB       ║${RESET}"
echo "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Projeto: ${PROJECT_TAG}"
echo "  VPC ID:  ${VPC_ID}"
echo "  Zone ID: ${HOSTED_ZONE_ID}"
echo ""

# ============================================================================
# BLOCO 1: REDE (VPC, Subnets, Internet Gateway, Route Tables)
# ============================================================================
print_section "BLOCO 1: Rede (VPC, Subnets, IGW, Route Tables)"

# 1.1 Verificar VPC
VPC_RESULT=$(run_check "aws ec2 describe-vpcs --filters \"Name=tag:Project,Values=${PROJECT_TAG}\" --query 'Vpcs[0].VpcId' --output text")
check_result "VPC com tag Project=${PROJECT_TAG} existe" "$VPC_RESULT" "VPC ID válido"

# 1.2 Verificar CIDR da VPC
VPC_CIDR=$(run_check "aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --query 'Vpcs[0].CidrBlock' --output text")
if [ "$VPC_CIDR" = "10.0.0.0/16" ]; then
    check_result "VPC CIDR é 10.0.0.0/16" "ok"
else
    check_result "VPC CIDR é 10.0.0.0/16" "" "10.0.0.0/16 (atual: ${VPC_CIDR})"
fi

# 1.3 Verificar Subnets (mínimo 2 em AZs distintas)
SUBNET_COUNT=$(run_check "aws ec2 describe-subnets --filters \"Name=vpc-id,Values=${VPC_ID}\" --query 'length(Subnets)' --output text")
if [ "$SUBNET_COUNT" -ge 2 ] 2>/dev/null; then
    check_result "Subnets públicas criadas (${SUBNET_COUNT} encontradas)" "$SUBNET_COUNT" "≥ 2"
else
    check_result "Subnets públicas criadas (mínimo 2)" "" "≥ 2 subnets"
fi

# 1.4 Verificar AZs distintas
AZ_COUNT=$(run_check "aws ec2 describe-subnets --filters \"Name=vpc-id,Values=${VPC_ID}\" --query 'length(Subnets[].AvailabilityZone | unique_items(@))' --output text")
if [ "$AZ_COUNT" -ge 2 ] 2>/dev/null; then
    check_result "Subnets em AZs distintas (${AZ_COUNT} AZs)" "$AZ_COUNT"
else
    check_result "Subnets em AZs distintas" "" "≥ 2 AZs distintas"
fi

# 1.5 Verificar Internet Gateway
IGW_RESULT=$(run_check "aws ec2 describe-internet-gateways --filters \"Name=attachment.vpc-id,Values=${VPC_ID}\" --query 'InternetGateways[0].InternetGatewayId' --output text")
check_result "Internet Gateway associado à VPC" "$IGW_RESULT" "IGW ID válido"

# 1.6 Verificar Route Table com rota para IGW
RT_RESULT=$(run_check "aws ec2 describe-route-tables --filters \"Name=vpc-id,Values=${VPC_ID}\" \"Name=route.destination-cidr-block,Values=0.0.0.0/0\" --query 'RouteTables[0].RouteTableId' --output text")
check_result "Route Table com rota 0.0.0.0/0 para IGW" "$RT_RESULT" "Route Table ID válido"

# ============================================================================
# BLOCO 2: SEGURANÇA (Security Groups)
# ============================================================================
print_section "BLOCO 2: Segurança (Security Groups)"

# 2.1 Verificar Security Groups na VPC
SG_COUNT=$(run_check "aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=${VPC_ID}\" --query 'length(SecurityGroups)' --output text")
check_result "Security Groups encontrados na VPC (${SG_COUNT})" "$SG_COUNT"

# 2.2 Verificar SG-ALB
SG_ALB=$(run_check "aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=${VPC_ID}\" \"Name=group-name,Values=*ALB*\" --query 'SecurityGroups[0].GroupId' --output text")
check_result "Security Group SG-ALB existe" "$SG_ALB" "SG para ALB"

# 2.3 Verificar SG-WEB
SG_WEB=$(run_check "aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=${VPC_ID}\" \"Name=group-name,Values=*WEB*\" --query 'SecurityGroups[0].GroupId' --output text")
check_result "Security Group SG-WEB existe" "$SG_WEB" "SG para instâncias Web"

# 2.4 Verificar SG-GAME
SG_GAME=$(run_check "aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=${VPC_ID}\" \"Name=group-name,Values=*GAME*\" --query 'SecurityGroups[0].GroupId' --output text")
check_result "Security Group SG-GAME existe" "$SG_GAME" "SG para instâncias Game"

# ============================================================================
# BLOCO 3: LOAD BALANCERS (ALB e NLB)
# ============================================================================
print_section "BLOCO 3: Load Balancers (ALB e NLB)"

# 3.1 Verificar ALB
ALB_STATE=$(run_check "aws elbv2 describe-load-balancers --names ${ALB_NAME} --query 'LoadBalancers[0].State.Code' --output text")
check_result "ALB '${ALB_NAME}' existe (estado: ${ALB_STATE})" "$ALB_STATE" "active"

# 3.2 Verificar tipo do ALB
ALB_TYPE=$(run_check "aws elbv2 describe-load-balancers --names ${ALB_NAME} --query 'LoadBalancers[0].Type' --output text")
if [ "$ALB_TYPE" = "application" ]; then
    check_result "ALB é do tipo application" "ok"
else
    check_result "ALB é do tipo application" "" "application (atual: ${ALB_TYPE})"
fi

# 3.3 Verificar NLB
NLB_STATE=$(run_check "aws elbv2 describe-load-balancers --names ${NLB_NAME} --query 'LoadBalancers[0].State.Code' --output text")
check_result "NLB '${NLB_NAME}' existe (estado: ${NLB_STATE})" "$NLB_STATE" "active"

# 3.4 Verificar tipo do NLB
NLB_TYPE=$(run_check "aws elbv2 describe-load-balancers --names ${NLB_NAME} --query 'LoadBalancers[0].Type' --output text")
if [ "$NLB_TYPE" = "network" ]; then
    check_result "NLB é do tipo network" "ok"
else
    check_result "NLB é do tipo network" "" "network (atual: ${NLB_TYPE})"
fi

# ============================================================================
# BLOCO 4: TARGET GROUPS
# ============================================================================
print_section "BLOCO 4: Target Groups"

# 4.1 Verificar Target Group WEB
TG_WEB=$(run_check "aws elbv2 describe-target-groups --query \"TargetGroups[?contains(TargetGroupName, 'web') || contains(TargetGroupName, 'WEB')].TargetGroupArn | [0]\" --output text")
check_result "Target Group WEB existe" "$TG_WEB" "TG para instâncias Web (HTTP:80)"

# 4.2 Verificar Target Group GAME
TG_GAME=$(run_check "aws elbv2 describe-target-groups --query \"TargetGroups[?contains(TargetGroupName, 'game') || contains(TargetGroupName, 'GAME')].TargetGroupArn | [0]\" --output text")
check_result "Target Group GAME existe" "$TG_GAME" "TG para instâncias Game (UDP:30000)"

# 4.3 Verificar protocolo do TG WEB
TG_WEB_PROTO=$(run_check "aws elbv2 describe-target-groups --query \"TargetGroups[?contains(TargetGroupName, 'web') || contains(TargetGroupName, 'WEB')].Protocol | [0]\" --output text")
if [ "$TG_WEB_PROTO" = "HTTP" ]; then
    check_result "Target Group WEB usa protocolo HTTP" "ok"
else
    check_result "Target Group WEB usa protocolo HTTP" "" "HTTP (atual: ${TG_WEB_PROTO})"
fi

# 4.4 Verificar protocolo do TG GAME
TG_GAME_PROTO=$(run_check "aws elbv2 describe-target-groups --query \"TargetGroups[?contains(TargetGroupName, 'game') || contains(TargetGroupName, 'GAME')].Protocol | [0]\" --output text")
if [ "$TG_GAME_PROTO" = "UDP" ]; then
    check_result "Target Group GAME usa protocolo UDP" "ok"
else
    check_result "Target Group GAME usa protocolo UDP" "" "UDP (atual: ${TG_GAME_PROTO})"
fi

# ============================================================================
# BLOCO 5: AUTO SCALING GROUPS
# ============================================================================
print_section "BLOCO 5: Auto Scaling Groups"

# 5.1 Verificar ASG WEB
ASG_WEB_NAME=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'web') || contains(AutoScalingGroupName, 'WEB')].AutoScalingGroupName | [0]\" --output text")
check_result "Auto Scaling Group WEB existe" "$ASG_WEB_NAME" "ASG para instâncias Web"

# 5.2 Verificar capacidade do ASG WEB
ASG_WEB_MIN=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'web') || contains(AutoScalingGroupName, 'WEB')].MinSize | [0]\" --output text")
ASG_WEB_MAX=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'web') || contains(AutoScalingGroupName, 'WEB')].MaxSize | [0]\" --output text")
if [ "$ASG_WEB_MIN" = "1" ] && [ "$ASG_WEB_MAX" = "2" ]; then
    check_result "ASG WEB capacidade: Min=${ASG_WEB_MIN}, Max=${ASG_WEB_MAX}" "ok"
else
    check_result "ASG WEB capacidade correta" "" "Min=1, Max=2 (atual: Min=${ASG_WEB_MIN}, Max=${ASG_WEB_MAX})"
fi

# 5.3 Verificar ASG GAME
ASG_GAME_NAME=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'game') || contains(AutoScalingGroupName, 'GAME')].AutoScalingGroupName | [0]\" --output text")
check_result "Auto Scaling Group GAME existe" "$ASG_GAME_NAME" "ASG para instâncias Game"

# 5.4 Verificar capacidade do ASG GAME (self-healing: 1/1/1)
ASG_GAME_MIN=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'game') || contains(AutoScalingGroupName, 'GAME')].MinSize | [0]\" --output text")
ASG_GAME_MAX=$(run_check "aws autoscaling describe-auto-scaling-groups --query \"AutoScalingGroups[?contains(AutoScalingGroupName, 'game') || contains(AutoScalingGroupName, 'GAME')].MaxSize | [0]\" --output text")
if [ "$ASG_GAME_MIN" = "1" ] && [ "$ASG_GAME_MAX" = "1" ]; then
    check_result "ASG GAME capacidade: Min=${ASG_GAME_MIN}, Max=${ASG_GAME_MAX} (self-healing)" "ok"
else
    check_result "ASG GAME capacidade correta (self-healing)" "" "Min=1, Max=1 (atual: Min=${ASG_GAME_MIN}, Max=${ASG_GAME_MAX})"
fi

# ============================================================================
# BLOCO 6: DNS (Route 53)
# ============================================================================
print_section "BLOCO 6: DNS (Route 53)"

# 6.1 Verificar registros DNS na Hosted Zone
DNS_RECORDS=$(run_check "aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --query 'length(ResourceRecordSets)' --output text")
check_result "Hosted Zone possui registros (${DNS_RECORDS} encontrados)" "$DNS_RECORDS"

# 6.2 Verificar registro www (Alias para ALB)
DNS_WWW=$(run_check "aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --query \"ResourceRecordSets[?contains(Name, 'www')].Type | [0]\" --output text")
check_result "Registro DNS 'www' existe (tipo: ${DNS_WWW})" "$DNS_WWW" "A (Alias para ALB)"

# 6.3 Verificar registro game (Alias para NLB)
DNS_GAME=$(run_check "aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --query \"ResourceRecordSets[?contains(Name, 'game')].Type | [0]\" --output text")
check_result "Registro DNS 'game' existe (tipo: ${DNS_GAME})" "$DNS_GAME" "A (Alias para NLB)"

# ============================================================================
# BLOCO 7: CLOUDWATCH (Alarmes)
# ============================================================================
print_section "BLOCO 7: CloudWatch (Alarmes)"

# 7.1 Verificar alarmes CloudWatch
ALARM_COUNT=$(run_check "aws cloudwatch describe-alarms --query 'length(MetricAlarms)' --output text")
check_result "Alarmes CloudWatch configurados (${ALARM_COUNT} encontrados)" "$ALARM_COUNT"

# 7.2 Verificar alarme de CPU
CPU_ALARM=$(run_check "aws cloudwatch describe-alarms --query \"MetricAlarms[?MetricName=='CPUUtilization'].AlarmName | [0]\" --output text")
check_result "Alarme de CPUUtilization existe" "$CPU_ALARM" "Alarme de CPU > 80%"

# 7.3 Verificar alarme de 5XX
HTTP_ALARM=$(run_check "aws cloudwatch describe-alarms --query \"MetricAlarms[?MetricName=='HTTPCode_ELB_5XX_Count' || MetricName=='HTTPCode_ELB_5XX'].AlarmName | [0]\" --output text")
check_result "Alarme de HTTPCode_ELB_5XX existe" "$HTTP_ALARM" "Alarme de erros 5XX > 10"

# ============================================================================
# RESUMO FINAL
# ============================================================================
echo ""
echo "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}  RESUMO DA VALIDAÇÃO${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "  Total de verificações: ${TOTAL}"
echo "  ${GREEN}Sucesso:  ${PASSED}${RESET}"
echo "  ${RED}Falhas:   ${FAILED}${RESET}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "  ${GREEN}${BOLD}✓ Todos os recursos foram validados com sucesso!${RESET}"
else
    echo "  ${RED}${BOLD}✗ Existem ${FAILED} verificação(ões) com falha.${RESET}"
    echo "  ${YELLOW}  Revise os itens marcados com [FALHA] acima.${RESET}"
fi

echo ""
echo "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"

# Código de saída baseado no resultado
if [ "$FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
