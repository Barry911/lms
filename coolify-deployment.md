# Coolify Deployment Guide - Frappe LMS

This guide provides step-by-step instructions on deploying the Frappe Learning Management System (LMS) application on a **Coolify** instance in a production-ready, containerized manner.

---

## Architecture Overview

The deployment uses a production-grade, multi-stage decoupled Docker architecture:
1. **`db` (MariaDB):** Database service configured with the UTF-8 character sets required by Frappe.
2. **`redis-cache` & `redis-queue`:** Redis instances for fast session caching and job queue storage.
3. **`backend` (Gunicorn):** The Python web server running Gunicorn, serving dynamic routes.
4. **`websocket`:** The Node.js WebSocket server handling real-time socket connections.
5. **`scheduler`:** The Frappe scheduler daemon executing cron-like scheduled tasks.
6. **`worker`:** Background workers picking up default, short, and long-running job queues.
7. **`frontend` (Nginx):** A reverse proxy serving static assets directly and forwarding dynamic traffic to the backend/websocket servers.

---

## Step-by-Step Deployment Instructions

### Step 1: Add a New Resource in Coolify
1. Open your Coolify Dashboard.
2. Select your Project and Environment.
3. Click **"+ Add Resource"** and choose **"Docker Compose"**.
4. Give it a name (e.g., `lms-stack`).

### Step 2: Paste the Docker Compose Configuration
1. In the source input field, copy and paste the contents of `docker-compose.coolify.yml` from this repository.
2. Coolify will detect the repository and link the build context to your Git branch.

### Step 3: Configure Domains and Routing
1. In the Coolify UI, find the **`frontend`** service.
2. Under the **"Domains"** configuration field, assign your public domain (e.g., `https://lms.yourdomain.com`).
3. Set the proxy port to `8080` (this maps standard HTTPS port 443 traffic to the Nginx port `8080` container port).
4. Do *not* map ports manually under the `ports:` block in `docker-compose.coolify.yml` to prevent port conflicts on the host.

### Step 4: Configure Environment Variables
Navigate to the **"Environment Variables"** tab of your Coolify resource and add the following:

| Variable Name | Description | Example / Recommended Value |
| :--- | :--- | :--- |
| `SITE_NAME` | The exact domain you set in Step 3. | `lms.yourdomain.com` |
| `DB_ROOT_PASSWORD` | The root password for MariaDB. | *(Generate a secure random string)* |
| `ADMIN_PASSWORD` | The initial administrator password. | *(Generate a secure password)* |

### Step 5: Start Deployment
1. Click the **"Deploy"** button.
2. Coolify will clone the repository, run the multi-stage build (cloning the payments app, copy-installing the local LMS code, and compiling all frontend assets), and launch all services.
3. *Note: The initial build can take 5–10 minutes depending on your server's CPU and memory.*

---

## Automated Operations

- **First Boot Initialization:** When the backend container boots for the first time, the `docker/start.sh` script detects that the site folder does not exist. It automatically waits for the MariaDB service to become healthy, sets the DB hosts, runs `bench new-site`, and installs both `payments` and `lms` apps automatically.
- **Subsequent Boot Migrations:** On container updates or restarts, the script detects that the site already exists and automatically runs `bench --site [SITE_NAME] migrate` to apply database schema updates safely without data loss.

---

## Troubleshooting & Maintenance

### 1. Recreating Demo Data
If you need to seed the LMS with demo courses, instructors, and learners for testing, execute the following command inside the `backend` container via Coolify's built-in terminal:
```bash
bench --site lms.localhost execute lms.demo.demo_data.create_demo_data
```
*(Replace `lms.localhost` with your actual `SITE_NAME`).*

### 2. Checking Logs
- Gunicorn web logs are printed directly to standard output of the `backend` container.
- Scheduler and Worker logs are accessible in the standard output of the `scheduler` and `worker` containers.
- Nginx request logs are located in the `frontend` container logs.
