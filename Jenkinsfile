// Terraform pipeline for AWS account 629807611256 (dev).
//
//   ACTION=plan     fmt -> init -> validate -> tflint -> checkov -> plan (plan archived on the build)
//   ACTION=apply    plan -> manual approval -> apply that exact plan
//   ACTION=destroy  destroy plan -> manual approval -> apply it
//
// Agent (label 'terraform') needs: terraform >= 1.10, aws CLI v2, git. Optional: tflint, checkov.
// Plugins: Pipeline, Git, Credentials Binding, AWS Credentials (CloudBees).

// Script-level (binding) variables so every stage and helper sees them.
planHasChanges = false

// Bind the Jenkins AWS credential if one is configured; otherwise the agent's
// instance profile is used. ci/aws-auth.sh then assumes TF_ROLE_ARN.
def withAws(Closure body) {
  if (env.AWS_CREDENTIALS_ID?.trim()) {
    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                      credentialsId: env.AWS_CREDENTIALS_ID,
                      accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                      secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
      body()
    }
  } else {
    body()
  }
}

// Shared by Plan and Apply. Runs inside the stack directory.
TF_INIT = '''
  terraform init \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="key=${STACK}/terraform.tfstate" \
    -backend-config="region=${AWS_REGION}"
'''

pipeline {
  agent none

  parameters {
    choice(name: 'STACK', choices: ['projects/golden-hour-code/dev'], description: 'Stack directory to build')
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'plan only, or plan + approve + apply')
  }

  environment {
    AWS_ACCOUNT_ID     = '629807611256'
    AWS_REGION         = 'us-east-1'
    AWS_DEFAULT_REGION = 'us-east-1'
    TF_STATE_BUCKET    = 'tfstate-629807611256-us-east-1'
    TF_ROLE_ARN        = 'arn:aws:iam::629807611256:role/jenkins-terraform-dev'
    AWS_CREDENTIALS_ID = 'aws-jenkins'          // Jenkins credential ID; set to '' to use the agent's instance profile
    TF_APPROVERS       = 'devops-approvers'     // Jenkins users/groups allowed to approve; '' = anyone with Build
    TF_IN_AUTOMATION   = 'true'
    TF_INPUT           = 'false'
  }

  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 2, unit: 'HOURS')
  }

  stages {
    stage('Plan') {
      agent { label 'terraform' }
      steps {
        script {
          if (params.ACTION != 'plan' && env.BRANCH_NAME && env.BRANCH_NAME != 'main') {
            error "ACTION=${params.ACTION} is only allowed from main (this is ${env.BRANCH_NAME})"
          }
          currentBuild.description = "${params.ACTION} ${params.STACK}"
        }
        withAws {
          dir(params.STACK) {
            sh '. "$WORKSPACE/ci/aws-auth.sh"\n' + TF_INIT
            sh '''
              terraform fmt -check -recursive -diff
              terraform validate -no-color

              if command -v tflint >/dev/null; then
                tflint --init --config="$WORKSPACE/.tflint.hcl"
                tflint --config="$WORKSPACE/.tflint.hcl" --format=compact
              else
                echo "tflint not installed on agent, skipping"
              fi

              if command -v checkov >/dev/null; then
                checkov -d . --framework terraform --download-external-modules true --quiet --soft-fail
              else
                echo "checkov not installed on agent, skipping"
              fi
            '''
            sh '''
              . "$WORKSPACE/ci/aws-auth.sh"

              # Load every *.tfvars in the stack (golden-hour-code.tfvars is not auto-loaded by Terraform).
              VAR_FILES=""
              for f in *.tfvars; do if [ -e "$f" ]; then VAR_FILES="$VAR_FILES -var-file=$f"; fi; done
              DESTROY=""
              if [ "$ACTION" = "destroy" ]; then DESTROY="-destroy"; fi

              set +e
              terraform plan -no-color -detailed-exitcode -out=tfplan $VAR_FILES $DESTROY
              rc=$?
              set -e
              # 0 = no changes, 1 = error, 2 = changes
              if [ "$rc" -eq 1 ]; then exit 1; fi
              echo "$rc" > plan.exitcode
              terraform show -no-color tfplan > plan.txt
            '''
            script {
              planHasChanges = readFile('plan.exitcode').trim() == '2'
              echo(planHasChanges ? 'Plan has changes.' : 'No changes. Infrastructure matches the configuration.')
            }
            archiveArtifacts artifacts: 'plan.txt', fingerprint: true
            stash name: 'tfplan', includes: 'tfplan,.terraform.lock.hcl'
          }
        }
      }
      post {
        always { deleteDir() }  // tfplan can contain secrets; don't leave it on the agent
      }
    }

    stage('Approve') {
      when {
        beforeAgent true
        expression { params.ACTION != 'plan' && planHasChanges }
      }
      // No agent: waiting for a human doesn't hold an executor.
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: "${params.ACTION.toUpperCase()} ${params.STACK} in account ${env.AWS_ACCOUNT_ID}? Review plan.txt under Build Artifacts.",
                ok: params.ACTION == 'destroy' ? 'Destroy' : 'Apply',
                submitter: env.TF_APPROVERS
        }
      }
    }

    stage('Apply') {
      when {
        beforeAgent true
        expression { params.ACTION != 'plan' && planHasChanges }
      }
      agent { label 'terraform' }
      steps {
        withAws {
          dir(params.STACK) {
            unstash 'tfplan'
            // Same lock file as the plan, so the providers match. Terraform rejects the plan if state changed since.
            sh '. "$WORKSPACE/ci/aws-auth.sh"\n' + TF_INIT + '''
              terraform apply -no-color tfplan
              terraform output -no-color
            '''
          }
        }
      }
      post {
        always { deleteDir() }
      }
    }
  }
}
