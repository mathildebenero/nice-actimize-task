DevSecOps Student Assignment
📌 Overview

This project demonstrates a full DevSecOps pipeline using Jenkins, Terraform, Docker, Trivy, OWASP ZAP, and AWS S3.
The goal is to provision infrastructure, deploy a deliberately vulnerable app, scan it for issues, and improve security step by step.

⚙️ Steps Implemented
1. Infrastructure Provisioning (Terraform + Jenkins)

Terraform code provisions:

S3 bucket for storing security scan reports.

IAM role/policy for Jenkins to upload reports to S3.

Jenkins pipeline runs:

terraform init

terraform plan

terraform apply (manual approval gate)

Outputs (bucket name, policy ARN) are exported for later stages.

2. IaC Security Scanning (Trivy)

Runs trivy config against Terraform code.

Generates JSON report (reports/iac-trivy.json).

Uploads the report to the S3 bucket with SSE AES256 encryption.

3. Application Build & Containerization

Vulnerable Flask app (app_insecure.py) intentionally exposed Reflected XSS.

Dockerfile.insecure containerized the app.

Later hardened with:

app_secure.py → escaping user input + strong security headers.

Dockerfile.secure → updated base (python:3.12-slim-bookworm), OS patching, pip upgrades, non-root user.

Trivy image scans performed (image-trivy-insecure.json vs image-trivy-secure.json).

4. Dynamic Security Scanning (OWASP ZAP)

Jenkins runs the insecure app in a container.

NGINX edge proxy (with nginx-secure.conf) adds:

Security headers (CSP, XFO, nosniff, referrer, permissions).

Rate limiting (~60 req/min per client).

Short timeouts, banner masking, anti-clickjacking.

ZAP baseline scan runs via container against the app endpoint.

Reports (zap-baseline-insecure.html/json) uploaded to S3.

5. Report Storage

All reports (IaC, image, dynamic scan) uploaded to S3 securely:

Encrypted in transit (HTTPS/TLS via AWS CLI).

Encrypted at rest (--sse AES256).

Reports archived as Jenkins artifacts too.

🚀 How to Run Locally
Build and run the secure app
docker build -t demo-app-secure -f Dockerfile.secure .
docker run -d --name demo-app-secure -p 8082:8080 demo-app-secure

Run NGINX secure edge
docker run -d --name edge-secure -p 8092:80 \
  -v "%cd%/nginx/nginx-secure.conf:/etc/nginx/nginx.conf:ro" \
  nginx:stable-alpine

Access in browser

Direct app: http://localhost:8082/

Via edge (with headers & rate limiting): http://localhost:8092/

Health check: http://localhost:8092/health

Test security headers
curl -I http://localhost:8092/

Test rate limiting (~60 req/min)
for /L %i in (1,1,80) do curl -s http://localhost:8092/health

📂 Project Structure
├── terraform/             # Infrastructure as Code (S3 bucket, IAM policy)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── providers.tf
├── app/
│   ├── app_insecure.py    # Vulnerable app (XSS)
│   ├── app_secure.py      # Hardened app (XSS fixed, headers added)
│   └── requirements.txt
├── Dockerfile.insecure    # Old vulnerable build
├── Dockerfile.secure      # Hardened build (Python 3.12, non-root, patched deps)
├── nginx/nginx-secure.conf# NGINX edge proxy config
├── Jenkinsfile            # CI/CD pipeline with all stages
└── reports/               # Trivy & ZAP outputs (archived & uploaded to S3)

🔐 Security Features

IaC scanning with Trivy.

Container image scanning with Trivy.

Dynamic scanning with OWASP ZAP.

Secure report uploads to AWS S3 with encryption.

NGINX edge adds:

Security headers (CSP, anti-clickjacking, nosniff, etc.)

Rate limiting (DoS mitigation)

Short timeouts

Server banner masking

App hardened with escaping + headers.

Containers run as non-root users.

🔮 Future Improvements

Run Jenkins under a dedicated service account (not Local System).

Enable HTTPS at the edge with valid certs + HSTS.

Add active OWASP ZAP scan (not just baseline).

Deploy in AWS IL region for latency.

Automate dependency upgrades (base image & Python libs).

Use KMS-managed keys for S3 encryption.

Add a WAF in front of NGINX (AWS WAF/ModSecurity).

Centralize logging & monitoring (CloudWatch/ELK).

Add policy gates in Jenkins (fail build on CRITICAL issues).

✅ This README matches the PDF’s requirements, explains the whole pipeline, and makes you look structured and professional.