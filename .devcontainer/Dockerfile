# Use Ubuntu as the base image
FROM ubuntu:latest

# Install necessary packages
RUN apt-get update && apt-get install -y git rsync wget dos2unix sudo
RUN rm -rf /var/lib/apt/lists/*
RUN wget https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -O /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq

# Install docker
RUN apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get update && apt-get install -y docker-ce

# Set default user
ARG USERNAME=vscode
ARG USERHOME=/home/${USERNAME}
RUN useradd -m ${USERNAME} && chown -R ${USERNAME}:${USERNAME} ${USERHOME}
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

ADD init.sh ${USERHOME}/init.sh
ADD aliases.sh ${USERHOME}/aliases.sh
RUN chmod 777 ${USERHOME}/*.sh && dos2unix ${USERHOME}/*.sh
RUN echo "export PATH=$PATH:/workspace/MIMS" >> ${USERHOME}/.bashrc
RUN echo "source ${USERHOME}/aliases.sh" >> ${USERHOME}/.bashrc

USER ${USERNAME}
WORKDIR ${USERHOME}
