data "aws_caller_identity" "me" {}
data "aws_elb_service_account" "main" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# ---------- S3: ALB logs ----------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "devops-alb-logs-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Sirf Load Balancer ko logs likhne do
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.me.account_id}/*"
    }]
  })
}

# ---------- S3: App storage ----------
resource "aws_s3_bucket" "app" {
  bucket        = "devops-app-storage-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Servers ko sirf isi bucket ka access
resource "aws_iam_role_policy" "app_bucket" {
  name = "app-bucket-access"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.app.arn}/*"
    }]
  })
}

# ---------- Self-signed certificate ----------
resource "tls_private_key" "cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "cert" {
  private_key_pem       = tls_private_key.cert.private_key_pem
  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
  dns_names             = ["devops-task.local"]

  subject {
    common_name  = "devops-task.local"
    organization = "DevOps Task"
  }
}

resource "aws_acm_certificate" "cert" {
  private_key      = tls_private_key.cert.private_key_pem
  certificate_body = tls_self_signed_cert.cert.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# ---------- Application Load Balancer ----------
resource "aws_lb" "app" {
  name               = "devops-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# HTTP aaye to seedha HTTPS par bhej do
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------- Output ----------
output "app_url" {
  value = "https://${aws_lb.app.dns_name}"
}



resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.app.id
  key    = "app/index.html"
  source = "${path.module}/../app/index.html"
  etag   = filemd5("${path.module}/../app/index.html")
}
