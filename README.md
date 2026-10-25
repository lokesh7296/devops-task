# AWS DevOps Task: Terraform + GitHub Actions

## Architecture
mermaid
flowchart LR
  U[Internet] -->|HTTPS 443| ALB[Application Load Balancer]
  ALB --> A[EC2 - AZ a, private]
  ALB --> B[EC2 - AZ b, private]
  A --> DB[(RDS MySQL, private)]
  B --> DB
  A -.-> SM[Secrets Manager]
  ALB -.access logs.-> S3[S3 logs bucket]


## What is built
- VPC, 2 public + 2 private subnets (2 AZs), Internet Gateway, NAT Gateway, route tables
- EC2 Auto Scaling Group with Launch Template (t3.micro, min 2)
- Application Load Balancer with HTTPS (HTTP redirects to HTTPS)
- RDS MySQL in private subnets, encrypted at rest
- DB credentials in AWS Secrets Manager
- IAM role with least privilege, restricted Security Groups
- S3 buckets for app storage and ALB access logs (private, encrypted)
- GitHub Actions pipeline: fmt, validate, plan, apply, health check

## Note on HTTPS
No domain was available, so a self-signed certificate is used and the browser shows a warning (click Advanced, then Proceed). With a domain, replace it with an ACM certificate and a Route 53 record.

## Deploy
1. Add repo secrets AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
2. Actions tab, Run workflow, choose apply. The pipeline deploys and runs a health check.
3. Open the app_url shown in the Apply step.
4. To remove everything: Run workflow, choose destroy.

## Screenshots
See the screenshots folder.
