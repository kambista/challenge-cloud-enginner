# Decisiones y trade-offs

## GKE Autopilot, regional

Elegí GKE (Google Kubernetes Engine) en modo Autopilot porque para un servicio de este tamaño no aporta nada administrar node pools. Workload Identity viene siempre habilitado y Google restringe el acceso privilegiado a los nodos; los nodos privados los activé yo en Terraform (`enable_private_nodes`). Pago por lo que piden los pods y no por nodos medio vacíos.

Autopilot no tiene modo zonal, así que el clúster es regional y las réplicas de la API y de Nginx se reparten entre zonas con `topologySpreadConstraints`. El cargo de administración de GKE es de USD 0.10/h por clúster. El crédito mensual de GKE (USD 74.40 por cuenta de billing) cubre el cargo de administración de este clúster; cualquier cargo que exceda el crédito disponible se factura.

Lo que se pierde: no administro directamente los tipos de VM ni los node pools como en Standard (Autopilot permite pedir cierto hardware con Compute Classes, que acá no hizo falta), y los DaemonSets corren con las restricciones de Autopilot, sin la libertad de privilegios que da Standard.

## Acceso al control plane

El clúster tiene nodos privados y el acceso mediante el endpoint IP del control plane está restringido con `authorized_networks`. GitHub Actions entra por el **DNS endpoint**, donde el acceso se controla con IAM (y se le podría sumar VPC Service Controls). Así no tengo que abrir el control plane a los rangos de IP de GitHub (que cambian y son enormes) ni montar un runner self-hosted dentro de la VPC.

## MongoDB dentro del clúster

Es la opción base del reto y la más barata: un StatefulSet con un PersistentVolumeClaim (PVC) de 10 Gi. La API usa un usuario con `readWrite` solo sobre `quotes`; el root queda para backups y operación.

Lo que no me gusta de esta opción y cambiaría en producción:
- Es un solo nodo. Si el pod se reprograma hay unos segundos sin base; la API responde 503 en `/ready` y Nginx deja de mandarle tráfico, pero las escrituras fallan.
- Estado y cómputo en el mismo clúster: un error en el clúster afecta también a los datos.

Para producción iría a MongoDB Atlas con private endpoint (Private Service Connect, PSC) hacia la VPC, o un replica set de 3 nodos con el operador de MongoDB. Atlas resuelve buena parte de la operación de producción: backups con restauración a un punto en el tiempo (PITR), mantenimiento y opciones de cifrado administrado, que para una fintech regulada es lo que más pesa.

## Nginx como Deployment detrás del Ingress GCE

Preferí el Ingress de GKE para conservar el Application Load Balancer gestionado por Google, con su integración nativa con Cloud Armor, certificados administrados y NEGs (Network Endpoint Groups). Con Nginx Ingress Controller la entrada pasa a ser el Service del controlador y esas piezas habría que resolverlas por otro lado. Con el Ingress de GKE, el load balancer (LB) manda tráfico directo a los pods de Nginx (container-native load balancing) y Nginx hace el reverse proxy hacia la API.

Nginx agrega: logs de acceso en JSON con `request_id`, IP real del cliente y `upstream_time`, timeouts y `client_max_body_size` explícitos, rate limit por IP, reintento al otro pod de la API ante un 502/503, y un `/healthz` que no depende de Mongo para el health check del LB.

## HTTPS con nip.io

No tengo dominio propio para el reto, así que el host es `136.82.17.30.nip.io` con un `ManagedCertificate` de Google. HTTP redirige a HTTPS (`FrontendConfig`) y la SSL policy exige TLS 1.2 o más.

Google solo emite y renueva el certificado si el dominio resuelve a la IP del LB. nip.io devuelve esa IP para `136.82.17.30.nip.io`, y en este despliegue el certificado quedó en `Active`. No lo tomaría como garantizado en general: tanto la emisión como las renovaciones dependen de que un servicio de terceros responda cuando Google valida. En producción sería un dominio propio en Cloud DNS.

## Secretos

