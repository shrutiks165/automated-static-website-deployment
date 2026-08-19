# Automated Static Website Deployment

S3 (storage) → CloudFront (CDN) → GitHub Actions (CI/CD) → Terraform (infrastructure as code)

```
static-site-deploy/
├── terraform/
│   ├── provider.tf      # AWS + backend config
│   ├── variables.tf     # bucket name, etc.
│   ├── main.tf          # S3 bucket + CloudFront + OAC + policy
│   └── outputs.tf       # values other steps need (bucket name, distribution ID)
├── website/
│   └── index.html       # your actual site — replace/add files freely
└── .github/workflows/
    └── deploy.yml        # runs on every push to main
```

## One-time manual setup (do this BEFORE your first `git push`)

Terraform needs a place to store its "state" (a JSON file tracking what it
built), and GitHub Actions needs permission to touch your AWS account.
These two things can't be created by Terraform itself (chicken-and-egg), so
you set them up once, by hand.

### 1. Create the Terraform state bucket + lock table

```bash
aws s3api create-bucket \
  --bucket shrutiks165-tfstate-bucket \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```
The DynamoDB table is a "lock" — it stops two Terraform runs from editing
infrastructure at the same time and corrupting the state file.

> Update `bucket` in `terraform/provider.tf` if you pick a different name
> (S3 bucket names must be globally unique across ALL AWS accounts).

### 2. Let GitHub Actions authenticate to AWS (OIDC — no stored keys)

Create an IAM OIDC identity provider so AWS trusts tokens issued by GitHub:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Create a trust policy file `trust-policy.json` (replace `ACCOUNT_ID`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:shrutiks165/YOUR_REPO_NAME:ref:refs/heads/main" }
    }
  }]
}
```

Create the role and attach permissions (scope this down later — broad for now to keep setup simple):

```bash
aws iam create-role \
  --role-name github-actions-deploy-role \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name github-actions-deploy-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name github-actions-deploy-role \
  --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess

aws iam attach-role-policy \
  --role-name github-actions-deploy-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
```

Copy the role's ARN from the output, then in your GitHub repo:
**Settings → Secrets and variables → Actions → New repository secret**
- Name: `AWS_ROLE_ARN`
- Value: `arn:aws:iam::ACCOUNT_ID:role/github-actions-deploy-role`

### 3. Push it

```bash
git init
git add .
git commit -m "Automated static website deployment"
git branch -M main
git remote add origin https://github.com/shrutiks165/YOUR_REPO_NAME.git
git push -u origin main
```

Watch the run under the **Actions** tab. On success, the CloudFront URL is
in the Terraform output — check the workflow log, or run locally:
```bash
cd terraform && terraform output cloudfront_domain_name
```

## Why it's "secure" (for your resume bullet)

- S3 bucket has **Block Public Access** fully enabled — the bucket itself
  is unreachable from the internet.
- CloudFront reads from S3 using an **Origin Access Control (OAC)** —
  a signed-request mechanism so only your specific CloudFront distribution
  (not even other CloudFront distributions) can fetch objects.
- All viewer traffic is forced to HTTPS (`redirect-to-https`).

## Tearing it down (avoid ongoing charges)

```bash
cd terraform
terraform destroy
```
CloudFront distributions take ~15 min to delete since edge locations
worldwide have to disable it first — that's normal.
