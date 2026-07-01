# DevOps Training

A 3-day DevOps training program covering CI/CD, containerization, Infrastructure as Code (Terraform) and configuration management (Ansible), built around a Node.js sample application.

## Project structure

```
app/                  # Node.js sample application (see app/README.md)
infra/terraform/      # Terraform modules and environments (Docker provider)
infra/ansible/        # Ansible inventory, playbooks and roles
.github/workflows/    # CI pipeline (tests, image build, tooling)
docs/                 # Exercise instructions and course material
```

## Prerequisites

See [docs/consignes.md](docs/consignes.md) for installing and verifying the required tools (Git, Docker, kubectl, Terraform, Ansible, Helm, ArgoCD).

## Exercise path

| Doc | Topic |
|---|---|
| [01-pipelines-ci-cd.md](docs/01-pipelines-ci-cd.md) | CI/CD pipeline concepts |
| [02-github-actions.md](docs/02-github-actions.md) | GitHub Actions pipeline (tests, build, reusable workflow) |
| [03-terraform.md](docs/03-terraform.md) | Terraform introduction |
| [04-terraform-modules.md](docs/04-terraform-modules.md) | Terraform modules (webapp, database) |
| [05-ansible-playbook.md](docs/05-ansible-playbook.md) | Ansible playbooks and roles |
| [06-inventaire-dynamique.md](docs/06-inventaire-dynamique.md) | Ansible inventory generated from Terraform |

## Application

The application (`app/`) is a Node.js service exposing `/`, `/health` and `/metrics`. See [app/README.md](app/README.md) for test and build commands.

## Infrastructure

Terraform provisions Docker containers (webapp + PostgreSQL) per environment (`staging`, `prod`):

```bash
cd infra/terraform/environments/staging
terraform workspace select -or-create staging
terraform apply -var-file="terraform.tfvars" -var="db_password=<password>"
```

Ansible then configures the containers from an inventory generated off the Terraform outputs:

```bash
cd infra/ansible
./scripts/render-inventory.sh
ansible-playbook -i inventory.yml site.yml
```

## CI

The GitHub Actions pipeline (`.github/workflows/ci.yml`) runs the app's tests across multiple Node versions, builds the Docker image via a reusable workflow, and validates the composite actions.
