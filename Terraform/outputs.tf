output "alb_dns_name" {
  description = "The public endpoint URL of the Application Load Balancer"
  value       = aws_lb.external.dns_name
}

output "alb_target_group_arn" {
  description = "ARN of the target group attached to the ASG"
  value       = aws_lb_target_group.app.arn
}

output "autoscaling_group_name" {
  description = "Name of the provisioned Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  description = "ID of the launch template governing instances"
  value       = aws_launch_template.app.id
}

output "launch_template_latest_version" {
  description = "Latest registered version of the launch template"
  value       = aws_launch_template.app.latest_version
}
