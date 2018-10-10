# Display ELB IP address

output "elb_dns_name" {
  value = "${aws_elb.wp-aws-elb.dns_name}"
}

output "kibana_url" {
  value = "http://${aws_instance.wp-aws-elk.public_ip}:${var.kibana_port}"
}
