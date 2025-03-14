# Use Ubuntu as the base image
FROM ubuntu:latest

# Install necessary packages
RUN apt-get update && apt-get install -y git rsync wget dos2unix yq sudo
RUN rm -rf /var/lib/apt/lists/*

# Install docker
RUN apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get update && apt-get install -y docker-ce

# Add vscode to sudoers
RUN echo "vscode ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set default user
ARG USERNAME=vscode
RUN useradd -m ${USERNAME} && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

#RUN mkdir /workspace-local && chown -R ${USERNAME}:${USERNAME} /workspace-local
ADD init.sh /workspace-local/init.sh
RUN chmod 777 /workspace-local/init.sh
RUN echo "/workspace-local/init.sh" >> /home/${USERNAME}/.bashrc
RUN echo "export PATH=$PATH:/workspace/MIMS" >> /home/${USERNAME}/.bashrc

USER ${USERNAME}
WORKDIR /home/${USERNAME}
