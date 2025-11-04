#  Flask App Deployment on GKE using Cloud Build, Helm & Argo CD

> End-to-end, automated CI/CD + GitOps for a Flask app using:
> **Cloud Build** (CI) → **Artifact Registry** (images) → **Helm** (packaging) → **Argo CD** (GitOps CD) → **GKE + NGINX Ingress** (hosting & exposure)


---

##  Overview (What & Why)

- **What:** Build and deploy a Flask web app to GKE automatically whenever you push code to GitHub.
- **Why:** Automates build/test/deploy, keeps infrastructure declarative (GitOps), and makes rollbacks and visibility easy using Argo CD.

## Architecture diagram 

<img width="1699" height="806" alt="diagram-export-11-4-2025-12_33_43-PM" src="https://github.com/user-attachments/assets/48757146-ea3f-4019-96e0-61985c4aa946" />

## 🧩 Project Overview

1. **Developer updates code** in GitHub (e.g., `app.py`, `Dockerfile`, etc.)  
2. **Cloud Build Trigger** runs automatically when a commit is pushed to `main`.  
3. **Cloud Build:**
   - Builds a new Docker image  
   - Pushes it to **Artifact Registry**  
   - Updates image tag in `values.yaml`  
   - Pushes the updated files back to GitHub  
4. **Argo CD** continuously monitors the GitHub repository.  
   - When `values.yaml` or `deployment.yaml` changes, Argo CD detects it.  
   - It syncs the Kubernetes cluster automatically and deploys the latest version.  
5. **Ingress Controller** exposes the app to the internet via your domain (e.g., `flask.mayaworld.tech`).  


> **Important:** The Cloud Build trigger is configured to **not** re-run for commits that only contain changes to `deployment.yaml` or `values.yaml` or `README.md` (this prevents infinite build loops).

---
## ⚙️ Prerequisites

Make sure you have the following ready:

- A **Google Cloud project** with billing enabled.  
- **GKE Autopilot cluster** or Standard cluster.  
- **Cloud Build API** and **Artifact Registry API** enabled.  
- **Argo CD** installed in your cluster.  
- **Nginx Ingress Controller** installed.  
- A **GitHub repository** (e.g., `python-gcp`) connected to Cloud Build.  

## 📁 Repo structure
<img width="245" height="306" alt="image" src="https://github.com/user-attachments/assets/60d2def0-ea6e-4448-a8cf-fbcabd5c2354" />

## 🔧 Files & Key Examples

### Step 1: `app.py` (simple Flask)
```python

from flask import Flask, render_template
import random

app = Flask(__name__)

quotes = [
    "💡 Believe in yourself — you’re unstoppable!",
    "🚀 Every great dream begins with a dreamer.",
    "🔥 The best time to start was yesterday. The next best time is now.",
    "🌟 Code. Deploy. Repeat. Success follows consistency.",
    "🎯 Focus on progress, not perfection."
]

@app.route('/')
def home():
    message = random.choice(quotes)
    return render_template('index.html', message=message)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
```
## Step 2: create Dockerfile

```dockerfile
# Use official lightweight Python image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy files
COPY app.py ./
COPY templates ./templates

# Install Flask
RUN pip install flask

# Expose Flask port
EXPOSE 5000

# Run the app
CMD ["python", "app.py"]
```
## 🏢 Step 3: Create Artifact Registry

1. Go to **Google Cloud Console → Artifact Registry → Repositories → Create Repository**  
2. **Name:** `flask-repo`  
3. **Format:** `Docker`  
4. **Location:** Region of your choice (e.g., `us-west1`)  

Authenticate Docker with Artifact Registry:  
```bash
gcloud auth configure-docker us-west1-docker.pkg.dev
````

## Step 4: Create GKE Cluster
```bash
gcloud container clusters create-auto autopilot-cluster1 \
  --region=us-west1
