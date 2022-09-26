output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_id" {
  description = "The name/id of the EKS cluster. Will block on cluster creation until the cluster is really ready"
  value       = module.eks.cluster_id
}

output "iam_role_arn" {
  description = "ARN of IAM role"
  value       = module.amazon_managed_service_prometheus_irsa_role.iam_role_arn
}

output "iam_role_name" {
  description = "Name of IAM role"
  value       = module.amazon_managed_service_prometheus_irsa_role.iam_role_name
}

output "iam_role_path" {
  description = "Path of IAM role"
  value       = module.amazon_managed_service_prometheus_irsa_role.iam_role_path
}

output "iam_role_unique_id" {
  description = "Unique ID of IAM role"
  value       = module.amazon_managed_service_prometheus_irsa_role.iam_role_unique_id
}

