terraform {
  required_providers {
    kubernetes = {
      source  = "registry.opentofu.org/hashicorp/kubernetes"
      version = "~> 2.35.1"
    }
    helm = {
      source  = "registry.opentofu.org/hashicorp/helm"
      version = "~> 2.17.0" # Or your desired version
    }
  }
  required_version = ">= 1.9.0"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kubernetes-admin@homekube"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
