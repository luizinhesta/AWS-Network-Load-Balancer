# Dockerfile para o servidor Luanti (Minetest)
# Porta UDP 30000 para conexões de jogadores

FROM linuxserver/minetest:latest

# Metadados do projeto
LABEL maintainer="AWS-Luanti-NLB-ALB"
LABEL description="Servidor Luanti para projeto AWS NLB/ALB Lab"
LABEL project="AWS-Luanti-NLB-ALB"

# Variáveis de ambiente para linuxserver/minetest
ENV PUID=1000
ENV PGID=1000
ENV TZ=America/Sao_Paulo
ENV CLI_ARGS="--gameid minetest"

# Copiar configuração do servidor
COPY minetest.conf /config/minetest.conf

# Diretório para dados do mundo (persistência local)
VOLUME /config/worlds

# Expor porta UDP 30000 para conexões de jogadores
EXPOSE 30000/udp
