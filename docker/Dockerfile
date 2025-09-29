# Dockerfile para WoL Forwarder
FROM python:3.11-alpine

# Información del contenedor
LABEL maintainer="manu"
LABEL description="Wake-on-LAN Forwarder para WireGuard"
LABEL version="1.0"

# Instalar dependencias del sistema
RUN apk add --no-cache \
    tzdata \
    curl \
    && rm -rf /var/cache/apk/*

# Configurar zona horaria
ENV TZ=Europe/Madrid
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Crear directorio de trabajo
WORKDIR /app

# Crear usuario no privilegiado
RUN addgroup -g 1001 -S woluser && \
    adduser -u 1001 -S woluser -G woluser

# Copiar script principal
COPY wol_forwarder.py /app/
RUN chmod +x /app/wol_forwarder.py

# Crear directorio de logs
RUN mkdir -p /var/log && \
    touch /var/log/wol_forwarder.log && \
    chown -R woluser:woluser /var/log /app

# Cambiar a usuario no privilegiado
USER woluser

# Exponer puerto
EXPOSE 8080/udp

# Variables de entorno
ENV PYTHONUNBUFFERED=1
ENV LISTEN_PORT=8080
ENV LOCAL_BROADCAST=192.168.3.255
ENV TARGET_IP=192.168.3.90

# Comando por defecto
CMD ["python3", "/app/wol_forwarder.py"]