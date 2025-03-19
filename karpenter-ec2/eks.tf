locals {
    eks = {
      infra-eks-01 = {
        cluster_version      = "1.32" # 최신 버전
        public_access        = true
        public_access_cidrs  = [ "" ] # 관리자 작업 위치
        vpc                  = module.vpc["infra-vpc"].vpc_id
        subnet_ids           = module.vpc["infra-vpc"].private_subnets
        karpenter            = true
        cluster_addons       = {
          coredns                = {}
          eks-pod-identity-agent = {}
          kube-proxy             = {}
          vpc-cni                = {}
        }

        eks_managed_node_groups = {
          karpenter = {
            min_size     = 2
            max_size     = 4
            desired_size = 2
            instance_types = ["c7i.xlarge"]
            capacity_type  = "ON_DEMAND"
          }     
        }
        node_security_group_tags = {
          "karpenter.sh/discovery" = "infra-eks-01"
        }        
        cloudwatch_log_group_retention_in_days = "1"  
      }
  }
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"
  for_each = local.eks

  cluster_name    = each.key
  cluster_version = each.value.cluster_version

  vpc_id          = each.value.vpc
  subnet_ids      = each.value.subnet_ids

  cluster_endpoint_public_access       = try(each.value.public_access, false)
  cluster_endpoint_public_access_cidrs = try(each.value.public_access_cidrs, [])

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = try(each.value.eks_managed_node_groups, {})

  cluster_addons = try(each.value.cluster_addons, {})

  enable_cluster_creator_admin_permissions = true

  cloudwatch_log_group_retention_in_days = each.value.cloudwatch_log_group_retention_in_days

  node_security_group_tags = try(each.value.node_security_group_tags, {})
}

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  # karpenter = true 인 경우만 적용
  for_each = { for k, v in local.eks : k => v if try(v.karpenter, false) }

  cluster_name    = each.key

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }  
}

output "karpenter_info" {
  value = {
    for cluster_name, cluster_value in local.eks :
    cluster_name => {
      cluster_region    = regex("arn:aws:eks:([a-z0-9-]+):[0-9]+:cluster/.*", module.eks[cluster_name].cluster_arn)[0]
      cluster_version   = module.eks[cluster_name].cluster_version
      node_iam_role_arn = try(module.karpenter[cluster_name].node_iam_role_arn, null)
      queue_name        = try(module.karpenter[cluster_name].queue_name, null)
    }
  }
}
