# Deploying to Cloudflare Pages

This website is structured as a self-contained static directory (`website/`). You can deploy it to Cloudflare Pages in under two minutes.

## Deployment Steps

1. **Push Changes to GitHub**:
   Ensure your code, including this `website` directory, is pushed to your GitHub repository.

2. **Log In to Cloudflare**:
   Go to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and navigate to **Workers & Pages** in the sidebar.

3. **Create a New Project**:
   - Click **Create** (or **Create application**), then select the **Pages** tab.
   - Click **Connect to git**.
   - Select your GitHub account and choose the `PowerInfo-4-Mac` repository.

4. **Configure Build Settings**:
   - **Project Name**: `powerinfo-4-mac` (or any name you prefer).
   - **Production branch**: `main` (or your default branch).
   - **Framework preset**: Select **None** (this is a vanilla static site).
   - **Build command**: Leave this completely **blank** (no build step is required).
   - **Build output directory**: Change this to `website` (so Cloudflare only serves files from this subdirectory).

5. **Deploy**:
   - Click **Save and Deploy**.
   - Cloudflare will build and deploy the page in about a minute, giving you a custom `*.pages.dev` subdomain (e.g., `powerinfo-4-mac.pages.dev`).

## Customizing Your Domain

If you want to map a custom domain (like `powerinfo.yourdomain.com`):
1. In your Cloudflare Pages project dashboard, go to the **Custom domains** tab.
2. Click **Set up a custom domain** and enter your domain name.
3. Cloudflare will automatically configure the SSL certificate and DNS records if your domain is managed by Cloudflare.
