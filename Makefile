TF_DIR := terraform/azure-bigip

.PHONY: demo-init demo-plan demo-up demo-destroy-plan demo-down demo-status demo-renewal-proof

demo-init:
	terraform -chdir=$(TF_DIR) init -input=false

demo-plan:
	terraform -chdir=$(TF_DIR) plan -input=false

demo-up:
	terraform -chdir=$(TF_DIR) apply -input=false -auto-approve

demo-destroy-plan:
	terraform -chdir=$(TF_DIR) plan -destroy -input=false

demo-down:
	terraform -chdir=$(TF_DIR) destroy -input=false -auto-approve

demo-status:
	terraform -chdir=$(TF_DIR) output

demo-renewal-proof:
	bash ./scripts/prove_auto_renewal.sh
