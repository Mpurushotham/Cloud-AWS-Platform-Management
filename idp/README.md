# Internal Developer Platform (IDP)

The CAP IDP provides self-service, golden-path templates for teams to provision
standardized workloads without needing to understand underlying platform details.

## Available Templates

| Template | Use Case | Runtime |
|----------|----------|---------|
| `rest-api-service` | HTTP REST API with database | Python/Node/Java |
| `ecs-microservice` | Background worker or batch processor | Python/Node |
| `eks-workload` | Long-running stateful or stateless service | Any (containerized) |
| `data-pipeline` | ETL/ELT data processing pipeline | Python (Glue/Step Functions) |

## Usage

```bash
pip install cookiecutter
cookiecutter idp/templates/rest-api-service/
# Answer prompts → generates a fully configured service repository
```

## What You Get

Each template includes:
- Dockerfile (hardened, non-root, multi-stage)
- IaC (CDK or Terraform module) for deployment
- GitHub Actions workflow (pre-configured with OIDC + security gates)
- Pre-commit hooks
- Observability (CloudWatch logs, X-Ray tracing configured)
- Health check endpoints
