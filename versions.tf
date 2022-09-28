terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.21.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.12.1"
    }
  }

  backend "s3" {
    # Replace this with your bucket name!
    bucket         = "build-on-aws-o11y-demo-terraform-state"
    key            = "global/s3/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "build-on-aws-o11y-demo-locks"
    encrypt        = true
  }

  required_version = ">= 1.0.11"
}

