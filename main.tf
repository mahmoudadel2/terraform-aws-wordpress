# Configure AWS connection, secrets are in terraform.tfvars
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

# Get availability zones for the region specified in var.region
data "aws_availability_zones" "all" {}

# Single mysql node
resource "aws_instance" "wp-aws-mysql" {
  ami = "ami-5652ce39"
  instance_type = "t2.nano"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.wp-aws-lc-sg.id}"]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install docker curl -y
              sudo service docker start
              sudo chkconfig docker on
              mkdir -p /var/lib/mysql/
              docker run --name wp-aws-mysql \
              -v /var/lib/mysql:/var/lib/mysql \
              -v /var/log/mysql:/var/log/mysql \
              -e MYSQL_ROOT_PASSWORD=root \
              -p 3306:3306 \
              -d mysql:5.7
              curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-6.4.2-x86_64.rpm
              sudo rpm -vi filebeat-6.4.2-x86_64.rpm
              echo 'filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/mysql/*
    - /var/log/*.log
output.logstash:
  hosts: ["${aws_instance.wp-aws-elk.private_ip}:5044"]' > /etc/filebeat/filebeat.yml
              sudo service filebeat restart
              sudo chkconfig filebeat on
              EOF
  tags {
    Name = "wp-aws-mysql"
  }
}

# Single elk node
resource "aws_instance" "wp-aws-elk" {
  ami = "ami-5652ce39"
  instance_type = "t2.medium"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.wp-aws-lc-sg.id}"]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install docker curl git -y
              sudo service docker start
              sudo chkconfig docker on
              sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose
              cd /srv
              git clone https://github.com/mahmoudadel2/docker-elk.git
              cd docker-elk/
              /usr/local/bin/docker-compose up -d
              EOF
  tags {
    Name = "wp-aws-elk"
  }
}

resource "aws_autoscaling_notification" "wp-aws-ASG-notifications" {
  group_names = [
    "${aws_autoscaling_group.wp-aws-asg.name}",
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
  ]

  topic_arn = "${var.sns_topic_arn}"
}

# Create autoscaling policy -> target at a 70% average CPU load
resource "aws_autoscaling_policy" "wp-aws-asg-policy-1" {
  name                   = "wp-aws-asg-policy"
  policy_type            = "TargetTrackingScaling"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.wp-aws-asg.name}"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 25.0
  }
}

# Create an autoscaling group
resource "aws_autoscaling_group" "wp-aws-asg" {
  name = "wp-aws-asg"
  launch_configuration = "${aws_launch_configuration.wp-aws-lc.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  min_size = 2
  max_size = 8

  load_balancers = ["${aws_elb.wp-aws-elb.name}"]
  health_check_type = "ELB"

  tag {
    key = "Name"
    value = "wp-aws-ASG"
    propagate_at_launch = true
  }
}

# Create launch configuration
resource "aws_launch_configuration" "wp-aws-lc" {
  name = "wp-aws-lc"
  image_id = "ami-5652ce39"
  instance_type = "t2.nano"
  key_name = "${var.key_name}"
  security_groups = ["${aws_security_group.wp-aws-lc-sg.id}"]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install docker -y
              sudo service docker start
              sudo chkconfig docker on
              docker run --name wp-aws \
              -e WORDPRESS_DB_HOST="${aws_instance.wp-aws-mysql.private_ip}" \
              -e WORDPRESS_DB_USER=root \
              -e WORDPRESS_DB_PASSWORD=root \
              -p 80:80 \
              -d wordpress:latest
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

# Create the ELB
resource "aws_elb" "wp-aws-elb" {
  name = "wp-aws-elb"
  security_groups = ["${aws_security_group.wp-aws-elb-sg.id}"]
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "TCP:${var.http_port}"
  }

  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "${var.http_port}"
    instance_protocol = "http"
  }
}

# Create sticky session for WP
resource "aws_lb_cookie_stickiness_policy" "wp-aws-sticky-session" {
  name                     = "wp-aws-sticky-session"
  load_balancer            = "${aws_elb.wp-aws-elb.id}"
  lb_port                  = 80
  cookie_expiration_period = 600
}

# Create security group that's applied the launch configuration
resource "aws_security_group" "wp-aws-lc-sg" {
  name = "wp-aws-lc-sg"

  # Inbound HTTP from anywhere
  ingress {
    from_port = "${var.http_port}"
    to_port = "${var.http_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "${var.ssh_port}"
    to_port = "${var.ssh_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "${var.mysql_port}"
    to_port = "${var.mysql_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "${var.kibana_port}"
    to_port = "${var.kibana_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "${var.logstash_port}"
    to_port = "${var.logstash_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create security group that's applied to the ELB
resource "aws_security_group" "wp-aws-elb-sg" {
  name = "wp-aws-elb-sg"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound HTTP from anywhere
  ingress {
    from_port = "${var.http_port}"
    to_port = "${var.http_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}