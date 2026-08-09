# Network Load Balancer (NLB)

## Visão Geral

O Network Load Balancer (NLB) é um serviço de balanceamento de carga da AWS que opera na **Layer 4** (camada de transporte) do modelo OSI. Diferentemente do Application Load Balancer (ALB), que trabalha na Layer 7 e inspeciona o conteúdo HTTP/HTTPS das requisições, o NLB atua diretamente nos protocolos TCP, UDP e TLS, tomando decisões de roteamento com base em endereços IP e portas de origem e destino. Essa característica torna o NLB ideal para cargas de trabalho que exigem altíssima performance, baixa latência e suporte a protocolos não-HTTP.

No contexto deste projeto, o NLB é utilizado para rotear o tráfego UDP do servidor de jogo Luanti, permitindo que jogadores se conectem na porta 30000 com latência mínima e preservação do endereço IP de origem.

## Conceitos de Layer 4

### Operação na Camada de Transporte

A Layer 4 do modelo OSI é responsável pelo transporte de dados entre hosts, lidando com segmentação, controle de fluxo e multiplexação de conexões. O NLB opera nesta camada, o que significa que ele não interpreta o conteúdo dos pacotes (payload), não realiza inspeção de cabeçalhos HTTP e não aplica regras de roteamento baseadas em path ou host header.

Essa abordagem traz vantagens significativas:

- **Ultra-baixa latência**: sem necessidade de parsear conteúdo HTTP, o NLB consegue rotear pacotes com latência na ordem de microssegundos.
- **Milhões de conexões simultâneas**: projetado para escalar automaticamente e lidar com picos extremos de tráfego.
- **Suporte a protocolos diversos**: TCP, UDP e TLS são suportados nativamente, tornando o NLB adequado para aplicações de jogos, streaming, IoT e DNS.

### Passthrough de Tráfego

Uma das características mais importantes do NLB é o **passthrough** (repasse direto) do tráfego. Ao contrário do ALB, que termina a conexão do cliente e estabelece uma nova conexão com o backend (proxy reverso), o NLB encaminha os pacotes diretamente para os targets sem modificar o conteúdo ou os cabeçalhos do protocolo de aplicação.

No modo passthrough:

1. O cliente envia um pacote UDP para o endereço do NLB.
2. O NLB seleciona um target saudável com base no algoritmo de roteamento (flow hash).
3. O pacote é encaminhado ao target com o conteúdo intacto.
4. A resposta do target retorna diretamente ao cliente.

Esse comportamento é essencial para o servidor Luanti, pois o protocolo do jogo utiliza comunicação UDP stateless com formato proprietário que não pode ser interpretado ou modificado por um proxy de Layer 7.

### Preservação de IP de Origem

O NLB **preserva o endereço IP real do cliente** nos pacotes encaminhados aos targets. Isso ocorre porque o NLB não atua como proxy — ele realiza o roteamento no nível de rede sem reescrever os cabeçalhos IP.

Benefícios da preservação de IP neste projeto:

- O servidor Luanti pode identificar cada jogador pelo IP real para fins de autenticação e gerenciamento de sessão.
- Logs do servidor registram os IPs verdadeiros dos jogadores, facilitando diagnósticos.
- Regras de firewall no nível da instância EC2 podem filtrar tráfego com base no IP real do cliente.

> **Nota**: No ALB, o IP do cliente é substituído pelo IP do próprio load balancer, sendo necessário consultar o header `X-Forwarded-For` para obter o IP original. Com o NLB, essa complexidade não existe.

## Suporte a UDP

O NLB é o único tipo de Elastic Load Balancer da AWS que suporta balanceamento de tráfego **UDP** (User Datagram Protocol). Isso é fundamental para aplicações como:

- **Servidores de jogos** (como Luanti/Minetest)
- Servidores DNS
- Streaming de áudio e vídeo em tempo real
- Aplicações IoT
- Protocolos VoIP (SIP, RTP)

