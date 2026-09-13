variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS deployment region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "Subnet CIDR block"
}

variable "my_ip" {
  type        = string
  default     = "0.0.0.0/0" # Replace with your IP (e.g. "203.0.113.50/32") for security
  description = "Allowed IP range for UI and SSH ingress"
}

variable "key_name" {
  type        = string
  default     = ""
  description = "Optional existing EC2 Key Pair name for SSH"
}