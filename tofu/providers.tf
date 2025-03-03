terraform {
  required_providers {
    kubectl = {
      source  = "registry.opentofu.org/gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
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

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kubernetes-admin@homekube"
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "kubernetes-admin@homekube"
}
