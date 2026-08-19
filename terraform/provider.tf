terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Stores Terraform's "state" file (a record of what it has built) remotely
  # instead of on your laptop, so GitHub Actions can read/update the same state.
  # You must create this bucket + table manually ONCE before first run (see README).
  backend "s3" {
    bucket         = "shrutiks165-tfstate-bucket"   # <-- change to a globally-unique name
    key            = "static-website/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"              # prevents two runs from clashing
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

# CloudFront needs ACM certs in us-east-1 specifically, but we're using the
# default *.cloudfront.net domain (no custom domain / HTTPS cert), so this
# second provider isn't strictly needed yet. Left here as a comment in case
# you add a custom domain later:
#
# provider "aws" {
#   alias  = "us_east_1"
#   region = "us-east-1"
# }
