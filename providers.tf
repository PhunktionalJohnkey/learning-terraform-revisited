terraform {
  required_version = ">= 1.6.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
#      version = "3.29.1" # currently does not support Mac M2 processors
      version = "~> 3.26"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-west-2"
  access_key = "AKIATQ4VUGSF5Z37FA6B"
  secret_key = "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"
}
