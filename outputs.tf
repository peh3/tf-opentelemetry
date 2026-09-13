output "grafana_url" {
  value       = "http://${aws_instance.grafana.public_ip}:3000"
  description = "Grafana Web UI (Preconfigured with Tempo & Prometheus)"
}

output "jenkins_url" {
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
  description = "Jenkins Web UI"
}

output "demo_app_order_endpoint" {
  value       = "http://${aws_instance.app.public_ip}:8000/order"
  description = "Hit this endpoint to generate traces and metrics"
}

output "jenkins_initial_admin_password_command" {
  value       = "ssh ec2-user@${aws_instance.jenkins.public_ip} 'sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword'"
  description = "Command to get Jenkins initial admin key"
}