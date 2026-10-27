variable "aws_region" {
  type        = string
  description = "Target AWS deployment region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., production, staging)"
  default     = "production"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the dedicated VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks for load balancers"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks for EC2 workload instances"
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "ami_id" {
  type        = string
  description = "Packer-built golden AMI ID for the launch template"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance sizing"
  default     = "t3.medium"
}

variable "asg_min_size" {
  type        = number
  description = "Minimum capacity of the Auto Scaling Group"
  default     = 2
}

variable "asg_max_size" {
  type        = number
  description = "Maximum capacity of the Auto Scaling Group"
  default     = 4
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired capacity of the Auto Scaling Group"
  default     = 2
}
