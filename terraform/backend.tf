terraform {
  backend "s3" {
    bucket  = "tfstate-lokesh-2290428090"
    key     = "devops-task/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
