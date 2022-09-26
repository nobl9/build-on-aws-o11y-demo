<!-- BEGIN_TF_DOCS -->
# Observability Demo

This module creates an Amazon Managed Service for Prometheus workspace, as
well as a Kubernetes cluster with a demo service that exposes
Prometheus metrics, and a load generation script to generate traffic and
metric data. Prometheus is deployed in the cluster, and writes the gathered
metrics to Amazon Managed Service for Prometheus.  This data can then be
visualized using the Grafana instance that is deployed into the cluster. It
it configured to use the the Amazon Managed Service for Prometheus workspace
that is created.

## Prerequisites

This module requires the [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

## Usage

**NOTE** *This is a demo, and meant to be used in development and testing.
Please to do not use this in a production deployment*

To create the resources, take a look at the example in
`./examples/complete`. From the example directory, you can run
`terraform apply` or add the module to your own project. Refer to the
[documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
for more information on configuring the AWS provider.

Once the resources are created, follow the
[documentation](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html)
on creating a kubeconfig file in order to connect to the cluster. Once that
is created, you can connect to the Prometheus server by forwarding the port
to your local, ex:

```bash
export POD_NAME=$(kubectl get pods --namespace observability-demo-prometheus -l "app=prometheus,component=server" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace observability-demo-prometheus port-forward $POD_NAME 9090
```

Open up `https://localhost:9090` in a browser to access the Prometheus server.

To access the Grafana server, first get the password, ex:

```bash
kubectl get secret --namespace observability-demo-grafana observability-demo-complete-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Then forward the port to your local, ex:

```bash
export POD_NAME=$(kubectl get pods --namespace observability-demo-grafana -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=observability-demo-complete-grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace observability-demo-grafana port-forward $POD_NAME 3000
```

Opening up `https://localhost:3030` will bring up the Grafana login page.
Log in with `admin` and the password from the previous step.

Once you are done, you can call `terraform destroy` to clean up all created
resources.

### Prometheus Metrics

By default, the custom application exposes four metrics:

## Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) (>= 1.0.11)

- <a name="requirement_aws"></a> [aws](#requirement\_aws) (>= 4.21.0)

- <a name="requirement_helm"></a> [helm](#requirement\_helm) (>= 2.6.0)

- <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) (>= 2.12.1)

## Providers

The following providers are used by this module:

- <a name="provider_aws"></a> [aws](#provider\_aws) (>= 4.21.0)

- <a name="provider_helm"></a> [helm](#provider\_helm) (>= 2.6.0)

- <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) (>= 2.12.1)

## Modules

The following Modules are called:

### <a name="module_amazon_managed_service_prometheus_irsa_role"></a> [amazon\_managed\_service\_prometheus\_irsa\_role](#module\_amazon\_managed\_service\_prometheus\_irsa\_role)

Source: terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks

Version: 5.2.0

### <a name="module_eks"></a> [eks](#module\_eks)

Source: terraform-aws-modules/eks/aws

Version: 18.26.3

### <a name="module_vpc"></a> [vpc](#module\_vpc)

Source: terraform-aws-modules/vpc/aws

Version: ~> 3.0

## Resources

The following resources are used by this module:

- [aws_prometheus_workspace.demo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) (resource)
- [aws_security_group.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) (resource)
- [helm_release.grafana](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) (resource)
- [helm_release.metrics_server](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) (resource)
- [helm_release.prometheus](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) (resource)
- [kubernetes_deployment.load](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) (resource)
- [kubernetes_deployment.server](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) (resource)
- [kubernetes_namespace.load](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) (resource)
- [kubernetes_namespace.server](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) (resource)
- [kubernetes_service.server](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) (resource)
- [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) (data source)

## Required Inputs

No required inputs.

## Optional Inputs

The following input variables are optional (have default values):

### <a name="input_k8s_namespace"></a> [k8s\_namespace](#input\_k8s\_namespace)

Description: The kubernetes namespace to use

Type: `string`

Default: `"observability-demo"`

### <a name="input_name"></a> [name](#input\_name)

Description: The name for this project

Type: `string`

Default: `""`

### <a name="input_region"></a> [region](#input\_region)

Description: The region to target for the creation of resources

Type: `string`

Default: `"us-west-2"`

## Outputs

The following outputs are exported:

### <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data)

Description: Base64 encoded certificate data required to communicate with the cluster

### <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint)

Description: Endpoint for your Kubernetes API server

### <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id)

Description: The name/id of the EKS cluster. Will block on cluster creation until the cluster is really ready

### <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn)

Description: ARN of IAM role

### <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name)

Description: Name of IAM role

### <a name="output_iam_role_path"></a> [iam\_role\_path](#output\_iam\_role\_path)

Description: Path of IAM role

### <a name="output_iam_role_unique_id"></a> [iam\_role\_unique\_id](#output\_iam\_role\_unique\_id)

Description: Unique ID of IAM role
<!-- END_TF_DOCS -->
