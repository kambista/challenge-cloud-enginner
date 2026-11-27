# Decisiones Tecnicas y Trade-offs

## 1. GKE Standard (Zonal) vs. GKE Autopilot / Regional
- **Decision:** GKE Standard Zonal (`us-central1-a`) con 2 nodos `e2-medium` privados.
- **Trade-off:** Un cluster regional triplica el costo al replicar en 3 zonas. Con GKE Standard Zonal y 2 nodos se toleran fallos de pod/nodo manteniendo el costo bajo (~3x menor). En produccion real migraria a GKE Regional (3 zonas) con `PodDisruptionBudgets` y Cluster Autoscaler.

## 2. MongoDB en GKE (StatefulSet) vs. MongoDB Atlas
- **Decision:** MongoDB 7.0 en `StatefulSet` + `PVC` (`standard-rwo` 5Gi) dentro del cluster.
- **Trade-off:** Mantiene todo autocontenido en la misma VPC sin dependencias externas. En produccion fintech real usaria **MongoDB Atlas** multi-zona con Private Service Connect y backups point-in-time.

## 3. GCE Ingress + Nginx Reverse Proxy vs. Nginx Ingress Controller
- **Decision:** GCE Ingress nativo (HTTP(S) LB + SSL administrado) apuntando a un Deployment de Nginx.
- **Trade-off:** Aprovecha la IP estatica global y SSL administrado sin perder control sobre `nginx.conf` (rate limiting, timeouts y DNS dinamico), a cambio de un salto interno sub-milisegundo.

## 4. CI/CD: Workload Identity Federation vs. JSON Keys
- **Decision:** OIDC restringido por `attribute_condition` al repositorio `Fabri-99/challenge-cloud-enginner`, eliminando credenciales estaticas.

## 5. Mejoras para Fase 2 en Produccion
1. **External Secrets Operator (ESO):** Rotacion automatica desde Secret Manager.
2. **Google Cloud Armor (WAF):** Reglas OWASP Top 10 y proteccion DDoS.
3. **GitOps y Canary:** ArgoCD y Argo Rollouts.
4. **Backups:** `CronJob` diario con `mongodump` cifrado hacia Cloud Storage.
