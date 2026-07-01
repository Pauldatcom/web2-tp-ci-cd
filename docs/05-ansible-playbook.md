# Ansible - Playbooks & Roles après Terraform

## Objectif
Configurer avec Ansible les conteneurs créés dans l'exercice Terraform précédent, comprendre l'idempotence et structurer le code en roles.

## Contexte
Dans l'exercice Terraform modules, Terraform a provisionné :

- un réseau Docker `devops-dev`
- deux conteneurs web `devops-app-dev-0` et `devops-app-dev-1`
- un conteneur PostgreSQL `devops-app-db-dev`

Ici, on ne recrée pas l'infrastructure. Terraform garde la responsabilité du cycle de vie des ressources Docker. Ansible prend le relais pour configurer les conteneurs web déjà existants.

## Pré-requis

Depuis l'exercice Terraform :

```bash
cd infra/terraform/environments/dev
terraform workspace select dev
terraform apply -var-file="terraform.tfvars" -var="db_password=secret123"
docker ps --filter "name=devops-app"
```

Si les collections Ansible nécessaires ne sont pas disponibles :

```bash
ansible-galaxy collection install community.docker community.general
```

## Consignes

### 1. Créer le dossier Ansible

Depuis la racine du projet :

```bash
mkdir -p infra/ansible
cd infra/ansible
```

### 2. Inventaire basé sur les sorties Terraform

Créer `infra/ansible/inventory.yml` :

```yaml
---
all:
  vars:
    ansible_connection: docker
    ansible_python_interpreter: /usr/bin/python3
    app_name: devops-app
    app_environment: dev
    app_log_level: info
    database_host: devops-app-db-staging
    database_port: 5432

  children:
    webservers:
      hosts:
        devops-app-staging-0:
          public_url: http://localhost:8080
        devops-app-staging-1:
          public_url: http://localhost:8081

    databases:
      hosts:
        devops-app-db-staging:
```

Vérifier que les noms correspondent bien aux conteneurs Terraform :

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
```

> Les conteneurs `nginx:alpine` n'ont pas Python par défaut. On ne commence donc pas par `ansible -m ping` : on va d'abord bootstrapper Python avec le module `raw`.

### 3. Bootstrap Python sur les conteneurs web

Créer `infra/ansible/bootstrap-python.yml` :

```yaml
---
- name: Préparer les conteneurs web pour Ansible
  hosts: webservers
  gather_facts: false

  tasks:
    - name: Installer Python si absent
      raw: test -x /usr/bin/python3 || apk add --no-cache python3
      register: bootstrap_python
      changed_when: bootstrap_python.stdout | length > 0
```

Tester ensuite la connexion Ansible :

```bash
ansible-playbook -i inventory.yml bootstrap-python.yml
ansible webservers -i inventory.yml -m ping
```

### 4. Structure en roles

Créer la structure :

```bash
mkdir -p roles/{base,nginx}/{tasks,handlers,templates,defaults}
```

**roles/base/defaults/main.yml** :

```yaml
---
base_packages:
  - curl
  - tzdata

app_config_dir: /opt/app
```

**roles/base/tasks/main.yml** :

```yaml
---
- name: Installer les paquets d'exploitation
  apk:
    name: "{{ base_packages }}"
    state: present
    update_cache: true

- name: Créer le répertoire de configuration applicative
  file:
    path: "{{ app_config_dir }}"
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Déployer le fichier d'environnement applicatif
  copy:
    content: |
      APP_NAME={{ app_name }}
      APP_ENV={{ app_environment }}
      APP_LOG_LEVEL={{ app_log_level }}
      PUBLIC_URL={{ public_url }}
      DATABASE_HOST={{ database_host }}
      DATABASE_PORT={{ database_port }}
    dest: "{{ app_config_dir }}/.env"
    owner: root
    group: root
    mode: '0640'
