# Sourced by the Jenkinsfile: `. ci/aws-auth.sh`
# Assumes TF_ROLE_ARN (if set) and checks the credentials belong to AWS_ACCOUNT_ID.
# Base credentials come from the Jenkins AWS credential binding or the agent's instance profile.

set +x  # never trace credentials into the build log

if [ -n "${TF_ROLE_ARN:-}" ]; then
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<EOF
$(aws sts assume-role \
    --role-arn "$TF_ROLE_ARN" \
    --role-session-name "jenkins-${BUILD_NUMBER:-local}" \
    --duration-seconds 3600 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)
EOF
  if [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "ERROR: could not assume $TF_ROLE_ARN" >&2
    exit 1
  fi
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  unset AWS_PROFILE
fi

actual_account="$(aws sts get-caller-identity --query Account --output text)"
if [ "$actual_account" != "$AWS_ACCOUNT_ID" ]; then
  echo "ERROR: credentials are for account $actual_account, expected $AWS_ACCOUNT_ID" >&2
  exit 1
fi
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
