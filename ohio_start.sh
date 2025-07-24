cd ohio
terraform init
terraform plan -var-file="../common/terraform.tfvars"
terraform apply -var-file="../common/terraform.tfvars"