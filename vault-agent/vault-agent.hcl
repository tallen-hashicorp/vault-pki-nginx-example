pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "approle"

    config = {
      role_id_file_path = "/tmp/certs/roleid"
      secret_id_file_path = "/tmp/certs/secretid"
    }
  }

  sink {
    type = "file"
    config = {
      path = "/tmp/certs/token"
    }
  }
}

# TLS SERVER CERTIFICATE
template {
  contents = "{{ with secret \"pki_int/issue/example-dot-com\" \"common_name=test.example.com\" \"ttl=10m\" }}{{ .Data.certificate }}{{ range $idx, $cert := .Data.ca_chain }}\n{{ $cert }}{{ end }}{{ end }}"
  destination = "/etc/nginx/keys/nginx_certificate_chain.pem"
}

# TLS PRIVATE KEY
template {
  contents = "{{ with secret \"pki_int/issue/example-dot-com\" \"common_name=test.example.com\" \"ttl=10m\" }}{{ .Data.private_key }}{{ end }}"
  destination = "/etc/nginx/keys/nginx_private_key.pem"
  command = "systemctl restart nginx"
}