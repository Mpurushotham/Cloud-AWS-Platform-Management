plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format = "default"
  call_module_type = "local"
}

# Enforce variable descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Enforce output descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Require naming conventions
rule "terraform_naming_convention" {
  enabled = true

  resource {
    format = "snake_case"
  }

  data {
    format = "snake_case"
  }

  module {
    format = "snake_case"
  }

  variable {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }
}

# Disallow deprecated resources
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Require required_providers
rule "terraform_required_providers" {
  enabled = true
}

# Require terraform version constraint
rule "terraform_required_version" {
  enabled = true
}

# Disallow unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Warn on deprecated attributes
rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Environment", "Project", "ManagedBy", "Owner"]
}
