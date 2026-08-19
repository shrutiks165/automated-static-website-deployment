##############################################
# S3 BUCKET — stores your website files
##############################################

resource "aws_s3_bucket" "website" {
  bucket = var.bucket_name

  tags = {
    Environment = var.environment
    Project     = "static-website-deployment"
  }
}

# "Block Public Access" — S3's safety switch. We turn ALL public access OFF
# here because CloudFront will be the only thing allowed to read the bucket
# (via the Origin Access Control policy below). This is the "secure" part
# of the project: nobody can hit the S3 URL directly, only your CloudFront URL.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Turns on versioning so old copies of files aren't lost forever when
# GitHub Actions overwrites them on each deploy — handy for rollbacks.
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

##############################################
# CLOUDFRONT — the CDN that sits in front of S3
##############################################

# Origin Access Control (OAC) — the modern, recommended way (replacing the
# older "OAI") for CloudFront to authenticate to a private S3 bucket.
# It lets CloudFront sign its requests to S3 so only CloudFront can read
# the objects, even though the bucket itself is fully private.
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = "index.html" # file served when someone visits "/"
  price_class         = "PriceClass_200" # skips the priciest edge locations; fine for a personal project

  origin {
    # The S3 bucket's REST API domain (not the "website endpoint") —
    # required for OAC to work.
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-website-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https" # forces HTTPS for visitors

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600   # 1 hour — how long CloudFront caches a file before re-checking S3
    max_ttl     = 86400  # 24 hours
  }

  # If someone requests a page that doesn't exist, send them to index.html
  # with a 200 instead of CloudFront's default (ugly) error page. Common
  # pattern for single-page sites; remove/adjust if you build a multi-page site.
  custom_error_response {
    error_code         = 403 # S3 returns 403, not 404, for missing private objects
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # uses the default *.cloudfront.net HTTPS cert
  }

  tags = {
    Environment = var.environment
    Project     = "static-website-deployment"
  }
}

# Bucket policy: allow ONLY this specific CloudFront distribution to
# read objects. This is what OAC enforces — without this policy attached,
# CloudFront would get "access denied" even with the OAC configured above.
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}
