resource "aws_iam_role" "loadbalancer-controller" {
  name = "loadbalancer-controller"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "loadbalancer-controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.loadbalancer-controller.name
}

resource "kubernetes_namespace" "loadbalancer-controller" {
  metadata {
    name = "loadbalancer-controller"
  }
}

resource "kubernetes_secret" "aws-credentials" {
  metadata {
    name = "aws-credentials"
    namespace = kubernetes_namespace.loadbalancer-controller.metadata.0.name
  }

  data = {
    access-key-id     = var.aws_access_key_id
    secret-access-key = var.aws_secret_access_key
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "loadbalancer-controller" {
  metadata {
    name = "loadbalancer-controller"
    namespace = kubernetes_namespace.loadbalancer-controller.metadata.0.name
  }

  spec {
    selector {
      match_labels = {
        app = "loadbalancer-controller"
      }
    }

    replicas = 1

    template {
      metadata {
        labels = {
          app = "loadbalancer-controller"
        }
      }

      spec {
        container {
          name = "loadbalancer-controller"
          image = "public.ecr.aws/kubernetes-ingress-controller/nginx-ingress-controller:latest"

          args = [
            "/nginx-ingress-controller",
            "--ingress-class=nginx",
            "--configmap=$(POD_NAMESPACE)/nginx-configuration",
            "--default-backend-service=$(POD_NAMESPACE)/default-backend",
            "--publish-service=$(POD_NAMESPACE)/ingress-nginx-controller",
            "--annotations-prefix=nginx.ingress.kubernetes.io",
            "--report-node-internal-ip-address",
            "--enable-modsecurity",
            "--enable-owasp-core-rules"
          ]

          env {
            name  = "POD_NAMESPACE"
            value = kubernetes_namespace.loadbalancer-controller.metadata.0.name
          }

          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.aws-credentials.metadata.0.name
                key  = "access-key-id"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.aws-credentials.metadata.0.name
                key  = "secret-access-key"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 10254
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          ports {
            name = "http"
            container_port = 80
          }

          ports {
            name = "https"
            container_port = 443
          }
        }
      }
    }
  }
}
