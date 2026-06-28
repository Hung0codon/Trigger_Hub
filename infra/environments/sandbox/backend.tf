terraform {
  backend "s3" {
    bucket         = "tf1-cdo05-tfstate-945125812908"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf1-cdo05-tflock"
    encrypt        = true
  }
}

