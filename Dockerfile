FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

ARG TF_VERSION=1.11.4
ARG YQ_VERSION=v4.42.1
ARG NODE_VERSION=18.19.1

RUN tdnf install -y \
  ansible \
  azure-cli \
  ca-certificates \
  curl \
  dos2unix \
  dotnet-sdk-6.0 \
  gawk \
  gh \
  git \
  glibc-i18n \
  gnupg \
  jq \
  moreutils \
  openssl-devel \
  openssl-libs \
  powershell \
  python3 \
  python3-pip \
  python3-virtualenv \
  sshpass \
  sudo \
  tar \
  unzip \
  util-linux \
  acl \
  which

# Install Terraform
RUN curl -fsSo terraform.zip \
 https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip && \
 unzip terraform.zip && \
  install -Dm755 terraform /usr/bin/terraform

# Install Node.js
RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz | tar -xz -C /usr/local --strip-components=1 && \
  ln -s /usr/local/bin/node /usr/bin/node && \
  ln -s /usr/local/bin/npm /usr/bin/npm

# Install yq, as there are two competing versions and Azure Linux uses the jq wrappers, which breaks the GitHub Workflows
RUN curl -sSfL https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64.tar.gz | tar zx && \
  install -Dm755 yq_linux_amd64 /usr/bin/yq && \
  rm -rf yq_linux_amd64.tar.gz yq_linux_amd64 install-man-page.sh yq.1

RUN locale-gen.sh
RUN echo "export LC_ALL=en_US.UTF-8" >> /root/.bashrc && \
    echo "export LANG=en_US.UTF-8" >> /root/.bashrc

RUN pip3 install --upgrade \
    ansible-core \
    argcomplete \
    jmespath \
    netaddr  \
    pip \
    pywinrm \
    setuptools \
    wheel \
    chmod

# Download and extract Microsoft.AspNet.WebApi.Client NuGet package manually
RUN curl -L -o /tmp/webapiclient.nupkg https://www.nuget.org/api/v2/package/Microsoft.AspNet.WebApi.Client/5.2.7 && \
    mkdir -p /tmp/webapiclient && \
    unzip -q /tmp/webapiclient.nupkg -d /tmp/webapiclient && \
    DLL_SRC=/tmp/webapiclient/lib/net45/System.Net.Http.Formatting.dll && \
    for ver in 6.0.0 7.0.0 8.0.0; do \
      mkdir -p /usr/share/dotnet/shared/Microsoft.AspNetCore.App/$ver/; \
      cp $DLL_SRC /usr/share/dotnet/shared/Microsoft.AspNetCore.App/$ver/ || true; \
      mkdir -p /usr/share/dotnet/shared/Microsoft.NETCore.App/$ver/; \
      cp $DLL_SRC /usr/share/dotnet/shared/Microsoft.NETCore.App/$ver/ || true; \
    done && \
    rm -rf /tmp/webapiclient /tmp/webapiclient.nupkg

RUN git clone https://github.com/Azure/SAP-automation-samples.git /source/SAP-automation-samples

RUN tdnf install -y acl
COPY . /source

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

ENV SAP_AUTOMATION_REPO_PATH=/source

ENV SAMPLE_REPO_PATH=/source/SAP-automation-samples

RUN useradd -m -s /bin/bash azureadm
RUN echo "azureadm:password" | chpasswd
RUN usermod -aG sudo azureadm

WORKDIR /source
