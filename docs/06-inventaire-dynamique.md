# Terraform + Ansible - Inventaire dynamique

## Objectif
Remplacer l'inventaire Ansible écrit à la main par un inventaire généré depuis le résultat Terraform.

À la fin de l'exercice :

- Terraform reste la source de vérité pour les conteneurs Docker
- Ansible ne contient plus de noms de conteneurs codés en dur
- `inventory.yml` est généré depuis `terraform output`
- un changement Terraform (`web_replicas`, ports, noms, environnement) se répercute dans Ansible sans modifier l'inventaire à la main

## Contexte
Dans l'exercice 04, Terraform a créé les conteneurs Docker.

Dans l'exercice 05, Ansible les configure, mais l'inventaire contenait encore des noms écrits à la main. C'est fragile : si Terraform crée 3 webservers au lieu de 2, ou si `app_name` / `environment` change, l'inventaire devient faux.

Dans cet exercice, on corrige ça. On met à jour la configuration Terraform et le workflow Ansible pour générer l'inventaire à partir des ressources réellement créées.

## Pré-requis

- Exercice 04 appliqué avec Terraform
- Exercice 05 disponible avec les playbooks et roles Ansible
- Les conteneurs Terraform existent encore

Vérifier :

```bash
cd infra/terraform/environments/dev
terraform workspace select dev
terraform apply -var-file="terraform.tfvars" -var="db_password=secret123"
terraform state list
```

## Consignes

### 1. Exposer les infos utiles côté module `webapp`

Dans `infra/terraform/modules/webapp/outputs.tf`, ajouter :

```hcl
output "ansible_hosts" {
  value = {
    for c in docker_container.app :
    c.name => {
      public_url  = "http://localhost:${c.ports[0].external}"
      public_port = c.ports[0].external
    }
  }
}
```

Ce bloc utilise les attributs réels des conteneurs créés par Terraform. On ne recopie pas les noms à la main.

### 2. Exposer les infos utiles côté module `database`

Dans `infra/terraform/modules/database/outputs.tf`, ajouter :

```hcl
output "ansible_host" {
  value = {
    name = docker_container.db.name
    port = var.db_port
  }
}
```

### 3. Ajouter une variable de configuration applicative

Dans `infra/terraform/environments/dev/main.tf`, ajouter :

```hcl
variable "app_log_level" {
  type    = string
  default = "info"
}
```

Dans `infra/terraform/environments/dev/terraform.tfvars`, ajouter :

```hcl
app_log_level = "info"
```

Cette variable sera transmise à Ansible via l'inventaire généré.

### 4. Générer l'inventaire Ansible depuis Terraform

Dans `infra/terraform/environments/dev/main.tf`, ajouter cet output :

```hcl
output "ansible_inventory" {
  value = yamlencode({
    all = {
      vars = {
        ansible_connection         = "docker"
        ansible_python_interpreter = "/usr/bin/python3"
        app_name                   = var.app_name
        app_environment            = var.environment
        app_log_level              = var.app_log_level
        database_host              = module.database.ansible_host.name
        database_port              = module.database.ansible_host.port
      }
      children = {
        webservers = {
          hosts = module.webapp.ansible_hosts
        }
        databases = {
          hosts = {
            (module.database.ansible_host.name) = {}
          }
        }
      }
    }
  })
}
```

Point important : cet output ne contient aucune liste de noms écrite à la main. Les hosts viennent des ressources Terraform.

### 5. Appliquer les changements Terraform

```bash
cd infra/terraform/environments/dev
terraform fmt -recursive ../..
terraform apply -var-file="terraform.tfvars" -var="db_password=secret123"
y
```

Vous devez voir un YAML d'inventaire Ansible.

### 6. Générer `inventory.yml` côté Ansible

Depuis la racine du projet :

```bash
mkdir -p infra/ansible/scripts
cd infra/ansible
```

Créer `infra/ansible/scripts/render-inventory.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail

terraform_dir="../terraform/environments/dev"
output_file="inventory.yml"

terraform -chdir="$terraform_dir" output -raw ansible_inventory > "$output_file"
ansible-inventory -i "$output_file" --graph
```

Rendre le script exécutable :

```bash
chmod +x scripts/render-inventory.sh
```

Générer l'inventaire :

```bash
./scripts/render-inventory.sh
```

À partir de maintenant, `infra/ansible/inventory.yml` est un fichier généré. Ne le modifiez plus à la main.

### 7. Vérifier qu'Ansible consomme l'inventaire généré

```bash
ansible-inventory -i inventory.yml --list
ansible-playbook -i inventory.yml bootstrap-python.yml
ansible webservers -i inventory.yml -m ping
```

Puis relancer le playbook principal de l'exercice 05 :

```bash
ansible-playbook -i inventory.yml site.yml
ansible-playbook -i inventory.yml site.yml
```

Le deuxième run doit redevenir idempotent.

### 8. Prouver que l'inventaire suit Terraform

Dans `infra/terraform/environments/dev/terraform.tfvars`, changer :

```hcl
web_replicas = 3
app_log_level = "debug"
```

Appliquer :

```bash
cd infra/terraform/environments/dev
terraform apply -var-file="terraform.tfvars" -var="db_password=secret123"
```

Regénérer l'inventaire :

```bash
cd ../../../ansible
./scripts/render-inventory.sh
```

Vérifier :

```bash
ansible-inventory -i inventory.yml --graph
ansible-playbook -i inventory.yml site.yml
```

Résultat attendu :

- le groupe `webservers` contient maintenant le nombre de conteneurs défini par Terraform
- Ansible configure le nouveau conteneur sans ajout manuel dans `inventory.yml`
- le fichier `/opt/app/.env` reçoit `APP_LOG_LEVEL=debug`

### 9. Vérifier les URLs depuis l'inventaire

Afficher les URLs générées :

```bash
ansible-inventory -i inventory.yml --list
```

Tester les endpoints indiqués dans `public_url` :

```bash
curl <public_url>
curl <public_url>/health
```

Remplacez `<public_url>` par les valeurs générées. Ne tapez pas les noms de conteneurs à la main.

## Livrable

- Outputs Terraform `ansible_hosts`, `ansible_host` et `ansible_inventory`
- Script `infra/ansible/scripts/render-inventory.sh`
- Fichier `infra/ansible/inventory.yml` généré
- Playbook Ansible exécuté depuis l'inventaire généré
- Démonstration : modifier `web_replicas`, appliquer Terraform, regénérer l'inventaire, relancer Ansible

## Aide

### Commandes utiles

```bash
# Voir l'inventaire généré sans l'écrire dans un fichier
terraform -chdir=infra/terraform/environments/dev output -raw ansible_inventory

# Regénérer l'inventaire
cd infra/ansible
./scripts/render-inventory.sh

# Visualiser les groupes
ansible-inventory -i inventory.yml --graph

# Vérifier les variables d'un host
ansible-inventory -i inventory.yml --host <host-genere-par-terraform>
```

### Erreurs fréquentes

- Modifier `inventory.yml` à la main : le fichier sera écrasé à la prochaine génération
- Oublier `terraform apply` après avoir ajouté les outputs
- Regénérer l'inventaire depuis le mauvais workspace Terraform
- Changer `web_replicas` avec `-var` puis oublier que `terraform.tfvars` contient encore l'ancienne valeur
- Lancer Ansible avant de bootstrapper Python sur les nouveaux conteneurs

### Nettoyage

Le nettoyage reste côté Terraform :

```bash
cd infra/terraform/environments/dev
terraform destroy -var-file="terraform.tfvars" -var="db_password=secret123"
```
