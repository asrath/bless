variable "region" {
  default = "eu-west-1"
}

variable "function_name" {
  default = "bless"
}

variable "owner" {
  default = "spaii"
}

variable "project" {}

variable "aws_lambda_basic_execution_role_arn" {
  default = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

variable "aws_ssm_managed_instance_core_arn" {
  default = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
