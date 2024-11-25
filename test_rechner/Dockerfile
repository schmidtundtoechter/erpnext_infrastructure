# Ausgangsbasis-Image
FROM ubuntu:20.04

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
    && curl -fsSL https://get.docker.com | sh \
    && apt-get clean

# Erstelle Verzeichnisse für den SSH-Server
RUN mkdir /var/run/sshd

# Setze das Passwort für den Benutzer root (dies ist unzureichend sicher und sollte in einer realen Umgebung angepasst werden)
RUN echo 'root:123' | chpasswd

# SSH-Server-Konfiguration anpassen (optional)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Docker-CLI zur Verfügung stellen
RUN usermod -aG docker root

# Exponiere die benötigten Ports für SSH
EXPOSE 22

# Setze das Arbeitsverzeichnis auf /workspace
WORKDIR /workspace

# Kommando, um den SSH-Server zu starten
CMD ["/usr/sbin/sshd", "-D"]
