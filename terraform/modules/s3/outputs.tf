output "produce_images_bucket_name" {
  value = aws_s3_bucket.produce_images.bucket
}

output "produce_images_bucket_url" {
  value = "https://${aws_s3_bucket.produce_images.bucket}.s3.amazonaws.com"
}

output "delivery_proofs_bucket_name" {
  value = aws_s3_bucket.delivery_proofs.bucket
}
