# n8n + Traefik + Cloudflare Tunnel on Colima


This setup lets you run **n8n** locally on macOS with **Colima**, expose it securely with a **Cloudflare Tunnel**, and manage TLS via Traefik.  
The script `manage.sh` automates everything: dependency checks, Colima VM startup, Cloudflare tunnel creation, environment variable validation, and deployment.  

---

## Requirements

- macOS with **Homebrew** installed  
- Cloudflare account + domain managed by Cloudflare  
- `.env` file (see example below)  
- `docker-compose.yaml` (already provided in this repo)  

---

## Environment Variables

These variables are **critical** and will be requested if missing or still set to a placeholder:

| Variable                 | Description                              | Example                |
|---------------------------|------------------------------------------|------------------------|
| `N8N_USER_EMAIL`          | Admin email for n8n login                | `admin@example.com`    |
| `N8N_USER_PASSWORD`       | Admin password for n8n                   | `strongpassword123`    |
| `SUBDOMAIN`               | Subdomain for your service               | `n8n`                  |
| `DOMAIN_NAME`             | Root domain managed in Cloudflare         | `example.com`          |
| `DB_POSTGRESDB_PASSWORD`  | Database password for n8n                 | `secret123`            |

Other variables (`DB_POSTGRESDB_HOST`, `DB_POSTGRESDB_PORT`, etc.) can remain with defaults unless you use an external DB.

---

## 📄 Example `.env`

Copy this into a file named `.env` in the project root before running `./manage.sh`.  
The script will prompt you to replace the placeholders if you leave them as-is.

```env
# n8n user information
N8N_USER_EMAIL=your_email@example.com
N8N_USER_PASSWORD=your_password

# domain information
SUBDOMAIN=subdomain
DOMAIN_NAME=example.com

# database information
DB_POSTGRESDB_HOST=db
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=your_password
DB_POSTGRESDB_DATABASE=n8n

# timezone information
GENERIC_TIMEZONE=Asia/Jerusalem
```

---

## Usage

Make the script executable:

```zsh
chmod +x manage.sh
```


Start services (default):

```zsh
./manage.sh start
```

Stop services and Colima:

```zsh
./manage.sh stop
```

Show live logs:

```zsh
./manage.sh logs
```

Show status of Colima and n8n services:

```zsh
./manage.sh status
```

Show script version:

```zsh
./manage.sh --version
```

Skip Cloudflare tunnel creation (only for start):

```zsh
./manage.sh start --skip-tunnel
```

Show help:

```zsh
./manage.sh --help
```

---

## Script Flow


### Actions

#### `start`

1. **Workspace check** → Validates `.env` and `docker-compose.yaml`.
2. **Dependency check** → Installs `colima`, `docker`, `docker-compose`, and `cloudflared` if missing.
3. **Colima startup** → Starts VM with limited resources (`2 CPU / 4GB RAM / 30GB disk`).
4. **Docker check** → Ensures Docker is running inside Colima.
5. **Cloudflare Tunnel** → Creates tunnel + DNS record, extracts token, updates `.env` (unless `--skip-tunnel` is used).
6. **Environment variables** → Prompts you to update/confirm all critical variables.
7. **Deploy** → Runs `docker compose up -d`.
8. **Access** → Prints your n8n URL:

    ```zsh
    Your n8n instance should be available at: https://SUBDOMAIN.DOMAIN_NAME/
    ```

#### `stop`

1. **Stop services** → Shuts down n8n containers and Colima VM.
2. **Cleanup** → Confirms all services and Colima have been stopped.

#### `logs`

1. **Show logs** → Tails live logs from n8n services.

#### `status`

1. **Show status** → Displays current status of Colima VM and n8n containers.

#### `--version`

1. **Show script version** → Prints the current version of the manage.sh script.

---

## Notes

- Always make sure your domain is managed by **Cloudflare**.  
- If you change critical values (like subdomain or password), rerun `./manage.sh start` and confirm updates.  
- Colima resources (CPU/RAM/Disk) can be adjusted inside the script variables at the top.  