- Terraform genera las contraseñas (`random_password`) y las guarda en Secret Manager.
- External Secrets Operator (ESO) las sincroniza como Secrets de Kubernetes. Lo elegí sobre el Secrets Store CSI driver (Container Storage Interface) porque la app lee `MONGO_URI` como variable de entorno. Con CSI, los secretos llegan como archivos montados; para tenerlos como variable habría que sincronizarlos a un Secret, y esa sincronización depende de que algún pod monte el volumen.
- ESO y el CronJob de backup se autentican con Workload Identity usando directamente su Kubernetes Service Account (KSA) como principal de IAM, sin una Google Service Account (GSA) intermedia. ESO solo puede leer los 3 secretos de Mongo y el backup solo puede escribir en su bucket.
- La conexión con Secret Manager es un `ClusterSecretStore` en su propio chart (`helm/external-secrets`), limitado al namespace `quotes`. Lo instala Terraform junto con el operador, así los charts de los servicios no llevan el proyecto y el deployer del pipeline no necesita permisos sobre recursos de alcance de clúster.
- Cada servicio declara su propio `ExternalSecret` con solo lo que usa: la API recibe la `mongo-uri`, no la contraseña de root.
- ESO refresca cada hora, pero la app lee `MONGO_URI` al arrancar; por eso la rotación (`scripts/rotate-mongo-secret.sh`) termina con un `rollout restart`.

Trade-offs:
- Las contraseñas también quedan en el state. El bucket es privado y versionado; en producción usaría `ephemeral "random_password"` con `secret_data_wo` (Terraform ≥ 1.11) para que no lleguen al state.
- Con el `ClusterSecretStore` todos los servicios comparten la identidad de ESO. Con más equipos pasaría a un `SecretStore` por namespace, cada uno con su propia KSA.
- El backup usa el usuario root de Mongo; en producción tendría un usuario con el rol `backup`.
- Los secretos usan replicación `auto`; si hubiera requisitos de residencia de datos, usaría `user_managed` limitada a regiones permitidas.

## Terraform

La infraestructura se aplica en dos fases, cada una con su propio state en el mismo bucket.

**Fase 1, `bootstrap/`.** Activa las APIs del proyecto y administra el bucket del state. Ese bucket tiene que existir antes de que Terraform pueda usarlo como backend, así que lo creo con `gcloud storage buckets create` y el stack lo adopta con un bloque `import`. Es la única pieza que nace fuera de Terraform. Las APIs no se deshabilitan en el `destroy` porque otros recursos pueden seguir dependiendo de ellas mientras se destruyen.

**Fase 2, `envs/prd/`.** Con el backend listo, Terraform administra todo lo demás: red, GKE, IAM y Workload Identity Federation, Artifact Registry, secretos, IP y SSL policy del ingress, backups y monitoring. También instala ESO y el `ClusterSecretStore` con `helm_release`: crean recursos de alcance de clúster (CRDs, ClusterRoles), y prefiero que ese permiso lo tenga la infraestructura y no el pipeline de la aplicación, que se queda con `container.developer`.

Otras decisiones:
- **Módulos propios** (`network`, `gke`, `artifact-registry`, `iam-wif`, `secrets`, `edge`, `backup`, `monitoring`) en lugar de los de `terraform-google-modules`. Son chicos, se leen rápido y no arrastran decenas de variables que no uso. Con más entornos, migraría `network` y `gke` a los módulos oficiales.
- `deletion_protection = false` en el clúster y `force_destroy` en el bucket de backups, para que el reto se pueda desmontar con un `destroy`. En producción usaría protecciones contra eliminaciones accidentales y una política de retención acorde a los datos.
- El nombre del bucket del state está fijo en `backend.tf`, porque el bloque `backend` no acepta variables. En otro proyecto hay que cambiar esa línea.

## Helm: un chart por servicio

Hay cuatro charts:

| Chart | Lo despliega | Contenido |
|---|---|---|
| `external-secrets` | Terraform | `ClusterSecretStore` hacia Secret Manager |
| `mongodb` | pipeline | StatefulSet, backup diario, Job que crea los índices |
| `quotes-api` | pipeline | Deployment, HPA, PDB |
| `nginx` | pipeline | reverse proxy, Ingress, certificado |

