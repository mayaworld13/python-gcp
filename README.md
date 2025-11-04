#  Flask App Deployment on GKE using Cloud Build, Helm & Argo CD

> End-to-end, automated CI/CD + GitOps for a Flask app using:
> **Cloud Build** (CI) → **Artifact Registry** (images) → **Helm** (packaging) → **Argo CD** (GitOps CD) → **GKE + NGINX Ingress** (hosting & exposure)


---

##  Overview (What & Why)

- **What:** Build and deploy a Flask web app to GKE automatically whenever you push code to GitHub.
- **Why:** Automates build/test/deploy, keeps infrastructure declarative (GitOps), and makes rollbacks and visibility easy using Argo CD.

## Architecture diagram 

<img width="1699" height="806" alt="diagram-export-11-4-2025-12_33_43-PM" src="https://github.com/user-attachments/assets/48757146-ea3f-4019-96e0-61985c4aa946" />

Main flow:
1. Developer pushes code to GitHub.
2. Cloud Build builds a Docker image and pushes it to Artifact Registry.
3. Cloud Build updates the Helm `values.yaml` with the new image tag and pushes that change to GitHub.
4. GitHub webhook notifies Argo CD.
5. Argo CD auto-syncs the Helm chart and deploys the updated app on GKE.
6. NGINX Ingress exposes the app (e.g., `flask.mayaworld.tech`).

> **Important:** The Cloud Build trigger is configured to **not** re-run for commits that only contain changes to `deployment.yaml` or `values.yaml` or `README.md` (this prevents infinite build loops).

---

## 📁 Repo structure
<img width="245" height="306" alt="image" src="https://github.com/user-attachments/assets/60d2def0-ea6e-4448-a8cf-fbcabd5c2354" />

