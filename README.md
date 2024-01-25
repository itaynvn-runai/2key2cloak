# 2 Key 2 Cloak
helm chart that deploys a keycloak server.
## description
includes:
- persistent storage
- ingress/virtualservice exposing
- OpenShift support
- automatically creates an OIDC client

## install
see helm values in next section
```
helm install keycloak 2key2cloak
```

## configuration
### Admin
The admin for the keycloak UI.
| param | description | default value |
|--|--|--|
| `admin.username` | The admin username | kcadmin
| `admin.password` | The admin password | *auto-generated if empty*

### Initial user
the initial "regular" user who will be associated with the OIDC client.
Try to keep the details related for clarity.
| param | description | default value |
|--|--|--|
| `initUser.name.first` | First name | John
| `initUser.name.last` | Last name | Doe
| `initUser.username` | Username | johndoe
| `initUser.email` | Email address | johndoe@mycorp.net
| `initUser.password` | Password | *auto-generated if empty*

###  OIDC client
| param | description | default value |
|--|--|--|
| `clientSettings.clientId` | ID of the OIDC client | oidctest
| `clientSettings.realmName` | Name of the realm | testingrealm

###  Storage
| param | description | default value |
|--|--|--|
| `persistentVolume.size` | Size required for PVC | 10Gi
| `persistentVolume.storageClassName` | Name of the StorageClass (if non-default is required) | 

###  cnvrg
cnvrg related params. can be ignored if not needed.
| param | description | default value |
|--|--|--|
| `cnvrg.clusterDomain` | cnvrg cluster domain | web.mycorp.net
| `cnvrg.operatorVersion` | version of cnvrg operator. can be either v4 or slim | v4

###  host
| param | description | default value |
|--|--|--|
| `host` | the host address where keycloak UI is expected to be reached.
 | keycloak.web.mycorp.net

###  HTTPS
| param | description | default value |
|--|--|--|
| `https.enabled` | will HTTPS be served | false

###  virtualService
| param | description | default value |
|--|--|--|
|`virtualService.enabled`|Wether to use virtualService or not|false|
|`virtualService.namespace`|Namespace where istio lives||
|`virtualService.gateway`|Name of the Istio gateway in use|my-gateway|

###  ingress
| param | description | default value |
|--|--|--|
|`ingress.enabled`|Wether to use ingress or not|false
|`ingress.className`|ingress class to use. if left blank, default class will be taken|
|`ingress.namespace`|namespace where ingress will be created at. if left blank, the namespace of the helm chart will be used.|
|`ingress.tlsSecretName`|the name of the secret that holds the TLS certificate. Only relevant if `https.enabled` is set to true.|chart-example-tls

###  openshift
| param | description | default value |
|--|--|--|
|`openshift.enabled`|if its an openshift deployment. if true, will create a route to expose UI externally, and several other customizations in chart will be made to fit OCP.|false|

