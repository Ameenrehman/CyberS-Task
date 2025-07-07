terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state-bucket-ameen1"
    key    = "tfstate/main.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# IAM role for ECS Fargate Task Execution
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "my-fargate-cluster"
}

# Security Group for ECS Task
resource "aws_security_group" "ecs_sg" {
  vpc_id = "vpc-03323aabb25aa6abd"
  name   = "ecs-sg-fargate"

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ecs-sg-fargate" }
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  vpc_id = "vpc-03323aabb25aa6abd"
  name   = "alb-sg-fargate"

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

  tags = { Name = "alb-sg-fargate" }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "fargate-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = ["subnet-0437c1216c89d857c", "subnet-0f27d95ef9ed5eb73"]
  tags               = { Name = "fargate-alb" }
}

# Target Group
resource "aws_lb_target_group" "node_app1" {
  name        = "fargate-node-app1-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = "vpc-03323aabb25aa6abd"
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.node_app1.arn
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "node_app1_logs" {
  name              = "/ecs/node-app1"
  retention_in_days = 7
}

# ECS Task Definition (Fargate)
resource "aws_ecs_task_definition" "node_app1" {
  family                   = "node-app1-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "node-app1"
    image = "593793064016.dkr.ecr.us-east-1.amazonaws.com/myecr-ameen1@sha256:4240419aa95be71ad66633e17296e6002f938de29ee973031c8162c62c85e857"
    essential = true
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/node-app1"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ECS Fargate Service
resource "aws_ecs_service" "node_app1" {
  name            = "node-app1-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.node_app1.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-0437c1216c89d857c", "subnet-0f27d95ef9ed5eb73"]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.node_app1.arn
    container_name   = "node-app1"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.main]
}
