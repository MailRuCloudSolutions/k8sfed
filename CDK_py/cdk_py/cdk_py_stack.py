from aws_cdk import (
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_autoscaling as autoscaling,
    core
)


class CdkPyStack(core.Stack):

    def __init__(self, scope: core.Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)
        cluster_admin = iam.Role(self, "AdminRole",
            assumed_by=iam.AccountRootPrincipal())
            
        vpc = ec2.Vpc(self,"EKSVpc",cidr="10.2.0.0/16")
        
        eksCluster = eks.Cluster(self, "fedcluster", 
            vpc=vpc,
            cluster_name="awsfedcluster",
            kubectl_enabled=True,
            masters_role=cluster_admin,
            default_capacity=2,
            default_capacity_instance=ec2.InstanceType("t3.large"))
        
