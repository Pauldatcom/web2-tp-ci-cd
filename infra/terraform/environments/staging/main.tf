terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "main" {
  name = "devops-${var.environment}"
}

module "webapp" {
  source      = "../../modules/webapp"
  app_name    = var.app_name
  environment = var.environment
  port        = var.web_port
  replicas    = var.web_replicas
  network_id  = docker_network.main.name
}

module "database" {
  source      = "../../modules/database"
  app_name    = var.app_name
  environment = var.environment
  db_password = var.db_password
  db_port     = var.db_port
  network_id  = docker_network.main.name
}

variable "app_name" { type = string }
variable "environment" { type = string }
variable "web_port" { type = number }
variable "web_replicas" { type = number }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_port" { type = number }

output "web_urls" {
  value = module.webapp.urls
}

output "db_connection" {
  value     = module.database.connection_string
  sensitive = true
}

variable "app_log_level" {
  type    = string
  default = "info"
}

output "ansible_inventory" {
  value = yamlencode({
    all = {
      vars = {
        ansible_connection         = "docker"
        ansible_python_interpreter = "/usr/bin/python3"
        app_name                   = var.app_name
        app_environment            = var.environment
        app_log_level              = var.app_log_level
        database_host              = module.database.ansible_host.name
        database_port              = module.database.ansible_host.port
      }
      children = {
        webservers = {
          hosts = module.webapp.ansible_hosts
        }
        databases = {
          hosts = {
            (module.database.ansible_host.name) = {}
          }
        }
      }
    }
  })
}