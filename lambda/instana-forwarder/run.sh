# build
zip processor.zip handler.py

# deploy
cd terraform
terraform init
terraform apply \
  -var="instana_api_key=$INSTANA_API_KEY" \
  -var="instana_otlp_url=https://otlp-red-saas.instana.io/v1/logs" \
  -var="cloudwatch_log_group_name=test-instana" \
  -var="backup_bucket_name=test-instana-backup-logs" \


# CloudWatch → Kinesis Firehose → Lambda → Instana
