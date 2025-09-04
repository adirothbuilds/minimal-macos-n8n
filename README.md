# n8n + Traefik + Cloudflare Tunnel on Colima

This setup lets you run **n8n** locally on macOS with **Colima**, expose it securely with a **Cloudflare Tunnel**, and manage TLS via Traefik.  
The script `start.sh` automates everything: dependency checks, Colima VM startup, Cloudflare tunnel creation, environment variable validation, and deployment.  

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

Copy this into a file named `.env` in the project root before running `./start.sh`.  
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
chmod +x start.sh
```

Run with defaults:

```zsh
./start.sh
```

Skip Cloudflare tunnel creation (if you already have one):

```zsh
./start.sh --skip-tunnel
```

Show help:

```zsh
./start.sh --help
```

---

## Script Flow

1. **Workspace check** → Validates `.env` and `docker-compose.yaml`.  
2. **Dependency check** → Installs `colima`, `docker`, `docker-compose`, and `cloudflared` if missing.  
3. **Colima startup** → Starts VM with limited resources (`2 CPU / 4GB RAM / 30GB disk`).  
4. **Docker check** → Ensures Docker is running inside Colima.  
5. **Cloudflare Tunnel** → Creates tunnel + DNS record, extracts token, updates `.env`.  
6. **Environment variables** → Prompts you to update/confirm all critical variables.  
7. **Deploy** → Runs `docker compose up -d`.  
8. **Access** → Prints your n8n URL:  

    ```zsh
    Your n8n instance should be available at: https://SUBDOMAIN.DOMAIN_NAME/
    ```

---

## Notes

- Always make sure your domain is managed by **Cloudflare**.  
- If you change critical values (like subdomain or password), rerun `./start.sh` and confirm updates.  
- Colima resources (CPU/RAM/Disk) can be adjusted inside the script variables at the top.  
