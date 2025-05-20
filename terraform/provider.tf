terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Update to your desired region
}

# Define providers for source and destination regions
provider "aws" {
  alias  = "source"
  region = "us-east-1" # Replace with your source region
}

provider "aws" {
  alias  = "destination"
  region = "us-west-2" # Replace with your destination region
}