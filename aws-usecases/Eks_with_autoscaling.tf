resource "aws_eks_cluster" "cluster" {
  name     = "Autoscaler"
  role_arn = "arn:aws:iam::376604405359:role/eksClusterRole"

  vpc_config {
    subnet_ids = ["subnet-02b3dd105b1fb0e33","subnet-0fff2c4a5a7501ba8","subnet-0b31198f213e44561"]
  }

    kubernetes_network_config {
        service_ipv4_cidr ="192.168.1.0/24"
    }
}

output "endpoint" {
  value = aws_eks_cluster.cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.cluster.certificate_authority[0].data
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "vpc-cni"
  depends_on        =[aws_eks_cluster.cluster]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "kube-proxy"
  depends_on        =[aws_eks_cluster.cluster]
}
resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.cluster.name
  addon_name        = "coredns"
  addon_version     = "v1.8.4-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
  depends_on        =[aws_eks_cluster.cluster]
}

resource "aws_eks_node_group" "cluster" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "Autoscaler-ng"
  node_role_arn   = "arn:aws:iam::376604405359:role/AmazonEKSNodeRole"
  subnet_ids      = ["subnet-02b3dd105b1fb0e33","subnet-0fff2c4a5a7501ba8","subnet-0b31198f213e44561"]
  disk_size       = 10
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
  url             = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

resource "aws_iam_role" "role" {
  name = "AmazonEKSClusterAutoscalerRole"

  assume_role_policy = jsonencode(
    {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "${aws_iam_openid_connect_provider.cluster.arn}"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "${aws_iam_openid_connect_provider.cluster.url}:sub": "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  }
  )
}


resource "aws_iam_policy" "policy" {
  name        = "AmazonEKSClusterAutoscalerPolicy"
  description = "Autoscaling Policy"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode(
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/k8s.io/cluster-autoscaler/${aws_eks_cluster.cluster.name}": "owned"
                }
            }
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeAutoScalingGroups",
                "ec2:DescribeLaunchTemplateVersions",
                "autoscaling:DescribeTags",
                "autoscaling:DescribeLaunchConfigurations"
            ],
            "Resource": "*"
        }
    ]
}
  )
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}