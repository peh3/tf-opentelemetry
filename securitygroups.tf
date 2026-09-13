# -----------------------------------------------------------
# 2. Security Group
# -----------------------------------------------------------
resource "aws_security_group" "stack_sg" {
  name        = "otel-stack-sg"
  description = "Security group for OpenTelemetry, Grafana, App, and Jenkins stack"
  vpc_id      = aws_vpc.main.id

  # Allow all internal subnet traffic among the 6 nodes
  ingress {
    description = "Internal subnet mesh communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.subnet_cidr]
  }

  # Public access to UIs and SSH (restrict via var.my_ip in production)
  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Demo App HTTP"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Outbound to internet for package/image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "otel-stack-sg" }
}