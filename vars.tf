variable access_key {
  default = ""
}
variable secret_key {
  default = ""
}
variable region {
  default = ""
}
variable key_name {
  default = ""
}

variable iam_instance_profile {
  default = "t2.nano"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  default = 80
}

variable "ssh_port" {
  default = 22
}

variable "mysql_port" {
  default = 3306
}

variable "count" {
  description = "Number of EC2 instances"
  default = 1
}