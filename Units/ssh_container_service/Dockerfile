# Ausgangsbasis-Image
FROM ubuntu:24.04

# Setze Umgebungsvariablen
ENV DEBIAN_FRONTEND=noninteractive

# Aktualisiere und installiere grundlegende Pakete: SSH, Docker und andere nützliche Tools
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    rsync \
    dos2unix \
    && curl -fsSL https://get.docker.com | sh \
    && apt-get clean

# Erstelle Verzeichnisse für den SSH-Server
RUN mkdir /var/run/sshd

# Kopiere die .key-Dateien ins Image (stellen Sie sicher, dass Sie diese Dateien im Build-Kontext haben)
COPY *.key /tmp/keys/

# Berechtigungen für die .key-Dateien setzen
RUN chmod 600 /tmp/keys/* && \
    mkdir -p /root/.ssh && \
    cat /tmp/keys/*.key >> /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    rm -rf /tmp/keys  # Entfernen der temporären Dateien

# Docker-CLI zur Verfügung stellen
RUN usermod -aG docker root

# Exponiere die benötigten Ports für SSH
EXPOSE 22

# Setze das Arbeitsverzeichnis auf /workspace
WORKDIR /workspace

# Kommando, um den SSH-Server zu starten
CMD ["/usr/sbin/sshd", "-D"]
