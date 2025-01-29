provider "aws" {
  region = "us-east-1"
}

# Create VPC
resource "aws_vpc" "test_demo_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "test-demo-vpc-1"
  }
}

# Create Subnet 1 in Availability Zone 1
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.test_demo_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "test-demo-vpc1-subnet-1"
  }
}

# Create Subnet 2 in Availability Zone 2
resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.test_demo_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "test-demo-vpc1-subnet-2"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "test_demo_igw" {
  vpc_id = aws_vpc.test_demo_vpc.id

  tags = {
    Name = "test-demo-igw"
  }
}

# Create Route Table
resource "aws_route_table" "test_demo_route_table" {
  vpc_id = aws_vpc.test_demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_demo_igw.id
  }

  tags = {
    Name = "test-demo-route-table"
  }
}

# Associate Route Table with Subnet 1
resource "aws_route_table_association" "subnet1_association" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.test_demo_route_table.id
}

# Associate Route Table with Subnet 2
resource "aws_route_table_association" "subnet2_association" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.test_demo_route_table.id
}

# Create ECR repository
resource "aws_ecr_repository" "test_demo_service" {
  name = "test-demo-service-ecr"
}

# Create ECS Cluster
resource "aws_ecs_cluster" "test_demo_service_ecs_cluster" {
  name = "test-demo-service-ecs-cluster"
}

# Create IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "test-demo-service-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the IAM Role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create ECS Task Definition
resource "aws_ecs_task_definition" "test_demo_service_task" {
  family                   = "test-demo-service-ecs-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "test-demo-service-container"
      image     = "${aws_ecr_repository.test_demo_service.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

# Create Security Group for ECS Service and Load Balancer
resource "aws_security_group" "ecs_lb_sg" {
  name        = "test-demo-service-ecs-lb-sg"
  description = "Allow HTTP traffic"
  vpc_id      = aws_vpc.test_demo_vpc.id

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

# Create ECS Service
resource "aws_ecs_service" "test_demo_service_ecs_service" {
  name            = "test-demo-service-ecs-service"
  cluster         = aws_ecs_cluster.test_demo_service_ecs_cluster.id
  task_definition = aws_ecs_task_definition.test_demo_service_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups = [aws_security_group.ecs_lb_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test_demo_service_tg.arn
    container_name   = "test-demo-service-container"
    container_port   = 80
  }
}

# Create Application Load Balancer
resource "aws_lb" "test_demo_service_lb" {
  name               = "test-demo-service-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_lb_sg.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  enable_deletion_protection = false
}

# Create Listener
resource "aws_lb_listener" "test_demo_service_listener" {
  load_balancer_arn = aws_lb.test_demo_service_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test_demo_service_tg.arn
  }
}

# Create Target Group
resource "aws_lb_target_group" "test_demo_service_tg" {
  name        = "test-demo-service-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.test_demo_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Create S3 Bucket for CodePipeline Artifacts
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "test-demo-service-artifacts-${random_id.suffix.hex}"
  acl    = "private"

  tags = {
    Name = "test-demo-service-artifacts"
  }
}

# Create IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "test-demo-service-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

# Create IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "test-demo-service-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

# Create CodeBuild Project
resource "aws_codebuild_project" "test_demo_service_codebuild" {
  name          = "test-demo-service-codebuild"
  service_role  = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = "us-east-1"
    }
  }
  source {
    type      = "CODEPIPELINE"
  }
  cache {
    type = "NO_CACHE"
  }
}

# Create CodePipeline
resource "aws_codepipeline" "test_demo_service_codepipeline" {
  name     = "test-demo-service-codepipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner      = "memoresvasanth"
        Repo       = "test-demo-service"
        Branch     = "main"
        OAuthToken = var.github_oauth_token
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.test_demo_service_codebuild.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "ECS"
      version          = "1"
      input_artifacts  = ["build_output"]

      configuration = {
        ClusterName = aws_ecs_cluster.test_demo_service_ecs_cluster.name
        ServiceName = aws_ecs_service.test_demo_service_ecs_service.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}

output "vpc_id" {
  value = aws_vpc.test_demo_vpc.id
}

output "subnet1_id" {
  value = aws_subnet.subnet1.id
}

output "subnet2_id" {
  value = aws_subnet.subnet2.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.test_demo_service.repository_url
}