# This playbook creates an AWS infrastructure with a VPC, public subnet, Internet Gateway, route table, security group, EC2 instances for MySQL and WordPress, and IAM roles.
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.source.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.source.arn}/*"
      }
    ]
  })
}

# Destination Bucket
resource "aws_s3_bucket" "destination" {
  provider = aws.destination
  bucket   = "luitbnk-s3-backup"
  acl      = "private"
}

resource "aws_s3_bucket_versioning" "destination" {
  provider = aws.destination
  bucket   = aws_s3_bucket.destination.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Source Bucket
resource "aws_s3_bucket" "source" {
  provider = aws.source
  bucket   = "luitbnk-website"
  #acl      = "private"
  acl      = "public-read"
  force_destroy = true
  tags = {
    Name        = "source-bucket"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "source" {
  provider = aws.source
  bucket   = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role for Replication
resource "aws_iam_role" "replication" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "s3.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "s3-replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ],
        Resource = aws_s3_bucket.source.arn
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ],
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Resource = "${aws_s3_bucket.destination.arn}/*"
      }
    ]
  })
}

# Replication Configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.source
  bucket   = aws_s3_bucket.source.id
  role     = aws_iam_role.replication.arn

  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.destination
  ]

  rule {
    id     = "replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD"
    }
  }
}

resource "aws_s3_bucket_website_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.source.id
  key          = "index.html"
  source       = "./index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.source.id
  key          = "error.html"
  source       = "./error.html"
  content_type = "text/html"
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for luitbnk-website"
}
resource "aws_s3_bucket_policy" "cdn" {
  bucket = aws_s3_bucket.source.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.source.arn}/*"
      }
    ]
  })
}


# Create CloudFront distribution
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.source.bucket_regional_domain_name
    origin_id   = "s3-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for luitbnk-website"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "dev"
  }
}


/*
# Create the S3 bucket
resource "aws_s3_bucket" "static_site" {
  bucket        = "luitbnk-s3"  # Ensure this is globally unique
  force_destroy = true
}

# Set object ownership to allow ACLs
resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.static_site.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

# Define the bucket ACL
resource "aws_s3_bucket_acl" "bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.ownership]
  bucket     = aws_s3_bucket.static_site.id
  acl        = "public-read"
}

# Configure public access settings
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

locals {
  website_files = fileset("${path.module}/website", "**")
}

resource "aws_s3_object" "website_files" {
  for_each     = { for file in local.website_files : file => file }
  bucket       = aws_s3_bucket.static_site.id
  key          = each.key
  source       = "${path.module}/website/${each.key}"
  content_type = lookup(var.content_types, split(".", each.key)[1], "application/octet-stream")
  acl          = "public-read"
}

# Upload index.html
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_site.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  acl          = "public-read"
}

# Upload error.html
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.static_site.id
  key          = "error.html"
  source       = "${path.module}/error.html"
  #source       = "./error.html"
  content_type = "text/html"
  acl          = "public-read"
}

# Configure website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Define bucket policy for public read access
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.static_site.arn}/*"
      }
    ]
  })
}
*/