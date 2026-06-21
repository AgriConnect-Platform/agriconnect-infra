# ── Produce Images Bucket (public read) ───────────────────────────────────────
resource "aws_s3_bucket" "produce_images" {
  bucket = var.produce_images_bucket

  tags = { Name = var.produce_images_bucket, Purpose = "produce-images" }
}

resource "aws_s3_bucket_public_access_block" "produce_images" {
  bucket                  = aws_s3_bucket.produce_images.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "produce_images_public_read" {
  bucket     = aws_s3_bucket.produce_images.id
  depends_on = [aws_s3_bucket_public_access_block.produce_images]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.produce_images.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_cors_configuration" "produce_images" {
  bucket = aws_s3_bucket.produce_images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# ── Delivery Proofs Bucket (private) ─────────────────────────────────────────
resource "aws_s3_bucket" "delivery_proofs" {
  bucket = var.delivery_proofs_bucket

  tags = { Name = var.delivery_proofs_bucket, Purpose = "delivery-proofs" }
}

resource "aws_s3_bucket_public_access_block" "delivery_proofs" {
  bucket                  = aws_s3_bucket.delivery_proofs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
