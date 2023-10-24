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
  contents = "/tmp/certs/template.tmpl"
  destination = "/etc/nginx/keys/nginx_certificate_chain.pem"
}