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
    APP_HOST_PORT = '8081'
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

    // stage('Preflight: free 8081') {
    //   steps {
    //     bat """
    //       powershell -Command " $p=%APP_HOST_PORT%; $c=Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue; if ($c) { Write-Host \\"Port $p busy by PID $($c.OwningProcess). Killing...\\"; Stop-Process -Id $($c.OwningProcess) -Force } else { Write-Host \\"Port $p is free.\\" } "
    //       for /f %%i in ('docker ps -q --filter "publish=%APP_HOST_PORT%"') do docker rm -f %%i
    //     """
    //   }
    // }

    stage('Run App Container') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          set CONTAINER=demo-app-%BUILD_NUMBER%
          set PORT=%APP_HOST_PORT%

          rem Clean slate
          docker rm -f %CONTAINER% 1>nul 2>nul || ver > nul

          rem Start container with host 8081 -> container 8080
          docker run -d --name %CONTAINER% -p %PORT%:8080 %IMAGE_REF%

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

    stage('ZAP Baseline Scan') {
      steps {
        bat '''
          set "PATH=%PATH%;C:\\Program Files\\Docker\\Docker\\resources\\bin"

          docker pull %ZAP_IMAGE%

          del /q %REPORTS%\\zap-baseline.html 2>nul
          del /q %REPORTS%\\zap-baseline.json 2>nul

          rem Run ZAP baseline
          docker run --rm -t ^
            -v "%cd%\\%REPORTS%:/zap/wrk" ^
            %ZAP_IMAGE% zap-baseline.py ^
              -t http://host.docker.internal:%APP_HOST_PORT% ^
              -r zap-baseline.html ^
              -J zap-baseline.json ^
              -m 5 ^
              -z "-config api.disablekey=true"

          rem Capture exit code from the previous command
          set ZAP_EXIT=%ERRORLEVEL%
          echo %ZAP_EXIT% > %REPORTS%\\zap-exit.txt
          echo ZAP exit code: %ZAP_EXIT%

          rem Gate: fail only on internal error (>=3). For 0/1/2, succeed so we can upload reports.
          if %ZAP_EXIT% GEQ 3 (
            exit /b %ZAP_EXIT%
          ) else (
            exit /b 0
          )
        '''
        archiveArtifacts artifacts: 'reports/zap-baseline.*', fingerprint: true
        archiveArtifacts artifacts: 'reports/zap-exit.txt', fingerprint: true
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
          docker rm -f demo-app-%BUILD_NUMBER% 1>nul 2>nul || ver > nul
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
