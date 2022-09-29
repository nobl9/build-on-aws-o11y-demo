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

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
    }
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

  prom_service_account_name = "amazon-managed-service-prometheus"
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
  private_subnets = local.cidr_blocks.0
  public_subnets  = local.cidr_blocks.1
  intra_subnets   = local.cidr_blocks.2

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
          image             = "ghcr.io/nobl9/build_on_aws_demo_load:steps-three"
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
      app = "Server"
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
          app = "Server"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        container {
          image             = "ghcr.io/nobl9/build_on_aws_demo_server:steps-three"
          name              = "server"
          image_pull_policy = "Always"

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

resource "random_pet" "irsa_role" {}

module "amazon_managed_service_prometheus_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.2.0"

  role_name                                       = "${local.prom_service_account_name}-${random_pet.irsa_role.id}"
  attach_amazon_managed_service_prometheus_policy = true

  oidc_providers = {
    ex = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${var.k8s_namespace}-prometheus:${local.prom_service_account_name}-${random_pet.irsa_role.id}",
        "${var.k8s_namespace}-grafana:${local.prom_service_account_name}-${random_pet.irsa_role.id}"
      ]
    }
  }

  tags = local.tags
}

/*===========================================
 *
 * O11Y
 *
 */
resource "aws_prometheus_workspace" "demo" {
  alias = "${local.name}-prometheus"
}

resource "helm_release" "metrics_server" {
  name             = "${local.name}-metrics"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "${var.k8s_namespace}-metrics-server"
  create_namespace = true
  version          = "3.8.2"
}

resource "helm_release" "prometheus" {
  name             = "${local.name}-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "${var.k8s_namespace}-prometheus"
  create_namespace = true
  version          = "15.9.0"

  lint = true

  values = [
    <<-EOT
serviceAccounts:
  server:
    name: ${module.amazon_managed_service_prometheus_irsa_role.iam_role_name}
    annotations:
      eks.amazonaws.com/role-arn: ${module.amazon_managed_service_prometheus_irsa_role.iam_role_arn}
  alertmanager:
    create: false
  pushgateway:
    create: false
server:
  statefulSet:
    enabled: true
    persistentVolume:
      enabled: true
  remoteWrite:
    - url: "${aws_prometheus_workspace.demo.prometheus_endpoint}api/v1/remote_write"
      sigv4:
        region: ${var.region}
      queue_config:
        max_samples_per_send: 1000
        max_shards: 200
        capacity: 2500
prometheusSpec:
  resources:
    limits:
      cpu: 250m
      memory: 2000Mi
    requests:
      cpu: 50m
      memory: 1300Mi
  storageSpec:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
nodeExporter:
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9100"
alertmanager:
  enabled: false
pushgateway:
  enabled: false
extraScrapeConfigs: |
  - job_name: prometheus-amp
    metrics_path: /metrics
    scrape_interval: 10s
    scheme: http
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - ${var.k8s_namespace}-server
    relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      regex: "true"
      replacement: $1
      action: keep
    - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
      action: replace
      regex: ([^:]+)(?::\d+)?;(\d+)
      replacement: $1:$2
      target_label: __address__
EOT
  ]
}

resource "helm_release" "grafana" {
  name             = "${local.name}-grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  namespace        = "${var.k8s_namespace}-grafana"
  create_namespace = true
  version          = "6.32.2"

  values = [
    <<-EOT
serviceAccount:
    name: ${module.amazon_managed_service_prometheus_irsa_role.iam_role_name}
    annotations:
      eks.amazonaws.com/role-arn: ${module.amazon_managed_service_prometheus_irsa_role.iam_role_arn}
grafana.ini:
  auth:
    sigv4_auth_enabled: true
persistence:
  enabled: true
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: ${aws_prometheus_workspace.demo.prometheus_endpoint}
      jsonData:
        sigV4Auth: true
        sigV4AuthType: default
        sigV4Region: ${var.region}
      isDefault: true
EOT
  ]
}

