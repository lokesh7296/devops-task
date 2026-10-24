data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "app" {
  name = "devops-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "read_secret" {
  name = "read-db-secret"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "devops-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_launch_template" "app" {
  name_prefix            = "devops-app-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_tokens = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
      encrypted   = true
    }
  }

  user_data = base64encode(<<-EOT
#!/bin/bash
dnf install -y httpd mariadb105 jq
systemctl enable --now httpd
echo "OK" > /var/www/html/health.html

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
SECRET=$(aws secretsmanager get-secret-value --secret-id devops/db-credentials --region ap-south-1 --query SecretString --output text)
DBHOST=$(echo $SECRET | jq -r .host)
DBUSER=$(echo $SECRET | jq -r .username)
DBPASS=$(echo $SECRET | jq -r .password)

if mysql -h $DBHOST -u $DBUSER -p"$DBPASS" -e "SELECT 1" >/dev/null 2>&1; then
  DBSTATUS="Connected"
else
  DBSTATUS="NOT connected"
fi

aws s3 cp s3://${aws_s3_bucket.app.id}/app/index.html /var/www/html/index.html --region ap-south-1
sed -i "s/INSTANCE_ID_HERE/$IID/; s/DB_STATUS_HERE/$DBSTATUS/" /var/www/html/index.html
EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "devops-app" }
  }
}

resource "aws_lb_target_group" "app" {
  name     = "devops-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path    = "/health.html"
    matcher = "200"
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "devops-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 3
  vpc_zone_identifier       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  depends_on = [aws_secretsmanager_secret_version.db, aws_s3_object.index]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}
