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
  default = ""
}

variable "sns_topic_arn" {
  default = ""
}

variable "http_port" {
  default = 80
}

variable "ssh_port" {
  default = 22
}

variable "mysql_port" {
  default = 3306
}
