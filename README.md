# vps-setup-dokploy

VPS setup scripts for Dokploy with optional Pangolin VPN integration.

## Scripts

- `dokploy-setup.sh` - Initial server setup with Dokploy installation
- `pangolin-setup.sh` - Server setup with Pangolin VPN platform installation

## Restricting Dokploy Admin Access via Pangolin VPN

After setting up Pangolin, you can hide Dokploy's admin interface behind the VPN so it's only accessible when connected via Pangolin.

### Prerequisites

- Pangolin server running (use `pangolin-setup.sh`)
- Dokploy running in Docker Swarm mode
- A site created in your Pangolin dashboard

### Step 1: Create a Site in Pangolin Dashboard

1. Log into your Pangolin dashboard
2. Create a new Site
3. Note the **Site ID**, **Secret**, and **Endpoint** values

### Step 2: Configure Private Resource in Pangolin

1. In Pangolin dashboard, go to **Resources** → **Add Resource**
2. Select **Private Resource**
3. Configure:
   - **Name**: Dokploy Admin
   - **Destination**: `dokploy` (Docker service DNS name - stable across restarts)
   - **Port Restrictions**: TCP → Specific → `3000`
   - **Site**: Select your site
4. Save the resource

### Step 3: Run Newt on the Same Docker Network

Newt needs to run on the same Docker overlay network as Dokploy to reach it:

```bash
# Find the Dokploy network
docker network ls | grep dokploy
# Usually: dokploy-network

# Run Newt as a Docker Swarm service
docker service create \
  --name newt \
  --network dokploy-network \
  --cap-add NET_ADMIN \
  --restart-condition any \
  ghcr.io/fosrl/newt:latest \
  --id YOUR_SITE_ID \
  --secret YOUR_SITE_SECRET \
  --endpoint https://YOUR_PANGOLIN_DOMAIN

# Check status
docker service ps newt
docker service logs -f newt
```

You should see output like:
```
INFO: Tunnel connection to server established successfully!
INFO: Added target subnet ... to dokploy/32 rewrite to with port ranges: [{3000 3000 tcp}]
INFO: Client connectivity setup. Ready to accept connections from clients!
```

### Step 4: Install Pangolin Client on Your Local Machine

**Arch Linux:**
```bash
curl -fsSL https://get.pangolin.net/cli.sh | sh
pangolin login --url https://YOUR_PANGOLIN_DOMAIN
pangolin connect
```

**Other platforms:** See [Pangolin documentation](https://docs.pangolin.net)

### Step 5: Access Dokploy Through Pangolin

Once connected via Pangolin client, access Dokploy using:
- The Magic DNS name configured in Pangolin
- Or the Pangolin-assigned IP for the resource

### Step 6: Remove Public Access to Dokploy

Remove Dokploy's public port exposure so it's only accessible via Pangolin:

```bash
docker service update --publish-rm 3000:3000 dokploy
```

After this, Dokploy admin will only be accessible when connected through Pangolin.
