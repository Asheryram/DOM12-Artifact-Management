terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.40"
      configuration_aliases = [aws.primary, aws.dr]
    }
  }
}
