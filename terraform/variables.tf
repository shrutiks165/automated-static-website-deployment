variable "bucket_name" {
  description = "Globally unique S3 bucket name for the website"
  type        = string
  default     = "shrutiks165-static-website"   # <-- change this to something unique
}

variable "environment" {
  description = "Tag applied to all resources"
  type        = string
  default     = "personal-project"
}