```
<img width="1455" height="231" alt="image" src="https://github.com/user-attachments/assets/c67e1271-97a4-4aa6-8eb8-8e85acc2d9fe" />

now connect this cluster
```bash
gcloud container clusters get-credentials autopilot-cluster1 --region us-west1
```

## Step 5: Set Up Cloud Build Trigger

1. Go to **Cloud Build → Triggers → Create Trigger**  
2. **Name:** `flaskapp-build`  
3. **Source Repository:** Connect to your GitHub repo.  
4. **Branch:** `main`  
5. **Trigger Type:** “Push to branch”  
6. **Build Configuration:** `cloudbuild.yaml`  
7. **Substitution Variable:**  
   - `_GITHUB_TOKEN = your GitHub Personal Access Token (stored in Secret Manager)`  
8. **Include/Exclude Filters:**  
   - **Include:** All files  
   - **Exclude:** `deployment.yaml`, `values.yaml`  

🧠 This ensures the build trigger runs only when app code changes, not when manifest updates happen.

<img width="1436" height="161" alt="image" src="https://github.com/user-attachments/assets/a663608c-356c-4e4d-bc34-c291951836a4" />


## Step 6: 🔐  Create the Personal Access Token (PAT) of Github and Secret to autoupdate the image tag

### 🧩 a)  Create the PAT in GitHub

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens** (or “classic” if needed).  
2. Click **“Generate new token”**  
3. Give it a name (e.g., `cloudbuild-auto`)  
4. Select scopes/permissions:  
   - ✅ `repo` (full access to read/write)  
   - ✅ `workflow` (optional if you have GitHub Actions)  
5. **Copy the generated token** — you’ll only see it once.

---

### 🗝️ b)  Store it in Google Secret Manager

You’ll use this in your Cloud Build pipeline.

```bash
gcloud secrets create GITHUB_TOKEN --replication-policy="automatic"
```
Then add the token value:
```bash
echo "YOUR_GITHUB_PAT_HERE" | gcloud secrets versions add GITHUB_TOKEN --data-file=-
```

### 🔒 c)  Grant Cloud Build Access to the Secret
```bash
gcloud secrets add-iam-policy-binding GITHUB_TOKEN \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```
This allows Cloud Build to securely read the token at build time.

### 🧱 d) Reference It Inside Your cloudbuild.yaml

```yaml

steps:
  # 1️⃣ Build Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-west1-docker.pkg.dev/$PROJECT_ID/my-repo/mayaworld13:$SHORT_SHA', '.']

  # 2️⃣ Push image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-west1-docker.pkg.dev/$PROJECT_ID/my-repo/mayaworld13:$SHORT_SHA']

  # 3️⃣ Update image tag in deployment.yaml and push to GitHub
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: bash
    args:
      - -c
      - |
        echo "Updating image tag in values.yaml..."
        sed -i "s#tag: .*#tag: \"$SHORT_SHA\"#g" flaskapp/values.yaml 
        sed -i "s#image: .*#image: us-west1-docker.pkg.dev/$PROJECT_ID/my-repo/mayaworld13:$SHORT_SHA#g" deployment.yaml

        git config --global user.email "cloudbuild@google.com"
        git config --global user.name "Cloud Build"

        git add flaskapp/values.yaml deployment.yaml
        git commit -m "Auto-update Helm image tag to $SHORT_SHA"
        git push https://mayaworld13:$(gcloud secrets versions access latest --secret=GITHUB_TOKEN)@github.com/mayaworld13/python-gcp.git HEAD:main
    # args:
    #   - -c
    #   - |
    #     sed -i "s#image: .*#image: us-west1-docker.pkg.dev/$PROJECT_ID/my-repo/mayaworld13:$SHORT_SHA#g" deployment.yaml
    #     git config --global user.email "cloudbuild@google.com"
    #     git config --global user.name "Cloud Build"
    #     git add deployment.yaml
    #     git commit -m "Auto-update image tag to $SHORT_SHA"
    #     git push https://mayaworld13:$(gcloud secrets versions access latest --secret=GITHUB_TOKEN)@github.com/mayaworld13/python-gcp.git HEAD:main

images:
  - 'us-west1-docker.pkg.dev/$PROJECT_ID/my-repo/mayaworld13:$SHORT_SHA'

options:
  logging: CLOUD_LOGGING_ONLY
```

## Step 7: Create the helm chart
flaskapp/values.yaml
```yaml
replicaCount: 1

image:
  repository: us-west1-docker.pkg.dev/testing-474407/my-repo/mayaworld13
  tag: "latest"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 5000

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: flask.mayaworld.tech
      paths:
        - path: /
          pathType: Prefix
```
write the necessary changes and testing using helm upgrade using
```bash
kubectl create namespace flaskapp
helm upgrade --install flaskapp ./flaskapp -n flaskapp
```
then push the helm chart to you github repo.

## Step 8: Configure Ingress Controller

Install NGINX Ingress Controller (if not installed):
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```
Map your domain (e.g., flask.mayaworld.tech) to the External IP of your ingress:
```bash
kubectl get ingress -n flaskapp
```
Then update your DNS A record in your domain panel.

## Step 9: ☸️ Argo CD (GitOps) - UI Steps (Simple)

