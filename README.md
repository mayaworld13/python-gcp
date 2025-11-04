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
2. Select your **GitHub repository** (connect via OAuth if not already connected).  
3. Choose **Branch:** `main`

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

