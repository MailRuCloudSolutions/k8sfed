FROM ubuntu:18.04

ENV NVM_DIR /usr/local/nvm
ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN DEBIAN_FRONTEND=noninteractive apt-get update -y && \
	apt-get install python3 python3-pip python3-venv python-openstackclient curl -y && \
	pip3 install --upgrade pip && \
	pip3 install -q paramiko scp

RUN mkdir -p $NVM_DIR && \
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh | bash - && \
	. $NVM_DIR/nvm.sh && \
	nvm install v12.16.1 && \
	npm install -g aws-cdk

RUN	curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
	mv /tmp/eksctl /usr/local/bin && \
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl

RUN curl -LO https://get.helm.sh/helm-v2.16.3-linux-amd64.tar.gz && \
	tar xzvf helm-v2.16.3-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/

RUN	curl -LO https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc6/kubefedctl-0.1.0-rc6-linux-amd64.tgz && \
	tar xzvf kubefedctl-0.1.0-rc6-linux-amd64.tgz &&  mv kubefedctl /usr/local/bin

RUN apt-get -y install jq
RUN pip3 install awscli --upgrade

COPY . /app
WORKDIR /app

CMD tail -f /dev/null
