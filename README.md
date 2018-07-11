### openshift-datastax

Run datastax on OpenShift

See https://academy.datastax.com/content/docker-tutorial

#### Create a single - dse-server

Create OpenShift project

```
oc new-project cassandra
```

Build datastax image from Dockerfile

```
oc new-build --binary --name=dse -l app=dse --strategy=docker
oc start-build dse --from-dir=. --follow
```

DSE Server Image runs as 999 user, so allow this

```
oc adm policy add-scc-to-user anyuid -z default
```

Create DSE Server

```
oc new-app -f dse-template.yml -p NAMESPACE=$(oc project -q)
```

#### Test

```
oc rsh $(oc get pod --no-headers -lapp=dse --template='{{range .items}}{{.metadata.name}}{{end}}')

$ cqlsh
Connected to Test Cluster at 127.0.0.1:9042.
[cqlsh 5.0.1 | DSE 6.0.1 | CQL spec 3.4.5 | DSE protocol v2]
Use HELP for help.
cqlsh> select * from system_schema.columns;
...
```

Java Test

http://github.com/eformat/fixme

```
$ cd java-cassandra
$ mvn test
```

#### OpsCenter - dse-opscenter

Deploy dse-opscenter

```
oc new-app --docker-image=datastax/dse-opscenter -e DS_LICENSE=accept -l app=dse-opscenter
oc expose svc/dse-opscenter --port=8888

```

Browse to Route URL

- Click Manage existing cluster.
- Enter the IP Address for the DSE Node
```
oc get svc dse -o yaml -o jsonpath='{.spec.clusterIP}'
```
- Choose Install agents manually.

#### Studio - dse-studio

Deploy dse-studio

```
oc new-app --docker-image=datastax/dse-studio -e DS_LICENSE=accept -l app=dse-studio
oc expose svc/dse-studio --port=9091
```

- Click Hamburger -> Connections
- Edit `default localhost` connection
- Enter `Host/IP (comma delimited)` from
```
oc get svc dse -o yaml -o jsonpath='{.spec.clusterIP}'
```

##### TODO

- DSE Suppports clustering
- Add Storage PVC's for images
- OpsCenter Monitoring works, but has error in logs
- ConfigMap for dse-server (cannot inject ENV VARS here it seems) - note: using custom entrypoint.sh in lieu of this
```
oc create configmap cassandra --from-file=cassandra.yaml --dry-run -o yaml | oc apply --force -f-

oc volume dc/dse --add --overwrite \
    --name=cassandra \
    --mount-path=/opt/dse/resources/cassandra/conf/cassandra.yaml \
    --sub-path=cassandra.yaml \
    --source='{"configMap": { "name": "cassandra"}}'

-- need to turn off rewrite of cassandra.yaml
oc set env dc/dse DSE_AUTO_CONF_OFF=true
```
