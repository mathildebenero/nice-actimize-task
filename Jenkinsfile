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
    APP_HOST_PORT_INSECURE = '8081'
    APP_HOST_PORT_SECURE   = '8082'
    ZAP_IMAGE = 'ghcr.io/zaproxy/zaproxy:stable'
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

    // insecure app

    stage('Build Docker image (insecure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          if not exist %REPORTS% mkdir %REPORTS%
          docker version
          docker build -t %IMAGE_NAME%:insecure-%IMAGE_TAG% -f Dockerfile.insecure .
        """
      }
    }

    stage('Trivy Image Scan (insecure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Aquasec\\Trivy\\"
          if not exist %REPORTS% mkdir %REPORTS%
          trivy --version
          trivy image --ignore-unfixed --severity HIGH,CRITICAL --format json -o %REPORTS%\\image-trivy-insecure.json %IMAGE_NAME%:insecure-%IMAGE_TAG% --exit-code 0
        """
        archiveArtifacts artifacts: 'reports/image-trivy-insecure.json', fingerprint: true
      }
    }

    stage('Upload Trivy Image Report to S3 (insecure)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\image-trivy-insecure.json s3://%BUCKET%/reports/%BUILD_NUMBER%/image/image-trivy-insecure.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/image/insecure/
          """
        }
      }
    }

    stage('Run App Container (insecure)') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          set CONTAINER=demo-app-insecure-%BUILD_NUMBER%
          set PORT=%APP_HOST_PORT_INSECURE%

          rem Clean slate
          docker rm -f %CONTAINER% 1>nul 2>nul || ver > nul

          rem Start container with host 8081 -> container 8080
          docker run -d --name %CONTAINER% -p %PORT%:8080 %IMAGE_NAME%:insecure-%IMAGE_TAG%

          rem Persist port for later stages
          echo %PORT%> app_port.txt

          rem === Quick health wait: poll docker health (max ~20s) ===
          powershell -NoProfile -Command ^
            "$deadline=(Get-Date).AddSeconds(20);" ^
            "while((Get-Date) -lt $deadline){" ^
            "  $s = docker inspect -f '{{.State.Health.Status}}' $env:CONTAINER 2>$null;" ^
            "  if($s -eq 'healthy'){ exit 0 }" ^
            "  Start-Sleep -Milliseconds 750" ^
            "};" ^
            "Write-Host 'Container did not become healthy in time.'; docker logs --tail 100 $env:CONTAINER; exit 1"

          echo App healthy on http://localhost:%PORT%/
        '''
      }
    }

    stage('ZAP Baseline Scan (insecure)') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          docker pull %ZAP_IMAGE%

          del /q %REPORTS%\\zap-baseline-insecure.html 2>nul
          del /q %REPORTS%\\zap-baseline-insecure.json 2>nul

          rem Run ZAP baseline
          docker run --rm -t ^
            -v "%cd%\\%REPORTS%:/zap/wrk" ^
            %ZAP_IMAGE% zap-baseline.py ^
              -t http://host.docker.internal:%APP_HOST_PORT_INSECURE% ^
              -r zap-baseline-insecure.html ^
              -J zap-baseline-insecure.json ^
              -m 5 ^
              -z "-config api.disablekey=true"

          rem Capture exit code from the previous command
          set ZAP_EXIT=%ERRORLEVEL%
          echo %ZAP_EXIT% > %REPORTS%\\zap-exit-insecure.txt
          echo ZAP exit code: %ZAP_EXIT%

          rem Gate: fail only on internal error (>=3). For 0/1/2, succeed so we can upload reports.
          if %ZAP_EXIT% GEQ 3 (
            exit /b %ZAP_EXIT%
          ) else (
            exit /b 0
          )
        '''
        archiveArtifacts artifacts: 'reports/zap-baseline-insecure.*', fingerprint: true
        archiveArtifacts artifacts: 'reports/zap-exit-insecure.txt', fingerprint: true
      }
    }


    stage('Upload ZAP Reports to S3 (insecure)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\zap-baseline-insecure.html s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/insecure/zap-baseline-insecure.html --sse AES256
            aws s3 cp %REPORTS%\\zap-baseline-insecure.json s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/insecure/zap-baseline-insecure.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/insecure/
          """
        }
      }
    }

    stage('Cleanup App Container (insecure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          docker rm -f demo-app-insecure-%BUILD_NUMBER% 1>nul 2>nul || ver > nul
        """
      }
    }


    // secure app

    
    stage('Build Docker image (secure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          if not exist %REPORTS% mkdir %REPORTS%
          docker version
          docker build -t %IMAGE_NAME%:secure-%IMAGE_TAG% -f Dockerfile.secure .
        """
      }
    }

    stage('Trivy Image Scan (secure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Aquasec\\Trivy\\"
          if not exist %REPORTS% mkdir %REPORTS%
          trivy --version
          trivy image --ignore-unfixed --severity HIGH,CRITICAL --format json -o %REPORTS%\\image-trivy-secure.json %IMAGE_NAME%:secure-%IMAGE_TAG% --exit-code 0
        """
        archiveArtifacts artifacts: 'reports/image-trivy-secure.json', fingerprint: true
      }
    }

    stage('Upload Trivy Image Report to S3 (secure)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\image-trivy-secure.json s3://%BUCKET%/reports/%BUILD_NUMBER%/image/image-trivy-secure.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/image/secure/
          """
        }
      }
    }

    stage('Run App Container (secure)') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          set CONTAINER=demo-app-secure-%BUILD_NUMBER%
          set PORT=%APP_HOST_PORT_secure%

          rem Clean slate
          docker rm -f %CONTAINER% 1>nul 2>nul || ver > nul

          rem Start container with host 8081 -> container 8080
          docker run -d --name %CONTAINER% -p %PORT%:8080 %IMAGE_NAME%:secure-%IMAGE_TAG%

          rem Persist port for later stages
          echo %PORT%> app_port.txt

          rem === Quick health wait: poll docker health (max ~20s) ===
          powershell -NoProfile -Command ^
            "$deadline=(Get-Date).AddSeconds(20);" ^
            "while((Get-Date) -lt $deadline){" ^
            "  $s = docker inspect -f '{{.State.Health.Status}}' $env:CONTAINER 2>$null;" ^
            "  if($s -eq 'healthy'){ exit 0 }" ^
            "  Start-Sleep -Milliseconds 750" ^
            "};" ^
            "Write-Host 'Container did not become healthy in time.'; docker logs --tail 100 $env:CONTAINER; exit 1"

          echo App healthy on http://localhost:%PORT%/
        '''
      }
    }

    stage('ZAP Baseline Scan (secure)') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          docker pull %ZAP_IMAGE%

          del /q %REPORTS%\\zap-baseline-secure.html 2>nul
          del /q %REPORTS%\\zap-baseline-secure.json 2>nul

          rem Run ZAP baseline
          docker run --rm -t ^
            -v "%cd%\\%REPORTS%:/zap/wrk" ^
            %ZAP_IMAGE% zap-baseline.py ^
              -t http://host.docker.internal:%APP_HOST_PORT_secure% ^
              -r zap-baseline-secure.html ^
              -J zap-baseline-secure.json ^
              -m 5 ^
              -z "-config api.disablekey=true"

          rem Capture exit code from the previous command
          set ZAP_EXIT=%ERRORLEVEL%
          echo %ZAP_EXIT% > %REPORTS%\\zap-exit-secure.txt
          echo ZAP exit code: %ZAP_EXIT%

          rem Gate: fail only on internal error (>=3). For 0/1/2, succeed so we can upload reports.
          if %ZAP_EXIT% GEQ 3 (
            exit /b %ZAP_EXIT%
          ) else (
            exit /b 0
          )
        '''
        archiveArtifacts artifacts: 'reports/zap-baseline-secure.*', fingerprint: true
        archiveArtifacts artifacts: 'reports/zap-exit-secure.txt', fingerprint: true
      }
    }


    stage('Upload ZAP Reports to S3 (secure)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-reports-creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          bat """
            set "PATH=%PATH%;C:\\Windows\\System32;C:\\Windows;C:\\Program Files\\Amazon\\AWSCLIV2\\"
            set AWS_DEFAULT_REGION=%AWS_REGION%
            for /f %%i in (bucket_name.txt) do @set BUCKET=%%i
            if "%BUCKET%"=="" ( echo ERROR: bucket_name.txt missing or empty & exit /b 1 )
            aws s3 cp %REPORTS%\\zap-baseline-secure.html s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/secure/zap-baseline-secure.html --sse AES256
            aws s3 cp %REPORTS%\\zap-baseline-secure.json s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/secure/zap-baseline-secure.json --sse AES256
            aws s3 ls s3://%BUCKET%/reports/%BUILD_NUMBER%/zap/secure/
          """
        }
      }
    }

    stage('Cleanup App Container (secure)') {
      steps {
        bat """
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
          docker rm -f demo-app-secure-%BUILD_NUMBER% 1>nul 2>nul || ver > nul
        """
      }
    }


  } // <-- close stages

  post {
    success { echo 'Terraform from Jenkins: OK.' }
    always  {
      echo 'Done.'
      // extra safety: remove container even if earlier stages failed
      bat """
        set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"
        docker rm -f demo-app-%BUILD_NUMBER% 1>nul 2>nul || ver > nul
      """
    }
  }

} // <-- end pipeline
