# Docker image for k8sfed

This image is intended to use in interactive mode. Without specifying mounts, command would be:

```bash
docker run -it aws-mcs-k8s-federation /bin/bash
```

Main script is `super-big-script.sh`. After specifying credentials (see Inputs), run:

```bash
./super-big-script.sh
```

## Inputs

* AWS credentials: two methods to provide them
  * After starting the container in interactive mode run `aws configure`
  * When starting the container mount credentials folder, e.g. `-v ~/.aws:/root/.aws`
* MCS credentials: standard openrc file should be used, see [help](https://mcs.mail.ru/help/iaas-api/openstack-api). It is expected at the location `/app/openrc`. Again two methods:
  * After starting the container copy the openrc file, e.g. using `cat <<EOF> openrc`
  * Mount it when starting, e.g. `-v ~/openrc.sh:/app/openrc`

## Outputs

* Keypair for accessing Kubernetes cluster in MCS will be stored in `/app/k8s-fed_id_rsa`. Save it, before exiting container.
