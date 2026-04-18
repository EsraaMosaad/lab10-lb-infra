provider "aws" {
  region = "us-east-1"
}

# ── Data sources ──────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── Security Groups ───────────────────────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name        = "lab10-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "lab10-ec2-sg"
  description = "Allow traffic only from ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── EC2 Instances ─────────────────────────────────────────────────────────────
resource "aws_instance" "instance_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags                   = { Name = "lab10-instance-1" }

  user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y docker
  systemctl start docker
  systemctl enable docker
  docker network create lab10-net
  docker run -d --name mongo --network lab10-net \
    --restart always mongo:7
  # Wait longer for mongo to fully initialize
  sleep 30
  docker run -d --name lab6-app \
    --network lab10-net \
    --restart always \
    -p 3000:3000 \
    -e MONGO_URI=mongodb://mongo:27017 \
    -e MODE=docker \
    esraamosaad0111/lab6-app:latest
  EOF
}

resource "aws_instance" "instance_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags                   = { Name = "lab10-instance-2" }

  user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y docker
  systemctl start docker
  systemctl enable docker
  docker network create lab10-net
  docker run -d --name mongo --network lab10-net \
    --restart always mongo:7
  # Wait longer for mongo to fully initialize
  sleep 30
  docker run -d --name lab6-app \
    --network lab10-net \
    --restart always \
    -p 3000:3000 \
    -e MONGO_URI=mongodb://mongo:27017 \
    -e MODE=docker \
    esraamosaad0111/lab6-app:latest
  EOF
}

# ── Load Balancer Stack ───────────────────────────────────────────────────────
resource "aws_lb_target_group" "lab10_tg" {
  name     = "lab10-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb" "lab10_alb" {
  name               = "lab10-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_listener" "lab10_listener" {
  load_balancer_arn = aws_lb.lab10_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab10_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.lab10_tg.arn
  target_id        = aws_instance.instance_1.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.lab10_tg.arn
  target_id        = aws_instance.instance_2.id
  port             = 3000
}

# ── Output ────────────────────────────────────────────────────────────────────
output "alb_dns_name" {
  value = aws_lb.lab10_alb.dns_name
}