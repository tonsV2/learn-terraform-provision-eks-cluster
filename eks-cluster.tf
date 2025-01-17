locals {
  admin_role = [
    {
      rolearn = module.rbac-namespace["admin"].role-arn
      username = "admin"
      groups = [
        "system:masters"
      ]
    }
  ]

  namespace_roles = [for key in keys(var.namespace-users) : {
    rolearn = module.rbac-namespace[key].role-arn
    username = "${key}-user"
    groups = [
      module.rbac-namespace[key].group-name
    ]
  } if key != "admin"]

  map_roles = concat(local.admin_role, local.namespace_roles)
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  cluster_name = var.cluster_name
  cluster_version = "1.19"
  subnets = module.vpc.private_subnets

  tags = {
    Environment = "training"
    GithubRepo = "terraform-aws-eks"
    GithubOrg = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  map_roles = local.map_roles

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  worker_groups = [
    {
      name = "worker-group-1"
      instance_type = "t2.medium"
      additional_userdata = "echo foo bar"
      asg_desired_capacity = 2
      additional_security_group_ids = [
        aws_security_group.worker_group_mgmt_one.id]
    },
    /*
        {
          name = "worker-group-2"
          instance_type = "t2.large"
          additional_userdata = "echo foo bar"
          additional_security_group_ids = [
            aws_security_group.worker_group_mgmt_two.id]
          asg_desired_capacity = 1
        },
    */
  ]

  /* TODO: We should be able to pass a profile when authenticating with the EKS cluster
  (Shouldn't this work? https://github.com/hashicorp/learn-terraform-provision-eks-cluster/issues/38)

  kubeconfig_aws_authenticator_env_variables = {
    AWS_PROFILE = var.profile
  }
  */
}

// TODO: This is probably not the way we want to install the cluster stack
// Possible do it this way, but just call some scripts... install-stack.sh, uninstall-stack.sh
resource "null_resource" "dummy" {
  depends_on = [
    module.eks,
  ]
/*
  provisioner "local-exec" {
    command = "terraform output -raw kubectl_config > ~/.kube/dhis.yaml && export KUBECONFIG=\"$HOME/.kube/dhis.yaml\" && cd stacks/cluster && helmfile sync"
  }
*/
  provisioner "local-exec" {
    when = destroy
    command = "terraform output -raw kubectl_config > ~/.kube/dhis.yaml && export KUBECONFIG=\"$HOME/.kube/dhis.yaml\" && cd stacks/cluster/ingress && helmfile destroy"
  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}
