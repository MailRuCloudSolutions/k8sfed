# Docker image for k8sfed

This image is intended for usage in interactive mode.

## Step 0: Create image

```bash
docker build -t aws-mcs-k8s-federation .
```

## Step 1: Run container

```bash
docker run -it aws-mcs-k8s-federation /bin/bash
```

OR

```bash
docker run -d aws-mcs-k8s-federation
docker exec -it <container ID> /bin/bash
```

## Step 2: Configure AWS credentials

This step may be skipped, if on host machine you have configured credentials in `~/.aws` and during container run you've mounted them, e.g. `-v $HOME/.aws:/root/.aws`. Credentials are expected to be in `/root/.aws`. Otherwise configure them during interactive mode:

```bash
aws configure
```

## Step 3: Configure MCS credentials

Again as in AWS, this step may be skipped, if a correct mount is provided during container run, e.g. `-v $HOME/my-openrc.sh:/app/openrc`. Credentials are expected to be in file `/app/openrc`. See [help](https://mcs.mail.ru/help/iaas-api/openstack-api). It is highly recommended to have password in there, instead of interactive request, e.g. `export OS_PASSWORD="mypass"`.

If you've already have running container, copy the file during interactive mode:

```bash
cat > /app/openrc

<PASTE YOUR OPENRC>

Ctrl+D
```

## Step 4: Run the main script

Main script is `super-big-script.sh`.

```bash
./super-big-script.sh
```

## Outputs

After script has finished, you'll have plenty of files needed for later work **inside** the container. To mitigate possibility of losing them, it is recommeded to copy them somewhere **outside** the container.

* MCS Keypair with name `k8s-fed-XXXX` will be created. Private part will be stored in `/var/tmp/k8s-fed_id_rsa`. It should be used to access VPN server and Kubernetes nodes by SSH.
* MCS KUBECONFIG with private IP will be stored in `/var/tmp/mcs_k8s_cfg`. This is not so critical, because may be reacquired from MCS console or API.
* AWS EKS KUBECONFIG updated to conform to `kubefedctl` tool. This is stored in `/root/.kube/config`.
* AWS VPN configuration is stored in `/var/tmp/vpn_cfg_conn.xml`.
