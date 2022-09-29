# Build on AWS Observability Demo

This demo creates an Amazon Managed Service for Prometheus workspace, as
well as an EKS cluster with a demo service that exposes
Prometheus metrics, and a load generation script to generate traffic and
metric data. Prometheus is deployed in the cluster, and writes the gathered
metrics to Amazon Managed Service for Prometheus.  This data can then be
visualized using the Grafana instance that is deployed into the cluster. It
it configured to use the the Amazon Managed Service for Prometheus workspace
that is created.

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [oslo](https://github.com/OpenSLO/oslo)
- [yq](https://github.com/mikefarah/yq)
- [Terraform](https://www.terraform.io/)

## Usage

**NOTE** *This is a demo, and meant to be used in development and testing.
Please to do not use this in a production deployment*

To create the resources, from the root directory, you can run
`terraform apply`. Refer to the
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
kubectl get secret --namespace build-on-aws-o11y-demo-grafana observability-demo-complete-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Then forward the port to your local, ex:

```bash
export POD_NAME=$(kubectl get pods --namespace build-on-aws-o11y-demo-grafana -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=observability-demo-complete-grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace build-on-aws-o11y-demo-grafana port-forward $POD_NAME 3000
```

Opening up `https://localhost:3030` will bring up the Grafana login page.
Log in with `admin` and the password from the previous step.

Once you are done, you can call `terraform destroy` to clean up all created
resources.

To convert to nobl9, you can use the following commands:

```bash
oslo convert -p build-on-aws -f slos/slos.yaml -o nobl9 > slos/tmp/converted-slo.yaml
yq ea 'select(fileIndex == 0) * select(fileIndex == 1)' slos/tmp/converted-slo.yaml slos/tmp/override.yaml > nobl9.yaml
```
