variable "project_name" { type = string }
variable "environment" { type = string }
variable "api_endpoint" { type = string }
variable "alb_dns" {
  type        = string
  description = "ALB DNS name — added as a CloudFront origin so /api/* is proxied over HTTPS"
}
