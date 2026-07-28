# GitHub Actions OIDC identity provider.
#
# This replaces long-lived IAM access keys in CI entirely: GitHub mints a short
# lived JWT per job, AWS verifies it against this provider, and STS returns
# credentials valid for the job only. Nothing durable is stored in GitHub.
#
# Note on the original terraform/bootstrap/oidc.tf: it tried to look the
# provider up with a data source and conditionally create it. A data source that
# finds nothing is a hard error, not an empty result, so that configuration
# could never apply in an account without the provider — which is precisely the
# case it was written to handle. Here creation is an explicit boolean instead.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Since mid-2023 AWS validates this endpoint against its own trust store and
  # ignores the thumbprint, but the API still requires the field to be present.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}
