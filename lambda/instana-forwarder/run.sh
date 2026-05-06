# build
zip processor.zip handler.py

# deploy
cd terraform
terraform init
terraform apply \
  -var="instana_api_key=${INSTANA_API_KEY}" \
  -var="instana_base_url=https://test-hcp.instana.io" \
  -var="cloudwatch_log_group_name=test-instana" \
  -var="backup_bucket_name=test-instana-backup-logs" \
