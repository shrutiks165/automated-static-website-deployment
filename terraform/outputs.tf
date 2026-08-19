output "s3_bucket_name" {
  description = "Name of the S3 bucket holding website files"
  value       = aws_s3_bucket.website.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidation in CI/CD)"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain_name" {
  description = "The URL your website is live at"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}
