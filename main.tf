terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.19.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

##############

# Variables

variable "ingress_ports" {
  description = "List of ports open for ingress"
  type = list(number)
  default = [ 22, 80, 443 ]
}

variable "amazon_linux_2_ami" {
  default = "ami-0bb4c991fa89d4b9b"
}

##############

# Creates a VPC named Wordpress VPC

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "wordpress_vpc"
  }
}

resource "aws_subnet" "public_subnet" {
count = 3
availability_zone = element(data.aws_availability_zones.available.names, count.index)
vpc_id = aws_vpc.wordpress_vpc.id
cidr_block = "10.0.${count.index}.0/24"
map_public_ip_on_launch = true
tags = {
  Name = "public-subnet-${count.index}"
 }
}

resource "aws_subnet" "private_subnet" {
count = 3
availability_zone = element(data.aws_availability_zones.available.names, count.index)
vpc_id = aws_vpc.wordpress_vpc.id
cidr_block = "10.0.${count.index + 3}.0/24" 
map_public_ip_on_launch = true 
tags = {
  Name = "private-subnet-${count.index}"
 }
}

##############

# Creates EC2 instance named wordpress_ec2 with security group

resource "aws_instance" "wordpress_ec2" {
  ami = var.amazon_linux_2_ami
  instance_type = "t2.micro"
  key_name = "terraform-key"
  subnet_id = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  tags = {
    Name = "wordpress_ec2"
  }
}

resource "aws_security_group" "wordpress_sg" {
  name = "wordpress-sg"
  description = "Allow inbound traffic for HTTP, HTTPS, and SSH"
  vpc_id = aws_vpc.wordpress_vpc.id
  dynamic "ingress" {
    for_each = var.ingress_ports
    content {
      from_port = ingress.value
      to_port = ingress.value
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-sg"
  }
}

########################

# Creates Internet Gateway and Route Table

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress_igw"
  }
}

resource "aws_route_table" "wordpress_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "wordpress-rt"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count = 3
  subnet_id = aws_subnet.public_subnet.*.id[count.index]
  route_table_id = aws_route_table.wordpress_rt.id
}

resource "aws_security_group" "rds_sg" {
  name = "rds-sg"
  description = "Allow inbound traffic for MySQL"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "rds-sg"
  }
}

resource "aws_db_subnet_group" "private_subnets" {
  name = "private_subnets"
  subnet_ids = aws_subnet.private_subnet[*].id
  tags = {
    Name = "My DB Subnet Group"
  }
}

resource "aws_db_instance" "MySQL" {
allocated_storage = 20
storage_type = "gp2"
engine = "mysql"
engine_version = "5.7"
instance_class = "db.t2.micro"
identifier = "mysql"
username = "admin"
password = "adminadmin"
db_subnet_group_name = aws_db_subnet_group.private_subnets.name
vpc_security_group_ids = [aws_security_group.rds_sg.id] 
skip_final_snapshot = true
tags = {
  Name = "mysql"
 }
}

data "aws_availability_zones" "available" {}