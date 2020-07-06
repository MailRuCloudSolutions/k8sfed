Install:
Ubuntu: 
nodejs
iam-authenticator
(yes) eksctl  (see https://github.com/weaveworks/eksctl)
(yes) kubectl (see https://eksworkshop.com/020_prerequisites/k8stools/)
(yes) kubefedctl (see https://github.com/kubernetes-sigs/kubefed/blob/master/docs/installation.md)
(yes) helm 2x
aws cli 
cdk
pip -> python3 (check)


MCS: 
source mcs-cluster-setup/aws-fed-openrc.sh


@todo: 
1. EKS public endpoint: restrict
2. 


Setup eks: 
0. Make sure to disable "Managed creds" in Cloud9 (see eksworkshop)
1. eksctl + cluster.yaml: eksctl create cluster -f cluster.yaml
2. create rbac role for tiller: kubectl apply -f rbac-tiller.yaml
3. init helm tiller : helm init --service-account tiller
4. add repo: helm repo add kubefed-charts https://raw.githubusercontent.com/kubernetes-sigs/kubefed/master/charts
5. install kubefed chart: helm install kubefed-charts/kubefed --name kubefed --version=0.1.0-rc6 --namespace kube-federation-system
6. create merged kubeconfig with two clusters info. !NB Change AWS api endpoint to lowercase (example kubeconfig.yaml)
7. join clusters:
kubefedctl join eks-kubefed --cluster-context eks-kubefed --host-cluster-context eks-kubefed --v=2
kubefedctl join kubernetes-cluster-5454 --cluster-context default/kubernetes-cluster-5454 --host-cluster-context eks-kubefed --v=2
8. create test namespace : kubectl apply -f namespace.yaml 
9. create federated namespace : kubectl apply -f federated-namespace.yaml 
10. create fedeareted deployment kubectl apply -f federated-nginx.yaml 
11. change deployment policy: 
12. 

ExternalDNS setup 
1. Create policy: aws iam create-policy --policy-name AllowExternalDNSUpdates --policy-document file://policy
2. create service role:
eksctl utils associate-iam-oidc-provider --region=eu-central-1 --cluster=kubefed --approve
eksctl create iamserviceaccount \
    --name allowaxternaldnsupdates \
    --namespace test \
    --cluster kubefed \
    --attach-policy-arn arn:aws:iam::633127108222:policy/AllowExternalDNSUpdates \
    --approve \
    --override-existing-serviceaccounts
3. get hosted zone id : aws route53 list-hosted-zones-by-name --output json --dns-name "mcs-aws.kubefed.local" | jq -r '.HostedZones[0].Id'
4. kubectl apply -f external-dns.yaml -n test

Site-to-Site VPN setup:
full description is here - https://docs.aws.amazon.com/vpn/latest/s2svpn/SetUpVPNConnections.html 
1. Create VPC with no overlapping CIDR block with external on-premise site
2. Create a Customer Gateway with MCS external IP (Thats MCS endpoint 89.208.230.187)
2. Create a Virtual Private Gateway (Default ASN)
3. Create Subnet without overlapping CIDR 
4. Security Group with allow traffic (SSH, ICMP ALL to check PING etc)
6. Create VPN-site-to-site connection, associate with CGW, VPG and with static route prefix (192.168.10.0/24 = MCS subnet)
7. Create Routing table with external CIDR block (192.168.10.0/24) or just add auto propagation from VGW, associated with subnet (preferable way)

Its possible to get VPN connection configuration using that request (xml file): 
aws ec2 describe-vpn-connections --vpn-connection-id vpn-00e01e263c899595e 

--- Kubefed helper scripts/commands 
Check kubefed status:
kubectl -n kube-federation-system get kubefedclusters
KubeFed version: rc6

Federation links: 
https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md#helm-chart-deployment (propagation status) 
https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md#verify-your-deployment-is-working

Check podes in federated clusters:
kubectl get po -n test  --context default/kubernetes-cluster-5454
kubectl get po -n test  --context  eks-kubefed

Example for federation: https://github.com/kairen/aws-k8s-federation