O UDP é um protocolo sem conexão (connectionless) e sem garantia de entrega. Diferentemente do TCP, não há handshake de três vias, retransmissão automática ou controle de congestionamento. Isso resulta em menor overhead e latência, características desejáveis para comunicação em tempo real de jogos multiplayer.

### Algoritmo de Roteamento para UDP

Para tráfego UDP, o NLB utiliza um **flow hash** baseado em:

- IP de origem
- Porta de origem
- IP de destino
- Porta de destino
- Protocolo

Isso garante que todos os pacotes de um mesmo "fluxo" (mesma combinação de IP/porta) sejam direcionados ao mesmo target, mantendo a consistência da sessão do jogador mesmo sem o conceito formal de "conexão" do TCP.

## Configuração Específica do Projeto

### NLB — nlb-luanti-game

| Parâmetro | Valor |
|-----------|-------|
| Nome | nlb-luanti-game |
| Tipo | Network |
| Scheme | Internet-facing |
| Subnets | Públicas (AZ-1 e AZ-2) |
| Tags | Project=AWS-Luanti-NLB-ALB, Environment=Lab |

### Listener UDP

| Parâmetro | Valor |
|-----------|-------|
| Protocolo | UDP |
| Porta | 30000 |
| Ação padrão | Forward para Target_Group_GAME |

### Target Group — Target_Group_GAME

| Parâmetro | Valor |
|-----------|-------|
| Nome | tg-luanti-game |
| Protocolo | UDP |
| Porta | 30000 |
| Tipo de target | Instance |
| VPC | VPC_Projeto (10.0.0.0/16) |

### Health Check

| Parâmetro | Valor |
|-----------|-------|
| Protocolo do health check | TCP |
| Porta do health check | 30000 |
| Intervalo | 30 segundos |
| Threshold healthy | 3 verificações consecutivas |
| Threshold unhealthy | 3 verificações consecutivas |

> **Por que TCP no health check?** O protocolo UDP não possui um mecanismo nativo de "resposta" que o NLB possa utilizar para validar saúde. Portanto, o health check é realizado via TCP na mesma porta (30000), verificando se a instância está aceitando conexões nessa porta. Quando o container Docker do Luanti está em execução, a porta 30000 responde a conexões TCP, confirmando que o serviço está ativo.

### Security Group — SG-GAME

| Regra | Protocolo | Porta | Origem |
|-------|-----------|-------|--------|
| Inbound | UDP | 30000 | 0.0.0.0/0 |
| Inbound (opcional) | TCP | 22 | IP do operador (/32) |
| Outbound | All | All | 0.0.0.0/0 |

## NLB vs ALB para Tráfego de Jogos

| Aspecto | NLB | ALB |
|---------|-----|-----|
| Camada OSI | Layer 4 (transporte) | Layer 7 (aplicação) |
| Protocolo UDP | ✅ Suportado | ❌ Não suportado |
| Latência | Ultra-baixa (microssegundos) | Baixa (milissegundos) |
| Preservação de IP | ✅ Nativa | ❌ Requer X-Forwarded-For |
| Passthrough | ✅ Pacotes intactos | ❌ Proxy reverso |
| Roteamento por conteúdo | ❌ | ✅ Path, host, headers |
| Terminação TLS | ✅ Opcional | ✅ Padrão |
| Caso de uso | Jogos, DNS, IoT, streaming | APIs REST, websites, microserviços |

Para o servidor Luanti, o NLB é a **única opção viável** porque o ALB não suporta tráfego UDP. Além disso, a baixa latência e a preservação de IP do NLB são características essenciais para uma experiência de jogo fluida.

## Referências

- [Documentação oficial do NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [docs/ALB.md](ALB.md) — Documentação técnica sobre Application Load Balancer
- [ARQUITETURA.md](../ARQUITETURA.md) — Diagramas de arquitetura do projeto
- [IMPLANTACAO-AWS.md](../IMPLANTACAO-AWS.md) — Guia de criação do NLB via Console AWS (Bloco 7)