```

**roles/nginx/defaults/main.yml** :

```yaml
---
nginx_conf_path: /etc/nginx/conf.d/default.conf
nginx_web_root: /usr/share/nginx/html
```

**roles/nginx/tasks/main.yml** :

```yaml
---
- name: Vérifier que le répertoire web existe
  file:
    path: "{{ nginx_web_root }}"
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Déployer la configuration Nginx
  template:
    src: default.conf.j2
    dest: "{{ nginx_conf_path }}"
    owner: root
    group: root
    mode: '0644'
  notify: reload nginx

- name: Valider la configuration Nginx
  command: nginx -t
  changed_when: false

- name: Déployer la page d'accueil
  template:
    src: index.html.j2
    dest: "{{ nginx_web_root }}/index.html"
    owner: root
    group: root
    mode: '0644'
```

**roles/nginx/handlers/main.yml** :

```yaml
---
- name: reload nginx
  command: nginx -s reload
  changed_when: true
```

**roles/nginx/templates/default.conf.j2** :

```nginx
server {
    listen 80 default_server;
    server_name _;
    root {{ nginx_web_root }};
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /health {
        default_type application/json;
        return 200 '{"status":"ok","app":"{{ app_name }}","environment":"{{ app_environment }}","host":"{{ inventory_hostname }}"}';
    }
}
```

**roles/nginx/templates/index.html.j2** :

```html
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>{{ app_name }} - {{ app_environment }}</title>
</head>
<body>
  <h1>{{ app_name }}</h1>
  <p>Environnement : {{ app_environment }}</p>
  <p>Conteneur : {{ inventory_hostname }}</p>
  <p>URL publique : {{ public_url }}</p>
</body>
</html>
```

### 5. Playbook principal

Créer `infra/ansible/site.yml` :

```yaml
---
- import_playbook: bootstrap-python.yml

- name: Configurer les serveurs web provisionnés par Terraform
  hosts: webservers
  gather_facts: false
  roles:
    - base
    - nginx
```

### 6. Exécuter et vérifier

```bash
# Première exécution : Ansible installe et configure
ansible-playbook -i inventory.yml site.yml

# Deuxième exécution : rien ne doit changer
ansible-playbook -i inventory.yml site.yml
# Résultat attendu : changed=0 sur les conteneurs déjà configurés

# Vérification fonctionnelle
curl http://localhost:8080/
curl http://localhost:8081/
curl http://localhost:8080/health
curl http://localhost:8081/health
```

### 7. Modifier une variable pour observer les handlers

Dans `inventory.yml`, changer par exemple :

```yaml
app_log_level: debug
```

Relancer :

```bash
ansible-playbook -i inventory.yml site.yml
ansible-playbook -i inventory.yml site.yml
```

Observer :

- le fichier `/opt/app/.env` change au premier run
- le second run redevient idempotent
- le handler `reload nginx` ne se déclenche que si la configuration Nginx change

## Livrable

- Inventaire Ansible ciblant les conteneurs créés par Terraform
- Playbook `bootstrap-python.yml`
- Playbook principal `site.yml`
- Roles `base` et `nginx`
- Preuve d'idempotence : deuxième exécution avec `changed=0`
- Vérification HTTP sur les deux URLs Terraform (`8080` et `8081`)

## Aide

### Commandes utiles

```bash
# Vérifier la syntaxe
ansible-playbook --syntax-check -i inventory.yml site.yml

# Lister les hosts
ansible-inventory -i inventory.yml --graph

# Lister les tâches
ansible-playbook -i inventory.yml site.yml --list-tasks

# Limiter à un conteneur
ansible-playbook -i inventory.yml site.yml --limit devops-app-dev-0

# Mode verbeux
ansible-playbook -i inventory.yml site.yml -vvv
```

### Si les noms ne correspondent pas

Si vous avez changé `app_name`, `environment`, `web_port` ou `web_replicas` dans Terraform, adaptez `inventory.yml` avec les vrais noms :

```bash
docker ps --format "{{.Names}}"
```

### Nettoyage

Le nettoyage reste côté Terraform :

```bash
cd ../terraform/environments/dev
terraform destroy -var-file="terraform.tfvars" -var="db_password=secret123"
```