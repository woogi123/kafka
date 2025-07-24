# Terraform 설정

# AWS Provider 설정 - 오하이오 리전
provider "aws" {
    alias = "ohio"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    region = "us-east-2"
}

# 기본 VPC 데이터 소스
data "aws_vpc" "default" {
  default = true
}

# 기본 서브넷 데이터 소스
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 최신 Amazon Linux 2 AMI 데이터 소스
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# 로컬 Private Key 파일 읽기
data "local_file" "ohio_private_key" {
  filename = "${path.module}/test-key.pem"
}

# Private Key에서 Public Key 추출
data "tls_public_key" "ohio_existing_key" {
  private_key_pem = data.local_file.ohio_private_key.content
}

# AWS Key Pair 생성
resource "aws_key_pair" "ohio_test_key" {
  key_name   = "test-key"
  public_key = data.tls_public_key.ohio_existing_key.public_key_openssh

  tags = {
    Name = "test-key"
  }
}

# EC2 인스턴스용 보안 그룹
resource "aws_security_group" "ohio_ec2_sg" {
  name        = "docker-compose-sg"
  description = "Security group for Docker-Compose EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH 접근 허용 (포트 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-compose-sg"
  }
}

# RDS용 보안 그룹
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS instances"
  vpc_id      = data.aws_vpc.default.id

  # MySQL/Aurora 접근 허용 (포트 3306) - EC2 보안 그룹에서
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ohio_ec2_sg.id]
  }

  # PostgreSQL 접근 허용 (포트 5432) - 모든 곳에서
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}

# EC2 인스턴스 (Docker-Compose)
resource "aws_instance" "ohio_docker_compose" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "m5.xlarge"
  key_name      = aws_key_pair.ohio_test_key.key_name

  vpc_security_group_ids = [aws_security_group.ohio_ec2_sg.id]

  tags = {
    Name = "Docker-Compose"
  }
}

# RDS 서브넷 그룹 (MySQL과 PostgreSQL에서 공유)
resource "aws_db_subnet_group" "default" {
  name       = "ohio_default-vpc"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "Default VPC DB subnet group"
  }
}

# MySQL RDS 인스턴스
resource "aws_db_instance" "ohio_mysql" {
  identifier             = "dcmysqldb"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "dcmysqlDB"
  username               = "dcadmin"
  password               = "dcmaster!"
  parameter_group_name   = "default.mysql8.0"
  option_group_name      = "default:mysql-8-0"
  
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name
  
  publicly_accessible = true
  skip_final_snapshot = true

  tags = {
    Name = "dcmysqldb"
  }
}

# PostgreSQL RDS 인스턴스
resource "aws_db_instance" "ohio_postgresql" {
  identifier             = "dcpostgresql"
  allocated_storage      = 20
  storage_type           = "gp3"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t4g.micro"
  db_name                = "dcpostgreDB"
  username               = "dcadmin"
  password               = "dcmaster!"
  parameter_group_name   = "default.postgres16"
  
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name
  
  publicly_accessible = true
  skip_final_snapshot = true

  tags = {
    Name = "dcpostgresql"
  }
}

# 출력값
output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.ohio_docker_compose.public_ip
}

output "ohio_mysql_endpoint" {
  description = "MySQL RDS instance endpoint"
  value       = aws_db_instance.ohio_mysql.endpoint
}

output "ohio_postgresql_endpoint" {
  description = "PostgreSQL RDS instance endpoint"
  value       = aws_db_instance.ohio_postgresql.endpoint
}

output "ohio_private_key_path" {
  description = "SSH 접근을 위한 Private Key 경로"
  value       = "${path.module}/test-key.pem"
}