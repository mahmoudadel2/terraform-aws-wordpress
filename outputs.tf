# Display ELB IP address

output "elb_dns_name" {
  value = "${aws_elb.wp-aws-elb.dns_name}"
}