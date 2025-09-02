pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }

  environment {
    AWS_REGION = 'eu-central-1'
    IMAGE_NAME = "nice-demo-app"
    IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
    IMAGE_REF  = "${env.IMAGE_NAME}:${env.IMAGE_TAG}"
    TF_DIR     = 'terraform'
    TF_INPUT   = 'false'
    REPORTS    = 'reports'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        bat 'cd & dir'
      }
    }

    stage('Terraform Init') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\;C:\\Program Files\\Terraform\\"
            cd %TF_DIR%
            set AWS_DEFAULT_REGION=%AWS_REGION%
            terraform -version
            terraform init -input=%TF_INPUT% -no-color
          """
        }
      }
    }

    stage('Terraform Plan') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\;C:\\Program Files\\Terraform\\"
            cd %TF_DIR%
            set AWS_DEFAULT_REGION=%AWS_REGION%
            terraform plan -input=%TF_INPUT% -no-color -out tfplan
            terraform show -no-color tfplan > tfplan.txt
          """
        }
        archiveArtifacts artifacts: "${env.TF_DIR}/tfplan.txt", fingerprint: true
      }
    }

    stage('Terraform Apply (manual gate)') {
      // if you want only on main, uncomment:
      // when { branch 'main' }
      steps {
        input message: 'Apply Terraform changes to AWS?'
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\;C:\\Program Files\\Terraform\\"
            cd %TF_DIR%
            set AWS_DEFAULT_REGION=%AWS_REGION%
            if exist tfplan (
              terraform apply -input=%TF_INPUT% -no-color -auto-approve tfplan
            ) else (
              terraform apply -input=%TF_INPUT% -no-color -auto-approve
            )
            terraform output
          """
        }
      }
    }

    stage('Export Terraform outputs') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Terraform\\"
          if not exist %REPORTS% mkdir %REPORTS%
          cd %TF_DIR%
          terraform output > outputs.txt
          for /f %%i in ('terraform output -raw bucket_name') do @echo %%i > ..\\bucket_name.txt
          for /f %%i in ('terraform output -raw jenkins_reports_policy_arn') do @echo %%i > ..\\policy_arn.txt
        """
        archiveArtifacts artifacts: 'bucket_name.txt, policy_arn.txt, terraform/outputs.txt', fingerprint: true
      }
    }

    stage('IaC Security Scan (Trivy config)') {
      steps {
        bat """
          rem Ensure Trivy is on PATH for LocalSystem:
          set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Aquasec\\Trivy\\"
          
          if not exist %REPORTS% mkdir %REPORTS%
          trivy --version
          
          rem Run Trivy config scan against the terraform/ directory.
          rem --exit-code 0 so the build doesn't fail on findings (you can tighten later).
          trivy config terraform --severity HIGH,CRITICAL --format json --output reports\\iac-trivy.json --exit-code 0
        """
        archiveArtifacts artifacts: 'reports/iac-trivy.json', fingerprint: true
      }
    }

    stage('Upload IaC report to S3') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            rem Ensure AWS CLI is visible:
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            
            rem Read the bucket name created by Terraform:
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            
            rem Upload the IaC report with SSE:
            aws s3 cp reports\\iac-trivy.json s3://%BUCKET%/reports/%BUILD_NUMBER%/iac/iac-trivy.json --sse AES256
            
            rem Optional: list the uploaded prefix for confirmation
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/iac/
          """
        }
      }
    }

    stage('Build Docker image') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          if not exist %REPORTS% mkdir %REPORTS%
          docker version
          docker build -t %IMAGE_REF% .
        """
      }
    }

    stage('Trivy Image Scan') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Aquasec\\Trivy\\"
          if not exist %REPORTS% mkdir %REPORTS%
          trivy --version
          trivy image --ignore-unfixed --severity HIGH,CRITICAL --format json -o %REPORTS%\\image-trivy.json %IMAGE_REF% --exit-code 0
        """
        archiveArtifacts artifacts: 'reports/image-trivy.json', fingerprint: true
      }
    }

    stage('Upload Trivy Image Report to S3') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\image-trivy.json s3://%BUCKET%/reports/%BUILD_NUMBER%/image/image-trivy.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/image/
          """
        }
      }
    }

    stage('Run App Container') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          docker rm -f demo-app 1>nul 2>nul || ver > nul
          docker run -d --name demo-app -p 8080:8080 %IMAGE_REF%
          rem Health check (PowerShell Invoke-WebRequest avoids curl dependency)
          powershell -Command "try { iwr http://localhost:8080/ -UseBasicParsing | Out-Null } catch { exit 1 }"
        """
      }
    }

    stage('ZAP Baseline Scan') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          del /q %REPORTS%\\zap-baseline.html 2>nul
          del /q %REPORTS%\\zap-baseline.json 2>nul

          docker run --rm -t ^
            -v "%cd%\\%REPORTS%:/zap/wrk" ^
            owasp/zap2docker-stable zap-baseline.py ^
              -t http://host.docker.internal:8080 ^
              -r zap-baseline.html ^
              -J zap-baseline.json ^
              -m 5 ^
              -z "-config api.disablekey=true"
        """
        archiveArtifacts artifacts: 'reports/zap-baseline.*', fingerprint: true
      }
    }

    stage('Upload ZAP Reports to S3') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\zap-baseline.html s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/zap-baseline.html --sse AES256
            aws s3 cp %REPORTS%\\zap-baseline.json s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/zap-baseline.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/
          """
        }
      }
    }

    stage('Cleanup App Container') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          docker rm -f demo-app 1>nul 2>nul || ver > nul
        """
      }
    }



  } // <-- close stages

  post {
    success { echo 'Terraform from Jenkins: OK.' }
    always  { echo 'Done.' }
  }
} // <-- end pipeline
