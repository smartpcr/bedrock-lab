curl -OL https://releases.hashicorp.com/terraform/0.11.14/terraform_0.11.14_darwin_amd64.zip
unzip terraform_0.11.14_darwin_amd64.zip
sudo chmod +x terraform
sudo mv terraform /usr/local/bin/
rm terraform_0.11.14_darwin_amd64.zip