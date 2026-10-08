# terraform-shared

Live infrastructure stacks built from [aws-terraform-modules](https://github.com/tilak925849-collab/aws-terraform-modules).

```
projects/<project>/<env>/   one stack = one state file (s3://<bucket>/projects/<project>/<env>/terraform.tfstate)
bootstrap/                  one-time: state bucket + GitHub OIDC roles
.github/workflows/terraform.yml
```

## Pipeline

| Trigger | What runs |
|---|---|
| Pull request to `main` | For every changed stack: `fmt` → `init` → `validate` → `tflint` → `checkov` → `plan`. The plan is posted as a PR comment. |
| Merge to `main` | Plans again, then **applies that saved plan** after the GitHub environment's approval gate (`dev`, `prod`, …). |
| Manual (*Run workflow*) | `plan`, `apply` or `destroy` for one stack. Apply and destroy only run from `main`. |

- Only stacks with changed files run. A change to the workflow or `.tflint.hcl` re-plans every stack.
- The environment name is the last path segment: `projects/golden-hour-code/dev` → environment `dev`.
- Applies to the same stack never overlap (they run one at a time per stack). State is locked with S3 native locking (`use_lockfile`).
- AWS access is through OIDC, with no stored keys. Plans use a read-only role. Applies use a role that only jobs in an approved environment can assume.

## One-time setup

1. **Bootstrap AWS** (admin credentials, run locally):
   ```bash
   cd bootstrap
   terraform init
   terraform apply -var github_repo=<owner>/terraform-shared -var state_bucket_name=<unique-bucket-name>
   ```
2. **Repository variables** (*Settings → Secrets and variables → Actions → Variables*):
   `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN` (from the bootstrap outputs).
3. **Environments** (*Settings → Environments*): create `dev` (and later `stage`, `prod`). In each one:
   - add variable `AWS_APPLY_ROLE_ARN`
   - add *Required reviewers* (at least for prod)
   - set *Deployment branches* to `main`
4. **Branch protection** on `main`: require PRs and require the `plan` checks to pass.
5. Fill in `vpc_id` / `subnet_ids` in `projects/golden-hour-code/dev/golden-hour-code.tfvars`, then open a PR.
6. Commit the `.terraform.lock.hcl` files, so CI uses the same provider versions you do:
   `terraform init -backend=false && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`

## Jenkins (account 629807611256, dev)

The [Jenkinsfile](Jenkinsfile) is a parameterised job: pick `STACK` and `ACTION` (`plan` / `apply` / `destroy`).
It plans, archives `plan.txt`, waits for approval (without holding an executor), then applies the stashed plan.
Every AWS step first assumes `jenkins-terraform-dev` and fails if the account isn't `629807611256`. The provider's `allowed_account_ids` enforces the same rule.

Setup:
1. Bootstrap the account (admin creds for 629807611256):
   ```bash
   cd bootstrap && terraform init
   terraform apply \
     -var github_repo=<owner>/terraform-shared \
     -var state_bucket_name=tfstate-629807611256-us-east-1 \
     -var 'jenkins_principal_arns=["arn:aws:iam::<jenkins-account>:role/<jenkins-agent-role>"]'
   ```
2. Jenkins agent with label `terraform`: terraform >= 1.10, aws CLI v2, git (tflint and checkov are optional).
3. AWS credentials:
   - Either create a Jenkins *AWS Credentials* entry with ID `aws-jenkins` for the principal above,
   - or set `AWS_CREDENTIALS_ID = ''` in the Jenkinsfile to use the agent's instance profile.
4. Create a Pipeline (or Multibranch) job from this repo's `Jenkinsfile`. Approval is limited to `devops-approvers` (`TF_APPROVERS`). In a multibranch job, apply and destroy only run on `main`.
5. To add a stack, add its path to the `STACK` choices.

## Adding a stack

Copy `projects/golden-hour-code/dev` to `projects/<project>/<env>`, then edit its `.tfvars`. For a new env, create the GitHub environment and add it to `environments` in `bootstrap`.

## Removing a stack

Run the workflow manually with `action=destroy` first. Then delete the directory in a PR. The pipeline never destroys anything just because a directory was deleted.

## Module versions

Stacks pin the modules repo to a commit SHA. Tag releases in the modules repo (`v1.0.0`, …), then reference `?ref=v1.0.0` so upgrades are deliberate and show up in a plan.
