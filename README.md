Sure, here's an enhanced version of your tutorial:

# Vault PKI and NGINX Example

This tutorial guides you through setting up Vault PKI with an NGINX server on a Linux system to manage SSL/TLS certificates. By following these steps, you will create a secure infrastructure that leverages HashiCorp Vault to handle certificate management efficiently. The tutorial is divided into the following sections:

## Table of Contents
1. [Introduction](#introduction)
2. [Install NGINX](#install-nginx)
3. [Configure Vault](#configure-vault)
   - [Logging into Vault](#logging-into-vault)
   - [Create a Root Certificate Authority (CA)](#create-a-root-certificate-authority-ca)
   - [Generate an Intermediate CA](#create-an-intermediate-ca)
   - [Request Certificates for NGINX](#request-certificates-for-nginx)
   - [Verify Certificates](#verify-certificates)
4. [Add Certificates to Trust Store](#add-certificates-to-trust-store)
   - [For Ubuntu](#for-ubuntu)
   - [For CentOS/RHEL](#for-centosrhel)
5. [Generate Certificates and Apply to NGINX](#generate-certificates-and-apply-to-nginx)
6. [Test NGINX](#test-nginx)
7. [Use Vault Agent for Certificate Renewal](#use-vault-agent-for-certificate-renewal)
   - [Create a New AppRole](#create-a-new-approle)
   - [Set Up Vault Agent](#set-up-vault-agent)

## Introduction

This tutorial demonstrates how to integrate HashiCorp Vault's PKI (Public Key Infrastructure) system with an NGINX web server running on a Linux platform. By the end of this tutorial, you'll have a fully functional system that automatically manages SSL/TLS certificates for your NGINX server. This process enhances security and simplifies certificate handling. The tutorial consists of the following steps:

1. **Install NGINX**: Install NGINX on your Linux server.

2. **Configure Vault**:
   - Log in to Vault.
   - Create a root certificate authority (CA).
   - Generate an intermediate CA.
   - Request certificates for NGINX.
   - Verify the certificates.

3. **Add Certificates to Trust Store**: Add root and intermediate certificates to your system's trust store to establish trust for certificates issued by your CA.

4. **Generate Certificates and Apply to NGINX**: Set up NGINX to use the generated certificates for secure connections.

5. **Test NGINX**: Verify NGINX configuration by accessing your server using the generated certificate.

6. **Use Vault Agent for Certificate Renewal**: Set up Vault Agent to automatically renew certificates and update NGINX configurations.

The tutorial provides detailed commands and steps for each of these processes, enabling you to secure your NGINX server with certificates from Vault.

For a more in-depth explanation, follow the tutorial step-by-step. You can refer to the original tutorial for additional information and examples.

[Original Tutorial](https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine)

## Install NGINX

First, ensure that NGINX is installed on your Linux server. The following command demonstrates the installation on Ubuntu, but you can adapt it for Red Hat Enterprise Linux (RHEL) or SUSE.

```bash
sudo apt-get install nginx jq
```

## Configure Vault

This section involves a series of steps to configure HashiCorp Vault for certificate management:

### Logging into Vault

To begin, log into your Vault instance using the following commands:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
vault login
```

### Create a Root Certificate Authority (CA)

In this step, you create a root certificate authority (CA) that will be used to sign an intermediate store. You will also use the `root_2023_ca.crt` certificate for later trust store setup. 

```bash
# Enable the PKI secrets engine
vault secrets enable pki

# Configure the PKI engine
vault secrets tune -max-lease-ttl=87600h pki

# Generate the root CA certificate
vault write -field=certificate pki/root/generate/internal \
     common_name="example.com" \
     issuer_name="root-2023" \
     ttl=87600h > root_2023_ca.crt

# Define roles and URLs
vault write pki/roles/2023-servers allow_any_name=true

vault write pki/config/urls \
     issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
     crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
```

### Create an Intermediate CA

In this step, you'll create an intermediate CA using the root CA you generated earlier.

```bash
# Enable the intermediate PKI secrets engine
vault secrets enable -path=pki_int pki

# Configure the intermediate PKI engine
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate an intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="example.com Intermediate Authority" \
     issuer_name="example-dot-com-intermediate" \
     | jq -r '.data.csr' > pki_intermediate.csr

# Sign the intermediate CA with the root CA
vault write -format=json pki/root/sign-intermediate \
     issuer_ref="root-2023" \
     csr=@pki_intermediate.csr \
     format=pem_bundle ttl="43800h" \
     | jq -r '.data.certificate' > intermediate.cert.pem

# Set the signed intermediate certificate
vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

# Define roles for the intermediate CA
vault write pki_int/roles/example-dot-com \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="example.com" \
     allow_subdomains=true \
     max_ttl="720h"
```

### Request Certificates for NGINX

Generate certificates that you will use later with NGINX.

```bash
vault write -format=json pki_int/issue/example-dot-com common_name="test.example.com" ttl="24h" > nginx_certs.json

# Extract private key, certificate, and CA chain
jq -r '.data.private_key' nginx_certs.json > nginx_private_key.pem
jq -r '.data.certificate' nginx_certs.json > nginx_certificate.pem
jq -r '.data.ca_chain[]' nginx_certs.json > nginx_ca_chain.pem
cat nginx_certificate.pem nginx_ca_chain.pem > nginx_certificate_chain.pem
```

### Verify Certificates

Use OpenSSL to verify the certificate.

```bash
openssl verify -CAfile root_2023_ca.crt -untrusted intermediate.cert.pem nginx_certificate.pem
```

## Add Certificates to Trust Store

Let's outline what certificates have been created:

| File                    | Description                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| root_2023_ca.crt        | The Root CA's certificate                                                                          |
| intermediate.cert.pem   | The intermediate CA's certificate                                                                  |
| pki_intermediate.csr    | The CSR used to sign the intermediate CA                                                           |
| nginx_certs.json        | A JSON file including all the certs generated by the issue command                                 |
| nginx_private_key.pem   | A short-lived private key for the `test.example.com` domain based on the `example-dot-com` role    |
| nginx_certificate.pem    | A short-lived certificate for the `test.example.com` domain based on the `example-dot-com` role   |
| nginx_ca_chain.pem      | A short-lived certificate chain, this contains the SSL/TLS Certificate and Certificate Authority (CA) Certificates, that enable the receiver to verify that the sender and all CAs are trustworthy |
| nginx_certificate_chain.pem | The cert and chain combined, used by NGINX            

To establish trust for certificates issued by your CA, you need to add the root certificates to your system's trust store. The following sections provide instructions for different Linux distributions:

### For Ubuntu

```bash
sudo cp root_2023_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### For CentOS/RHEL

```bash
yum install ca-certificates
update-ca-trust force-enable
cp root_2023_ca.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
```

## Generate Certificates and Apply to NGINX

This section guides you in setting up NGINX to use the generated certificates. First, copy the certificates to an appropriate location.

```bash
sudo mkdir /etc/nginx/keys
sudo cp nginx_private_key.pem nginx_certificate_chain.pem /etc/nginx/keys/
```

Next, update the NGINX configuration to enable TLS and use the new keys. You need to add the following lines to your enabled site configuration (usually located at `/etc/nginx/sites-enabled/default`). You can also look in the `default` file in this directory as an example.

```nginx
    listen 443 ssl default_server;
    ssl_certificate /etc/nginx/keys/nginx_certificate_chain.pem;
    ssl_certificate_key /etc/nginx/keys/nginx_private_key.pem;
```

Finally, restart NGINX.

```bash
sudo systemctl restart nginx
```

## Test NGINX

To test your NGINX setup, access your server using the generated certificate. Make sure to use the correct host header, as your certificate is issued for `test.example.com`.

```bash
curl --resolve test.example.com:443:127.0.0.1 https://test.example.com/
```

# Use Vault Agent for Certificate Renewal

While your NGINX setup is now secure, the certificates have a limited validity period. To address this, you can use Vault Agent to automatically renew certificates and update NGINX configurations.

### Create a New AppRole

To begin, create a new AppRole and define its policy.

```bash
mkdir -p /tmp/certs
cat <<EOF > /tmp/certs/cert.policy
path "pki_int/issue*" {
  capabilities = ["create","update"]
}
path "auth/token/renew" {
  capabilities = ["update"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

# Write the policy
vault policy write cert-policy /tmp/certs/cert.policy

# Enable approle
vault auth enable approle
vault write auth/approle/role/cert-role token_policies="cert-policy" secret_id_ttl=24h token_ttl=5m token_max_ttl=4h

# Get the role and secretid
vault read -format=json auth/approle/role/cert-role/role-id > /tmp/certs/role.json
vault write -format=json -f auth/approle/role/cert-role/secret-id > /tmp/certs/secretid.json
export ROLE_ID="$(cat /tmp/certs/role.json | jq -r .data.role_id )" && echo $ROLE_ID | tee roleid > /tmp/certs/roleid
export SECRET_ID="$(cat /tmp/certs/secretid.json | jq -r .data.secret_id )" && echo $SECRET_ID |tee secretid > /tmp/certs/secretid
```

### Set Up Vault Agent

Configure Vault Agent to handle certificate renewal and NGINX updates. In this guide, Vault Agent runs in the terminal; please note that converting this setup to run as a service is beyond the scope of this example.

```bash
# Copy Vault Agent configuration files
cp vault-agent/* /tmp/certs/

# Export role and secret IDs
export ROLE_ID="$(cat /tmp/certs/role.json | jq -r .data.role_id )" && echo $ROLE_ID | tee roleid > /tmp/certs/roleid
export SECRET_ID="$(cat /tmp/certs/secretid.json | jq -r .data.secret_id )" && echo $SECRET_ID | tee secretid > /tmp/certs/secretid

# Start Vault Agent
sudo vault agent -config=/tmp/certs/vault-agent.hcl
```

This setup ensures that certificates are automatically renewed every 10 minutes, followed by a restart of NGINX to apply the new certificates.

This tutorial covers the complete process of integrating Vault PKI with NGINX, resulting in a secure and efficiently managed SSL/TLS certificate infrastructure. By following these steps, you can automate certificate renewal and enhance the security of your NGINX web server.

For additional details and examples, refer to the [original tutorial](https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine).