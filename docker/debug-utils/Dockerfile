FROM alpine:3.19

LABEL maintainer="Jan Groth" \
    description="Debugging tools for Kubernetes troubleshooting"

# Install networking tools
# bind-tools: Provides dig, nslookup
# iproute2: Provides ip command
# busybox-extras: Provides telnet
# netcat-openbsd: Provides nc
# net-tools: Provides netstat, route, arp
# mtr - My Traceroute
RUN apk update && apk add --no-cache \
    bash \
    curl \
    bind-tools \        
    iproute2 \          
    busybox-extras \    
    netcat-openbsd \
    net-tools \
    nmap \
    nmap-nping \
    openssl \
    traceroute \
    wget \
    tcpdump \
    mtr \
    iftop \
    && rm -rf /var/cache/apk/*

WORKDIR /work

# Entrypoint that keeps container running
ENTRYPOINT ["tail", "-f", "/dev/null"]