`mongodb`, `quotes-api` y `nginx` tienen ciclos de vida distintos: la app cambia en cada commit, la base casi nunca. Con charts separados:
- un deploy de la API no toca el StatefulSet,
- `helm rollback quotes-api` no revierte el Ingress ni la base,
- el pipeline solo despliega el chart cuya carpeta cambió.

`external-secrets` va aparte porque es configuración de plataforma compartida por los servicios y crea un recurso de alcance de clúster; por eso lo instala Terraform y no el pipeline.

Cada chart tiene un solo `values.yaml` con los datos de este proyecto. El único valor que cambia en cada deploy es `image.tag`, que el pipeline pasa con `--set`.

## Probes de la API

Sigo lo que propone la app: liveness en `/health` y readiness en `/ready`. El problema es que `/health` devuelve 503 cuando Mongo no responde, así que una caída de la base podría terminar reiniciando todas las réplicas de la API, lo que no ayuda. Lo mitigué con `failureThreshold: 6` y `timeoutSeconds: 5`, para que un pod lento bajo carga no se reinicie. Si pudiera tocar la app, haría que `/health` solo verifique el proceso y dejaría la dependencia de Mongo solo en `/ready`.

## Prueba de carga

Corrí k6 desde mi máquina contra la URL pública: 80 usuarios virtuales durante 10 minutos, 80% lecturas (`GET /quotes`) y 20% escrituras (`POST /quotes`). El servicio sostuvo ~114 req/s con 0.006% de errores, mediana de 201 ms y p95 de 738 ms. El HPA llevó la API de 2 a 6 réplicas a medida que subía la CPU y la devolvió a 2 al terminar, sin reinicios de pods en el camino. Del p95, ~136 ms son solo la red hasta `us-central1`.

Lo que preparé para que la base acompañe:
- Índice `{pair: 1, createdAt: -1}`, porque `GET /quotes` filtra por par y ordena por fecha. Lo crea un Job hook de Helm en cada deploy de Mongo; es idempotente y no requiere tocar la app.
- Readiness de Mongo por `tcpSocket`. Un `mongosh` cada 10 s es un proceso Node completo y se come CPU que la base necesita.
- 500m de CPU y 1 GiB para Mongo, y timeout de 5 s en la liveness de la API para que un pod lento bajo carga no se reinicie.
- HPA al 60% de CPU, con scale-up de hasta 2 pods cada 30 s, para que las réplicas lleguen antes que la latencia.

Con esta arquitectura, Mongo es el primer punto de saturación: agregar réplicas de la API no ayuda si la base ya está al límite. Por eso en producción priorizaría alertas sobre la CPU, conexiones y operaciones lentas de Mongo antes que las de la API.

## Backups

CronJob diario con dos contenedores: `mongodump` con la imagen de mongo y la subida a GCS con `curl` contra la API de Storage, usando el token de Workload Identity del metadata server. Lo hice así para no bajar la imagen de `gcloud` (casi 1 GB) y para que el único permiso necesario sea `storage.objectCreator`: el job puede escribir backups pero no leerlos ni borrarlos.

El restore (`scripts/mongo-restore.sh`) hace streaming desde GCS a `mongorestore` dentro del pod: el archivo no se guarda en disco local y la contraseña de root no sale del pod. Lo probé con un backup de ~30 mil documentos: volvieron completos, con sus índices, en unos 2 segundos y sin cortar la API. El RPO es de 24 h; para bajarlo, en producción sumaría snapshots del disco o PITR.

## CI/CD

- Workload Identity Federation (WIF) con `attribute_condition` sobre los IDs numéricos del repo y del owner, no sobre el nombre: un fork no puede pedir tokens, y un repo borrado y recreado con el mismo nombre tampoco.
- Tags `sha-<commit>` (lo que se despliega) y `latest` (referencia).
- `--atomic` en la API y en Nginx: si el rollout no queda sano, Helm vuelve a la versión anterior solo.
- El smoke test crea un registro y lo busca, así valida el camino completo LB → Nginx → API → Mongo, no solo que el pod responda.
- Los PRs corren `ci.yml`: fmt/validate de Terraform, lint y render de los charts, `nginx -t` con la misma imagen que se despliega, build de la imagen y Trivy. El escaneo de Terraform y Helm bloquea con hallazgos HIGH/CRITICAL; las dos excepciones están en `.trivyignore.yaml` con su motivo y limitadas a su archivo. El escaneo de la imagen es informativo, porque se construye con el `Dockerfile` del reto. No hay `terraform plan` en CI porque necesitaría otra identidad con permisos de lectura sobre todo el proyecto; lo agregaría en fase 2.