### 🧩 Install Argo CD in Your Cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
### 🌐 Expose Argo CD (for Testing)

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl get svc -n argocd
```
### 🔑 Open Argo CD UI and Login

Access the Argo CD UI at:

```bash
https://<ARGOCD_EXTERNAL_IP>
```

### Get the initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

<img width="891" height="491" alt="image" src="https://github.com/user-attachments/assets/5c15bdee-e74d-44a1-bf28-bbe23463db77" />

Click Create 

### 🔔 Add GitHub Webhook to Notify Argo CD
1. Go to GitHub → Settings → Webhooks → Add webhook
2. Payload URL:
   ```bash
    http://<ARGOCD_EXTERNAL_IP>/api/webhook
   ```
3. Content type: application/json
4. Events: Just the push event
5. Click Add webhook

## 🧩 Troubleshooting Guide

| **Issue** | **Cause** | **Solution** |
|------------|------------|---------------|
| **1️⃣ ImagePullBackOff Error** | The image tag referenced in `values.yaml` or `deployment.yaml` does not exist in Artifact Registry (old or incorrect image). | ✅ Ensure the Cloud Build successfully pushes the latest image to Artifact Registry.<br>✅ Verify the image tag in `values.yaml` matches the latest pushed tag.<br>✅ You can check with:<br>`gcloud artifacts docker images list <repo-name>` |
| **2️⃣ Ingress Conflict Error** | Error: `host "flask.mayaworld.tech" and path "/" is already defined in ingress flaskapp/flaskapp` — happens when two Ingress resources use the same hostname. | ✅ Run `kubectl get ingress -A` to list all Ingresses.<br>✅ Delete the duplicate one: `kubectl delete ingress <name> -n <namespace>`.<br>✅ Keep only one Ingress with the correct domain. |
| **3️⃣ Auto Sync Fails in ArgoCD (OutOfSync / Missing Health)** | ArgoCD cannot sync resources because of webhook validation or previously failed Ingress creation. | ✅ Delete the failed Ingress using: `kubectl delete ingress <name> -n <namespace>`.<br>✅ Wait for ArgoCD to reapply automatically.<br>✅ Check ArgoCD UI → App → Events for specific error. |
| **4️⃣ Cloud Build Trigger Not Running** | The trigger is not configured to run on specific file changes or branch pushes. | ✅ In Cloud Build trigger configuration, make sure the trigger type is **"Push to a branch"** and branch regex is `^main$`.<br>✅ Add included files filter to exclude certain files if needed.<br>⚠️ If you don’t want trigger to run for `deployment.yaml` or `values.yaml` commits, use an **ignore file filter**. |
| **5️⃣ GitHub Push Rejected (fetch first)** | Local repo not synced with GitHub remote. | ✅ Run:<br>`git pull origin main --rebase`<br>Then push again:<br>`git push origin main` |
| **6️⃣ ArgoCD Sync Shows “Missing” App Health** | Happens when the image or manifest update is in progress or Ingress is invalid. | ✅ Wait for sync to complete.<br>✅ Check `kubectl describe ingress -n <namespace>` for events.<br>✅ Ensure Helm chart values are consistent with deployment. |
| **7️⃣ Web App Not Accessible Externally** | Ingress or DNS misconfiguration, or service type not exposed. | ✅ Verify DNS: `dig flask.mayaworld.tech`.<br>✅ Check Ingress IP: `kubectl get ingress -n flaskapp`.<br>✅ Ensure Cloud DNS A record points to that IP. |
| **8️⃣ ArgoCD Not Auto Syncing After Image Update** | Webhook between GitHub → ArgoCD missing or misconfigured. | ✅ Add GitHub Webhook pointing to ArgoCD’s API URL (usually `https://argocd.yourdomain/api/webhook`).<br>✅ Use `Content-type: application/json`.<br>✅ Enable Auto-Sync in ArgoCD Application settings. |
| **9️⃣ Artifact Registry Image Not Found** | Image not built or uploaded correctly from Cloud Build. | ✅ Check Cloud Build logs.<br>✅ Verify image in Artifact Registry:<br>`gcloud artifacts docker images list LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME`.<br>✅ Update tag in `values.yaml`. |
| **🔟 Service Not Working Even After Deployment** | Service or deployment mismatch in Helm chart (wrong labels or selectors). | ✅ Ensure `selector` in Service matches `labels` in Deployment.<br>✅ Example:<br>```yaml<br>selector:<br>  app: flaskapp<br>``` matches ```yaml<br>metadata:<br>  labels:<br>    app: flaskapp<br>``` |

---

✅ **Pro Tips:**
- Always verify each new build pushed to Artifact Registry is reflected in Helm’s `values.yaml`.
- Keep only one Ingress per hostname to avoid webhook rejections.
- Use `kubectl get events -n flaskapp` for real-time debugging.
- Enable “Auto Sync” in ArgoCD for continuous deployment after Cloud Build updates.
- Avoid triggering Cloud Build on infra-related files like `values.yaml` or `deployment.yaml` using file filters.





