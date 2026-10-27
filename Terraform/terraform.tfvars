aws_region           = "us-east-1"
environment          = "production"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

# Replace with your newly baked Packer AMI ID
ami_id               = "ami-0123456789abcdef0"
instance_type        = "t3.medium"

asg_min_size         = 2
asg_max_size         = 4
asg_desired_capacity = 2
