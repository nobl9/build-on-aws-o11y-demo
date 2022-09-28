provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
  }
}

locals {
  name = var.name == "" ? replace(basename(path.cwd), "_", "-") : var.name

  tags = {
    Name  = local.name
    Owner = "terraform"
  }

  # the primary cidr block for this
  cidr_block  = "10.0.0.0/16"
  cidr_blocks = [for cidr_block in cidrsubnets(local.cidr_block, 4, 4, 4) : cidrsubnets(cidr_block, 4, 4, 4)]
}

data "aws_caller_identity" "current" {}

/*===========================================
 *
 * TERRAFORM BACKEND
 *
 */
resource "aws_s3_bucket" "terraform_state" {
  bucket = "build-on-aws-o11y-demo-terraform-state"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${local.name}-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

/*===========================================
 *
 * NETWORK
 *
 */
resource "aws_security_group" "additional" {
  description = "additional security group"
  name_prefix = "${local.name}-additional"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }

  tags = local.tags
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.cidr_block

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = local.cidr_blocks[0]
  public_subnets  = local.cidr_blocks[1]
  intra_subnets   = local.cidr_blocks[2]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

/*===========================================
 *
 * CLUSTER
 *
 */
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "18.26.3"
  cluster_version = "1.22"

  cluster_name                    = local.name
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # Encryption key
  create_kms_key = true
  cluster_encryption_config = [{
    resources = ["secrets"]
  }]
  kms_key_deletion_window_in_days = 7
  enable_kms_key_rotation         = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_ntp_ipv4_cidr_block = ["169.254.169.123/32"]
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  #
  # Self Managed Node Group(s)
  self_managed_node_group_defaults = {
    vpc_security_group_ids       = [aws_security_group.additional.id]
    iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  }

  self_managed_node_groups = {
    min_size     = 1
    max_size     = 3
    desired_size = 2
    spot = {
      instance_type = "m5.large"
      instance_market_options = {
        market_type = "spot"
      }

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

      post_bootstrap_user_data = <<-EOT
        cd /tmp
        sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
        sudo systemctl enable amazon-ssm-agent
        sudo systemctl start amazon-ssm-agent
        EOT
    }
  }

  # aws-auth configmap
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true

  aws_auth_users = [
    {
      userarn  = data.aws_caller_identity.current.arn,
      username = data.aws_caller_identity.current.user_id,
      groups   = ["system:masters"]
    }
  ]

  aws_auth_accounts = [
    data.aws_caller_identity.current.id
  ]

  tags = local.tags
}

/*===========================================
 *
 * APP
 *
 */
resource "kubernetes_namespace" "load" {
  metadata {
    name = "${var.k8s_namespace}-load-generation"
  }
}

resource "kubernetes_deployment" "load" {
  metadata {
    name      = "${local.name}-load-generation"
    namespace = "${var.k8s_namespace}-load-generation"
    labels = {
      app = "LoadGeneration"
    }
  }

  spec {
    replicas = 5

    selector {
      match_labels = {
        app = "LoadGeneration"
      }
    }

    template {
      metadata {
        labels = {
          app = "LoadGeneration"
        }
      }

      spec {
        container {
          image             = "ghcr.io/nobl9/build_on_aws_demo_load:steps-one"
          name              = "load"
          image_pull_policy = "Always"

          env {
            name  = "HOST"
            value = "http://${local.name}-server.${var.k8s_namespace}-server.svc.cluster.local:8080"
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.load]
}

resource "kubernetes_namespace" "server" {
  metadata {
    name = "${var.k8s_namespace}-server"
  }
}

resource "kubernetes_deployment" "server" {
  metadata {
    name      = "${local.name}-server"
    namespace = "${var.k8s_namespace}-server"
    labels = {
      app                          = "Server"
      "tags.datadoghq.com/env"     = "dev"
      "tags.datadoghq.com/service" = "build-on-aws-demo-server"
      "tags.datadoghq.com/version" = "1.0"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "Server"
      }
    }

    template {
      metadata {
        labels = {
          app                          = "Server"
          "tags.datadoghq.com/env"     = "dev"
          "tags.datadoghq.com/service" = "build-on-aws-demo-server"
          "tags.datadoghq.com/version" = "1.0"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        volume {
          host_path {
            path = "/var/run/datadog/"
          }
          name = "apmsocketpath"
        }

        container {
          image             = "ghcr.io/nobl9/build_on_aws_demo_server:steps-one"
          name              = "server"
          image_pull_policy = "Always"

          volume_mount {
            name       = "apmsocketpath"
            mount_path = "/var/run/datadog"
          }

          env {
            name  = "DD_HOSTNAME"
            value = "datadog-build-on-aws-demo.datadoog.svc.cluster.local"
          }
          env {
            name = "DD_ENV"
            value_from {
              field_ref {
                field_path = "metadata.labels['tags.datadoghq.com/env']"
              }
            }
          }

          env {
            name = "DD_SERVICE"
            value_from {
              field_ref {
                field_path = "metadata.labels['tags.datadoghq.com/service']"
              }
            }
          }
          env {
            name = "DD_VERSION"
            value_from {
              field_ref {
                field_path = "metadata.labels['tags.datadoghq.com/version']"
              }
            }
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/good"
              port = 8080
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.server]
}

resource "kubernetes_service" "server" {
  metadata {
    name      = "${local.name}-server"
    namespace = kubernetes_deployment.server.metadata[0].namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.server.metadata[0].labels.app
    }
    port {
      port        = 8080
      target_port = 8080
    }
  }
  depends_on = [kubernetes_namespace.server]
}
