FROM fedora:latest

RUN dnf -y update && dnf -y install \
    bash-completion \
    curl \
    git \
    gh \
    sudo \
    wget \
    which \
    && dnf clean all

RUN groupadd -g 1000 vscode \
    && useradd -u 1000 -g 1000 -m -s /bin/bash vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode

USER vscode