## Seguridad

- Nodos privados; la única salida es Cloud NAT.
- Rate limit en Nginx: 10 req/s por IP con burst de 20, respondiendo 429. La IP del cliente sale de la penúltima entrada de `X-Forwarded-For` (la que agrega el LB de Google), no de la primera, que el cliente puede inventar.
- Cloud Armor está en Terraform (reglas preconfiguradas de SQLi y XSS, rate limit por IP y geobloqueo con `allowed_countries`), pero quedó apagado (`enable_cloud_armor = false`): al crear la policy, el proyecto del reto respondió `Quota 'SECURITY_POLICIES' exceeded. Limit: 0`, así que no tenía disponible esa cuota. Si se activa, el `BackendConfig` de Nginx la toma con `ingress.securityPolicy: quotes-armor`. Es lo primero que encendería en producción: el rate limit en Nginx es por réplica y no filtra ataques de capa 7.
- NetworkPolicies: Mongo solo acepta a la API y al backup; la API solo a Nginx; Nginx solo a los rangos del LB.
- Contenedores sin root, sin escalamiento de privilegios, sin capabilities y con filesystem de solo lectura (salvo Mongo, que necesita escribir).
- Imágenes de terceros (Nginx, Mongo, curl) fijadas por digest (`tag@sha256:…`): un tag que se mueve no cambia lo que corre en el clúster sin pasar por un commit. La de la app se despliega por `sha-<commit>`.
- Sin llaves JSON en ningún lado.

## Observabilidad

Lo configurado y lo que agregaría en producción está en el [README](../README.md#observabilidad). Las decisiones detrás:

- Las métricas de tráfico y latencia salen del Load Balancer y no de la app: miden lo que percibe el cliente, incluidos los errores que nunca llegan al clúster, y no requieren instrumentar el código del reto.
- Los logs del LB están con sampling al 100% porque el volumen del reto es bajo y entra en la cuota gratuita de Cloud Logging. Con tráfico real lo bajaría a 10%, que sigue siendo representativo.
- La alerta de 5xx está en 5% sostenido durante 5 minutos, aunque el objetivo es menos de 1%. Con poco tráfico, un par de errores aislados ya supera el 1%, y una alerta que suena sin motivo deja de leerse.
- El uptime check exige que falle desde más de una región antes de alertar, para no confundir un problema de red de una región de Google con una caída del servicio.
- Cada alerta trae en su documentación los primeros comandos de diagnóstico, para que quien la reciba no dependa de conocer el proyecto.

## Pendiente

Ordenado por el riesgo que reduce:

1. **Mongo con alta disponibilidad.** Hoy es el único punto de falla: una sola réplica con disco zonal y un RPO de 24 h. El siguiente paso es un replica set de tres miembros en zonas distintas, o Atlas con private endpoint y restauración a un punto en el tiempo.
2. **Cloud Armor.** Ya está escrito en Terraform; falta un proyecto con cuota. El rate limit de Nginx es por réplica y no filtra ataques de capa 7.
3. **Rollback automático tras un smoke test fallido.** `--atomic` solo cubre los pods que no llegan a `Ready`; un deploy que arranca bien pero responde mal hoy depende de que alguien vea el run en rojo.
4. **Dominio propio en Cloud DNS**, para no depender de nip.io en la renovación del certificado.
5. **Alertas por SLO, edad del último backup y antigüedad de las cotizaciones**, las métricas que hoy no tienen alerta.
6. **`terraform plan` en los PRs** con una identidad de solo lectura, para revisar cambios de infraestructura antes del merge.
7. **Argo CD y canary con Argo Rollouts**, para que el clúster tome los cambios desde el repo en vez de recibir `helm upgrade` desde el pipeline.
8. **Restore de prueba automático**, que valide cada cierto tiempo que los backups realmente sirven.
