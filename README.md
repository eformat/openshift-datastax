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

#### (optional) Add a PVC to dse-server

Add single dse-server storage

```
oc create -f - <<EOF
{
  "apiVersion": "v1",
  "kind": "PersistentVolumeClaim",
  "metadata": {
    "name": "cassandra-data"
  },
  "spec": {
    "accessModes": [ "ReadWriteOnce" ],
    "resources": {
     "requests": {
        "storage": "1Gi"
      }
    }
  }
}
EOF

oc volume dc/dse --add --overwrite -t persistentVolumeClaim --claim-name=cassandra-data --name=dse-volume-3 --mount-path=/var/lib/cassandra/
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

Simple Java Tests

```
git clone https://github.com/eformat/java-cassandra
```

Port forward native connection port

```
oc port-forward $(oc get pod --no-headers -lapp=dse --template='{{range .items}}{{.metadata.name}}{{end}}') 9042:9042
```

Run

```
cd java-cassandra
mvn test
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

#### Create Clustered dse-server

To create 3 node dse-server cluster

```
oc new-project cassandra
oc new-build --binary --name=dse -l app=dse --strategy=docker
oc start-build dse --from-dir=. --follow
oc adm policy add-scc-to-user anyuid -z default
oc apply -f ./cassandra-svc.yaml
oc apply -f ./cassandra-stateful-set.yaml
```

You can scale the `StatefulSet` using, but you will need to update `SEEDS` env variable:

```
oc scale --replicas=5 statefulset/cassandra
```

We can test it out

```
oc rsh cassandra-0
cqlsh

CREATE KEYSPACE IF NOT EXISTS hr_keyspace
  WITH REPLICATION = {
   'class' : 'SimpleStrategy',
   'replication_factor' : 2
  }
AND durable_writes = true;

use hr_keyspace;
CREATE TABLE employee( emp_id int PRIMARY KEY, emp_name text, emp_city text, emp_sal varint, emp_phone varint);
INSERT INTO employee (emp_id, emp_name, emp_city,emp_sal,emp_phone) VALUES(1,'David', 'San Francisco', 50000, 983210987);
INSERT INTO employee (emp_id, emp_name, emp_city,emp_sal,emp_phone) VALUES(2,'Robin', 'San Jose', 55000, 9848022339);
INSERT INTO employee (emp_id, emp_name, emp_city,emp_sal,emp_phone) VALUES(3,'Bob', 'Austin', 45000, 9848022330);
INSERT INTO employee (emp_id, emp_name, emp_city,emp_sal,emp_phone) VALUES(4, 'Monica','San Jose', 55000, 9458022330);

select * from employee;

-- clean up
oc delete statefulset,pvc,svc -l app=cassandra
oc adm policy remove-scc-from-user anyuid -z default -n cassandra
```

##### TODO

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
