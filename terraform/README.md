Terraform
=========

## Backend setup
If you want to use a backend create a `terraform.tf` file in this directory and add the backend configuration. More info on:
https://www.terraform.io/docs/backends/index.html

```
# for terraform cloud state management https://www.terraform.io/docs/backends/types/remote.html
terraform {
  backend "remote" {
    organization = "Your Organization Name"

    workspaces {
      name = "your-workspace-name"
    }
  }
}

# for aws S3 state storage https://www.terraform.io/docs/backends/types/s3.html
terraform {
  backend "s3" {
    bucket = "mybucket"
    key    = "path/to/my/key"
    region = "eu-west-1"
  }
}
```

## Override vars for development
Create an `override.tf`. The only var that is required to be set in override is `project`
```
variable "project" {
  default = "my_project"
}

# variable "function_name" {
#   default = "my_bless_lambda"
# }

```